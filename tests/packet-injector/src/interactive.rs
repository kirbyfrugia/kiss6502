//! The interactive picker: a nested menu you descend into subdirectories
//! of, to pick a test to inject. Every selection is a single keypress,
//! acted on immediately -- there's no in-band way to quit from here,
//! ctrl-c is the only way out.

use crate::packets::{self, Test, all_tests, subdirs, tests_in};
use crate::settings::Settings;
use kisstty_harness::{MENU_RULE, is_back, item_index, item_label};
use std::io::Write;
use std::path::{Path, PathBuf};

enum Entry {
    Dir(PathBuf),
    Test(Test),
}

/// `current` is both where the picker starts and where it leaves off, so a
/// caller that runs this in a loop lands back in the same directory each
/// time rather than at the root. `None` on EOF -- the caller decides what
/// that means, not this function.
///
/// `menu_key` returns one keypress at a time (`None` on EOF); `line` is
/// only used for the settings submenu's free-text value prompts. Real use
/// reads stdin, tests hand both canned values.
pub fn pick_interactive(
    root: &Path,
    current: &mut PathBuf,
    menu_key: &mut impl FnMut() -> Option<String>,
    line: &mut impl FnMut() -> Option<String>,
) -> Option<Test> {
    loop {
        let subdirs = subdirs(current);
        let tests = tests_in(current, root);

        let rel = current.strip_prefix(root).unwrap_or(current);
        let header = if rel.as_os_str().is_empty() {
            "packets".to_string()
        } else {
            format!("packets/{}", rel.display())
        };
        println!();
        println!("{MENU_RULE}");
        match packets::title(current) {
            Some(title) => println!("{header}/  -  {title}"),
            None => println!("{header}/"),
        }
        if let Some(description) = packets::description(current) {
            println!("  {description}");
        }

        let mut entries = Vec::new();
        for d in &subdirs {
            let count = all_tests(d, root).len();
            let name = d.file_name().unwrap().to_string_lossy().into_owned();
            let mut label = format!("{name}/  ({count} tests)");
            if let Some(title) = packets::title(d) {
                label += &format!("  -  {title}");
            }
            entries.push((label, Entry::Dir(d.clone())));
        }

        for t in tests {
            let label = if t.description().is_empty() {
                t.label().to_string()
            } else {
                format!("{}  -  {}", t.label(), t.description())
            };
            entries.push((label, Entry::Test(t)));
        }

        if *current != root {
            println!("  0) back");
        }
        for (i, (label, _)) in entries.iter().enumerate() {
            println!("  {}) {label}", item_label(i).expect("under 35 entries"));
        }
        if *current == root {
            let settings = Settings::load();
            println!("  .) settings");
            println!("        serial port: {}", settings.serial_port);
            println!("        tcp port:    {}", settings.tcp_port);
            println!(
                "        using:       {}",
                if settings.use_serial { "serial" } else { "tcp" }
            );
        }
        println!("  (ctrl-c to quit)");

        print!("Select: ");
        let _ = std::io::stdout().flush();
        let Some(key) = menu_key() else {
            println!();
            return None;
        };
        let choice = key.trim();
        if *current == root && choice == "." {
            edit_settings(menu_key, line);
            continue;
        }
        if *current != root && is_back(choice) {
            *current = current.parent().unwrap().to_path_buf();
            continue;
        }
        let Some(n) = choice
            .chars()
            .next()
            .filter(|_| choice.chars().count() == 1)
        else {
            println!("Invalid selection, try again.");
            continue;
        };
        let Some(i) = item_index(n).filter(|&i| i < entries.len()) else {
            println!("Invalid selection, try again.");
            continue;
        };

        match entries.into_iter().nth(i).unwrap().1 {
            Entry::Test(t) => return Some(t),
            Entry::Dir(dir) => *current = dir,
        }
    }
}

fn edit_settings(
    menu_key: &mut impl FnMut() -> Option<String>,
    line: &mut impl FnMut() -> Option<String>,
) {
    let mut settings = Settings::load();
    loop {
        println!();
        println!("{MENU_RULE}");
        println!("  0) back");
        println!("settings");
        println!("  1) serial port: {}", settings.serial_port);
        println!("  2) tcp port: {}", settings.tcp_port);
        println!(
            "  3) using: {}",
            if settings.use_serial { "serial" } else { "tcp" }
        );
        println!("  (ctrl-c to quit)");
        print!("Select: ");
        let _ = std::io::stdout().flush();
        let Some(key) = menu_key() else { return };
        let choice = key.trim();
        if is_back(choice) {
            return;
        }
        match choice {
            "1" => {
                print!("serial port [{}], Enter to keep: ", settings.serial_port);
                let _ = std::io::stdout().flush();
                let Some(value_line) = line() else { continue };
                let value = value_line.trim();
                if !value.is_empty() {
                    settings.serial_port = value.to_string();
                    settings.save();
                }
            }
            "2" => {
                print!("tcp port [{}], Enter to keep: ", settings.tcp_port);
                let _ = std::io::stdout().flush();
                let Some(value_line) = line() else { continue };
                let value = value_line.trim();
                if !value.is_empty() {
                    match value.parse() {
                        Ok(port) => {
                            settings.tcp_port = port;
                            settings.save();
                        }
                        Err(_) => println!("not a valid port number"),
                    }
                }
            }
            "3" => {
                settings.use_serial = !settings.use_serial;
                settings.save();
            }
            _ => println!("Invalid selection, try again."),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

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
        d
    }

    fn canned(lines: &[&str]) -> impl FnMut() -> Option<String> {
        let mut lines: std::collections::VecDeque<String> =
            lines.iter().map(|s| s.to_string()).collect();
        move || lines.pop_front()
    }

    #[test]
    fn navigates_and_picks_a_test() {
        let d = sample_tree();
        // descend into "cat" (1); bad input reprompts twice; 0 back to
        // root; descend again (1); pick "one" (its only entry, so 1).
        let mut menu_key = canned(&["1", "nope", "9", "0", "1", "1"]);
        let mut current = d.path().to_path_buf();
        let t = pick_interactive(d.path(), &mut current, &mut menu_key, &mut canned(&[]))
            .expect("a test should be picked");
        assert_eq!(t.packet(), "A>B:one");
    }

    #[test]
    fn eof_returns_none() {
        let d = sample_tree();
        let mut current = d.path().to_path_buf();
        assert!(
            pick_interactive(d.path(), &mut current, &mut canned(&[]), &mut canned(&[])).is_none()
        );
    }

    #[test]
    fn resumes_where_it_left_off() {
        let d = sample_tree();
        write(
            d.path(),
            "cat/tests.toml",
            "title = \"cat\"\ndescription = \"d\"\n\n\
             [[test]]\nname = \"one\"\npacket = \"A>B:one\"\n\n\
             [[test]]\nname = \"two\"\npacket = \"A>B:two\"\n",
        );

        // Descend into cat/ and hit EOF, leaving `current` there.
        let mut current = d.path().to_path_buf();
        pick_interactive(
            d.path(),
            &mut current,
            &mut canned(&["1"]),
            &mut canned(&[]),
        );
        assert_eq!(current, d.path().join("cat"));

        // A fresh call starting from that same `current` sees cat/'s tests
        // directly, not the root.
        let t = pick_interactive(
            d.path(),
            &mut current,
            &mut canned(&["2"]),
            &mut canned(&[]),
        )
        .expect("a test should be picked");
        assert_eq!(t.packet(), "A>B:two");
    }
}
