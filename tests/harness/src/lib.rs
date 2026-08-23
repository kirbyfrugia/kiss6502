//! Shared plumbing for the kisstty test tools.
//!
//! Both `packet-injector` and `scenario-runner` need the same fiddly core:
//! run a temporary direwolf, turn a TNC2 packet into 1200 baud audio, feed it
//! in, and read back what direwolf logged. That core is where the subtle
//! bugs live, so it lives here once.
//!
//! This crate has no CLI and prints nothing. Callers own their own output.
//!
//! The timing behaviour in here is not arbitrary; it was arrived at against
//! real hardware, and changing it breaks things in ways that look like
//! flaky hardware, not a bug.

mod direwolf;
mod escape;
mod lorem;
mod serial;
mod terminal;

pub use direwolf::{
    Direwolf, KISS_PORT, TRAILING_SILENCE, kiss_port_busy, render_conf, render_conf_text,
};
pub use escape::{contains, escape, unescape};
pub use lorem::LoremSource;
pub use serial::Serial;
pub use terminal::{RawSession, raw_session, read_menu_key, read_menu_line};

/// Anything that should stop the run with a message, not a panic.
pub type HarnessError = String;

/// Whether a line of interactive input means "go back a level". `\x1b` is
/// what [`read_menu_key`]/[`read_menu_line`] return for a bare Esc; `..`/`b`/
/// `back` are for anywhere that just reads plain lines instead (piped
/// input, tests).
pub fn is_back(input: &str) -> bool {
    input == "\u{1b}" || matches!(input, ".." | "b" | "back")
}

pub fn item_label(index: usize) -> Option<char> {
    match index {
        0..=8 => Some((b'1' + index as u8) as char),
        9..=34 => Some((b'A' + (index - 9) as u8) as char),
        _ => None,
    }
}

pub fn item_index(ch: char) -> Option<usize> {
    match ch.to_ascii_uppercase() {
        c @ '1'..='9' => Some(c as usize - '1' as usize),
        c @ 'A'..='Z' => Some(9 + (c as usize - 'A' as usize)),
        _ => None,
    }
}

/// Stops whatever direwolf is running (signals it and removes its temp
/// files) and puts the terminal back if a menu read or repeat-step key
/// check left it in raw mode. Safe to call from a signal handler -- both
/// halves only ever touch static state. Callers installing this as a signal
/// handler must `process::exit` immediately after, with nothing else
/// running in between -- see [`direwolf::stop_active_direwolf`]'s doc
/// comment on why.
pub fn emergency_stop() {
    direwolf::stop_active_direwolf();
    terminal::restore();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn item_label_and_index_round_trip_all_35_slots() {
        let labels: String = (0..35).map(|i| item_label(i).unwrap()).collect();
        assert_eq!(labels, "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ");
        for (i, ch) in labels.chars().enumerate() {
            assert_eq!(item_index(ch), Some(i));
            assert_eq!(item_index(ch.to_ascii_lowercase()), Some(i));
        }
        assert_eq!(item_label(35), None);
        assert_eq!(item_index('0'), None);
        assert_eq!(item_index('!'), None);
    }
}
