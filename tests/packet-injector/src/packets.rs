//! The injector's packet tree: a directory of `tests.toml` files, each
//! naming one or more packet tests and optionally nesting subcategories.

use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};

const TESTS_FILE: &str = "tests.toml";

#[derive(Deserialize, Default)]
struct Meta {
    title: Option<String>,
    description: Option<String>,
    #[serde(default)]
    test: Vec<TestData>,
}

#[derive(Deserialize, Clone, Default)]
struct TestData {
    name: String,
    label: Option<String>,
    description: Option<String>,
    packet: Option<String>,
}

/// One test: where it lives, its key, and its fields.
#[derive(Clone)]
pub struct Test {
    directory: PathBuf,
    data: TestData,
    root: PathBuf,
}

impl Test {
    pub fn packet(&self) -> &str {
        self.data.packet.as_deref().unwrap_or("")
    }

    pub fn label(&self) -> &str {
        self.data.label.as_deref().unwrap_or(&self.data.name)
    }

    pub fn description(&self) -> &str {
        self.data.description.as_deref().unwrap_or("")
    }

    /// The `<dir>/<name>` address used with `-t`.
    pub fn path(&self) -> String {
        let rel = self
            .directory
            .strip_prefix(&self.root)
            .unwrap_or(&self.directory);
        if rel.as_os_str().is_empty() {
            self.data.name.clone()
        } else {
            format!("{}/{}", rel.display(), self.data.name)
        }
    }
}

/// Parses the `tests.toml` in a directory. Empty (not an error) if there is
/// none or it fails to parse as a table with the expected shape -- a
/// directory with no packets of its own, just subcategories, is normal.
fn load_toml(directory: &Path) -> Meta {
    let sidecar = directory.join(TESTS_FILE);
    let Ok(text) = fs::read_to_string(&sidecar) else {
        return Meta::default();
    };
    toml::from_str(&text).unwrap_or_else(|e| {
        eprintln!("Error: could not parse {}: {e}", sidecar.display());
        std::process::exit(1);
    })
}

pub fn title(directory: &Path) -> Option<String> {
    load_toml(directory).title
}

pub fn description(directory: &Path) -> Option<String> {
    load_toml(directory).description
}

/// Test objects defined directly in a directory's `tests.toml`, in the
/// order they're written there.
pub fn tests_in(directory: &Path, root: &Path) -> Vec<Test> {
    load_toml(directory)
        .test
        .into_iter()
        .map(|data| Test {
            directory: directory.to_path_buf(),
            data,
            root: root.to_path_buf(),
        })
        .collect()
}

pub(crate) fn subdirs(directory: &Path) -> Vec<PathBuf> {
    let Ok(entries) = fs::read_dir(directory) else {
        return Vec::new();
    };
    let mut dirs: Vec<PathBuf> = entries
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .collect();
    dirs.sort();
    dirs
}

/// Every test at or under a directory: this directory's own tests, in
/// their `tests.toml` order, then each subdirectory in turn (subdirectories
/// themselves ordered alphabetically, same as [`subdirs`]).
pub fn all_tests(directory: &Path, root: &Path) -> Vec<Test> {
    let mut result = tests_in(directory, root);
    for sub in subdirs(directory) {
        result.extend(all_tests(&sub, root));
    }
    result
}

pub enum FindResult {
    Found(Test),
    NotFound,
    Ambiguous(Vec<String>),
}

/// Resolves a `<dir>/<name>` address, or a unique bare name, to a Test.
pub fn find_test(root: &Path, address: &str) -> FindResult {
    let address = address.trim_matches('/');
    if let Some((dirpart, name)) = address.rsplit_once('/') {
        let directory = match root.join(dirpart).canonicalize() {
            Ok(d) => d,
            Err(_) => return FindResult::NotFound,
        };
        let root_canon = root.canonicalize().unwrap_or_else(|_| root.to_path_buf());
        // Keep an address from walking out of the tree.
        if !directory.starts_with(&root_canon) || !directory.is_dir() {
            return FindResult::NotFound;
        }
        return match tests_in(&directory, root)
            .into_iter()
            .find(|t| t.data.name == name)
        {
            Some(t) => FindResult::Found(t),
            None => FindResult::NotFound,
        };
    }

    let matches: Vec<Test> = all_tests(root, root)
        .into_iter()
        .filter(|t| t.data.name == address)
        .collect();
    match matches.len() {
        0 => FindResult::NotFound,
        1 => FindResult::Found(matches.into_iter().next().unwrap()),
        _ => FindResult::Ambiguous(matches.iter().map(Test::path).collect()),
    }
}

/// Prints every test in the tree: address, label, description.
pub fn list_tree(root: &Path) {
    let tests = all_tests(root, root);
    if tests.is_empty() {
        println!("(no tests found under {})", root.display());
        return;
    }
    let addr_w = tests.iter().map(|t| t.path().len()).max().unwrap_or(0);
    let lbl_w = tests.iter().map(|t| t.label().len()).max().unwrap_or(0);
    for t in &tests {
        println!(
            "{:<addr_w$}  {:<lbl_w$}  {}",
            t.path(),
            t.label(),
            t.description()
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn write(dir: &Path, rel: &str, body: &str) {
        let p = dir.join(rel);
        fs::create_dir_all(p.parent().unwrap()).unwrap();
        fs::write(p, body).unwrap();
    }

    fn sample_tree() -> tempfile::TempDir {
        let d = tempfile::tempdir().unwrap();
        write(
            d.path(),
            "tests.toml",
            "title = \"root\"\ndescription = \"d\"\n",
        );
        write(
            d.path(),
            "cat/tests.toml",
            "title = \"cat\"\ndescription = \"d\"\n\n\
             [[test]]\nname = \"one\"\nlabel = \"One\"\npacket = \"A>B:one\"\n",
        );
        write(
            d.path(),
            "cat/sub/tests.toml",
            "title = \"sub\"\ndescription = \"d\"\n\n[[test]]\nname = \"two\"\npacket = \"A>B:two\"\n",
        );
        d
    }

    #[test]
    fn resolves_tests_by_address() {
        let d = sample_tree();
        match find_test(d.path(), "cat/one") {
            FindResult::Found(t) => assert_eq!(t.packet(), "A>B:one"),
            _ => panic!("not found"),
        }
        // Bare name, unambiguous: found tree-wide without the "cat/sub/" prefix.
        match find_test(d.path(), "two") {
            FindResult::Found(t) => assert_eq!(t.path(), "cat/sub/two"),
            _ => panic!("not found"),
        }
        // Every test resolves by the address it reports for itself.
        for t in all_tests(d.path(), d.path()) {
            match find_test(d.path(), &t.path()) {
                FindResult::Found(found) => assert_eq!(found.packet(), t.packet()),
                _ => panic!("{} does not resolve", t.path()),
            }
        }
    }

    #[test]
    fn tests_list_in_file_order_not_alphabetical() {
        let d = tempfile::tempdir().unwrap();
        write(
            d.path(),
            "tests.toml",
            "title = \"root\"\ndescription = \"d\"\n\n\
             [[test]]\nname = \"zebra\"\npacket = \"A>B:z\"\n\n\
             [[test]]\nname = \"apple\"\npacket = \"A>B:a\"\n\n\
             [[test]]\nname = \"mango\"\npacket = \"A>B:m\"\n",
        );
        let found = tests_in(d.path(), d.path());
        let names: Vec<&str> = found.iter().map(|t| t.data.name.as_str()).collect();
        assert_eq!(names, ["zebra", "apple", "mango"]);
    }
}
