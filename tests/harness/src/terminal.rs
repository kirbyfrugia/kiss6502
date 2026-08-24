//! Reading menu input: a line at a time, or one instant keypress at a time.

use std::io::{IsTerminal, Read, Write};
use std::os::fd::AsRawFd;
use std::sync::Mutex;

/// The terminal's mode from just before we last switched it to raw, if
/// we're currently in the middle of a raw read. Lets a signal handler put
/// the terminal back without reaching into whatever's blocked reading it.
static SAVED_TERMIOS: Mutex<Option<libc::termios>> = Mutex::new(None);

fn set_raw(fd: i32) -> Option<libc::termios> {
    let mut term: libc::termios = unsafe { std::mem::zeroed() };
    if unsafe { libc::tcgetattr(fd, &mut term) } != 0 {
        return None;
    }
    let original = term;
    term.c_lflag &= !(libc::ICANON | libc::ECHO);
    term.c_cc[libc::VMIN] = 1;
    term.c_cc[libc::VTIME] = 0;
    unsafe { libc::tcsetattr(fd, libc::TCSANOW, &term) };
    Some(original)
}

/// Restores the terminal if a menu read left it in raw mode. Safe to call
/// even when nothing needs restoring, and safe from a signal handler --
/// see [`emergency_stop`](crate::emergency_stop).
pub fn restore() {
    if let Some(term) = SAVED_TERMIOS.lock().unwrap().take() {
        unsafe { libc::tcsetattr(std::io::stdin().as_raw_fd(), libc::TCSANOW, &term) };
    }
}

/// Reads one line of menu input: a normal, backspace-editable, Enter
/// terminated line. Falls back to plain line reading when stdin isn't a
/// terminal (piped input, tests don't go through this at all).
pub fn read_menu_line() -> Option<String> {
    let stdin = std::io::stdin();
    if !stdin.is_terminal() {
        return read_plain_line();
    }
    let fd = stdin.as_raw_fd();
    let Some(original) = set_raw(fd) else {
        return read_plain_line();
    };
    *SAVED_TERMIOS.lock().unwrap() = Some(original);

    let mut buf = String::new();
    let mut byte = [0u8; 1];
    let result = loop {
        match stdin.lock().read(&mut byte) {
            Ok(0) | Err(_) => break None,
            Ok(_) => {}
        }
        match byte[0] {
            b'\r' | b'\n' => {
                print!("\r\n");
                let _ = std::io::stdout().flush();
                break Some(buf);
            }
            0x7f | 0x08 => {
                if buf.pop().is_some() {
                    print!("\x08 \x08");
                    let _ = std::io::stdout().flush();
                }
            }
            b => {
                buf.push(b as char);
                print!("{}", b as char);
                let _ = std::io::stdout().flush();
            }
        }
    };

    unsafe { libc::tcsetattr(fd, libc::TCSANOW, &original) };
    SAVED_TERMIOS.lock().unwrap().take();
    result
}

/// Reads one menu selection: a single keypress, acted on immediately with
/// no Enter needed -- letters come back uppercased, so callers don't have
/// to case-fold themselves. Falls back to plain line reading when stdin
/// isn't a terminal (piped input, tests don't go through this at all).
pub fn read_menu_key() -> Option<String> {
    let stdin = std::io::stdin();
    if !stdin.is_terminal() {
        return read_plain_line();
    }
    let fd = stdin.as_raw_fd();
    let Some(original) = set_raw(fd) else {
        return read_plain_line();
    };
    *SAVED_TERMIOS.lock().unwrap() = Some(original);

    let mut byte = [0u8; 1];
    let result = match stdin.lock().read(&mut byte) {
        Ok(0) | Err(_) => None,
        Ok(_) => {
            let ch = (byte[0] as char).to_ascii_uppercase();
            print!("{ch}\r\n");
            let _ = std::io::stdout().flush();
            Some(ch.to_string())
        }
    };

    unsafe { libc::tcsetattr(fd, libc::TCSANOW, &original) };
    SAVED_TERMIOS.lock().unwrap().take();
    result
}

fn read_plain_line() -> Option<String> {
    let mut line = String::new();
    match std::io::stdin().read_line(&mut line) {
        Ok(0) | Err(_) => None,
        Ok(_) => Some(line),
    }
}

/// A scoped raw-mode session for checking a keypress without blocking, e.g.
/// a "press q to stop" during an otherwise unattended repeating step.
/// Restores the terminal when dropped, including on an early return, so a
/// caller never has to remember to put it back itself.
pub struct RawSession {
    active: bool,
}

/// Starts a [`RawSession`]. A no-op session (its `poll_key` always returns
/// `None`) when stdin isn't a terminal, so piped input just never sees a key.
pub fn raw_session() -> RawSession {
    let stdin = std::io::stdin();
    if !stdin.is_terminal() {
        return RawSession { active: false };
    }
    let fd = stdin.as_raw_fd();
    let Some(original) = set_raw(fd) else {
        return RawSession { active: false };
    };
    *SAVED_TERMIOS.lock().unwrap() = Some(original);
    RawSession { active: true }
}

impl RawSession {
    /// A key waiting on stdin right now, or `None` if nothing is (this
    /// never blocks).
    pub fn poll_key(&self) -> Option<u8> {
        if !self.active {
            return None;
        }
        let fd = std::io::stdin().as_raw_fd();
        let mut pfd = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        if unsafe { libc::poll(&mut pfd, 1, 0) } <= 0 {
            return None;
        }
        let mut byte = [0u8; 1];
        match std::io::stdin().lock().read(&mut byte) {
            Ok(1) => Some(byte[0]),
            _ => None,
        }
    }
}

impl Drop for RawSession {
    fn drop(&mut self) {
        restore();
    }
}
