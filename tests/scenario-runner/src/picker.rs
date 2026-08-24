//! Interactive picker: descend from `scenarios/` into a platform directory,
//! then pick a scenario file. Every selection is a single keypress, acted
//! on immediately -- there's no in-band way to quit from here, ctrl-c is
//! the only way out.

use crate::settings::Settings;
use kisstty_harness::{MENU_RULE, is_back, item_index, item_label};
use std::io::Write;
use std::path::{Path, PathBuf};

enum Entry {
    Dir(PathBuf),
    File(PathBuf),
}

/// `current` is both where the picker starts and where it leaves off, so a
/// caller that runs this in a loop lands back in the same directory each
/// time rather than at the root.
pub fn pick_scenario(
    root: &Path,
    current: &mut PathBuf,
    menu_key: &mut impl FnMut() -> Option<String>,
    line: &mut impl FnMut() -> Option<String>,
) -> Option<PathBuf> {
    loop {
        let mut items: Vec<PathBuf> = std::fs::read_dir(&*current)
            .ok()?
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .collect();
        items.sort();

        let mut entries = Vec::new();
        for p in items {
            if p.is_dir() {
                let name = p.file_name().unwrap().to_string_lossy().into_owned();
                entries.push((format!("{name}/"), Entry::Dir(p)));
            } else if p.extension().is_some_and(|e| e == "toml") {
                let name = p.file_name().unwrap().to_string_lossy().into_owned();
                entries.push((name, Entry::File(p)));
            }
        }

        let rel = current.strip_prefix(root).unwrap_or(current);
        let header = if rel.as_os_str().is_empty() {
            "scenarios".to_string()
        } else {
            format!("scenarios/{}", rel.display())
        };
        println!();
        println!("{MENU_RULE}");
        println!("{header}/");

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
            Entry::File(p) => return Some(p),
            Entry::Dir(p) => *current = p,
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
        println!(
            "  1) serial port (for atari scenarios): {}",
            settings.serial_port
        );
        println!("  2) tcp port (for rust scenarios): {}", settings.tcp_port);
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
            _ => println!("Invalid selection, try again."),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;

    fn write(dir: &Path, rel: &str) {
        let p = dir.join(rel);
        std::fs::create_dir_all(p.parent().unwrap()).unwrap();
        std::fs::write(p, "").unwrap();
    }

    fn canned(lines: &[&str]) -> impl FnMut() -> Option<String> {
        let mut lines: VecDeque<String> = lines.iter().map(|s| s.to_string()).collect();
        move || lines.pop_front()
    }

    #[test]
    fn navigates_into_a_platform_and_picks_a_file() {
        let d = tempfile::tempdir().unwrap();
        write(d.path(), "atari/acks.toml");
        write(d.path(), "rust/acks.toml");

        // "atari/" and "rust/" sort before any files, alphabetically first.
        let mut menu_key = canned(&["1", "1"]);
        let mut line = canned(&[]);
        let mut current = d.path().to_path_buf();
        let picked = pick_scenario(d.path(), &mut current, &mut menu_key, &mut line)
            .expect("a scenario should be picked");
        assert_eq!(picked, d.path().join("atari/acks.toml"));
    }

    #[test]
    fn eof_returns_none() {
        let d = tempfile::tempdir().unwrap();
        write(d.path(), "atari/acks.toml");
        let mut current = d.path().to_path_buf();
        assert!(
            pick_scenario(d.path(), &mut current, &mut canned(&[]), &mut canned(&[])).is_none()
        );
    }

    #[test]
    fn resumes_where_it_left_off() {
        let d = tempfile::tempdir().unwrap();
        write(d.path(), "atari/acks.toml");
        write(d.path(), "atari/dedup.toml");
        write(d.path(), "rust/acks.toml");

        // Descend into atari/ and pick nothing (EOF), leaving `current` there.
        let mut current = d.path().to_path_buf();
        pick_scenario(
            d.path(),
            &mut current,
            &mut canned(&["1"]),
            &mut canned(&[]),
        );
        assert_eq!(current, d.path().join("atari"));

        // A fresh call starting from that same `current` sees atari/'s
        // files directly, not the root.
        let picked = pick_scenario(
            d.path(),
            &mut current,
            &mut canned(&["2"]),
            &mut canned(&[]),
        )
        .expect("a scenario should be picked");
        assert_eq!(picked, d.path().join("atari/dedup.toml"));
    }
}
