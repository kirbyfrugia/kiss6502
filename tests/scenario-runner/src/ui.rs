//! All the drawing. Degrades to plain ASCII with no colour when it has to.

use std::io::Write;
use std::time::Instant;

pub struct Ui {
    color: bool,
    width: usize,
    spin: usize,

    h: char,
    hh: char,
    vb: char,
    arrow: &'static str,
    box_marker: &'static str,
    tick: &'static str,
    cross: &'static str,
    dot: &'static str,
    to_air: &'static str,
    to_wire: &'static str,
    spinner: Vec<char>,
}

pub enum Answer {
    Yes,
    No,
    Quit,
}

impl Ui {
    /// Color and unicode symbols are always on except where the environment
    /// can't actually support them -- there's no override for either.
    pub fn new() -> Self {
        let color = std::io::IsTerminal::is_terminal(&std::io::stdout())
            && std::env::var_os("NO_COLOR").is_none()
            && std::env::var("TERM").as_deref() != Ok("dumb");
        let unicode = std::env::var("LANG")
            .map(|l| l.to_lowercase().contains("utf"))
            .unwrap_or(false)
            || std::env::var("LC_ALL")
                .map(|l| l.to_lowercase().contains("utf"))
                .unwrap_or(false);
        let (h, hh, vb, arrow, box_marker, tick, cross, dot, to_air, to_wire, spinner) = if unicode
        {
            (
                '─',
                '━',
                '┃',
                "▸",
                "□",
                "✓",
                "✗",
                "·",
                "→",
                "→",
                "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏",
            )
        } else {
            (
                '-', '=', '|', ">", "[ ]", "OK", "XX", ".", "->", "->", "|/-\\",
            )
        };
        Self {
            color,
            width: terminal_width().min(84),
            spin: 0,
            h,
            hh,
            vb,
            arrow,
            box_marker,
            tick,
            cross,
            dot,
            to_air,
            to_wire,
            spinner: spinner.chars().collect(),
        }
    }

    fn c(&self, text: &str, code: &str) -> String {
        if self.color {
            format!("\x1b[{code}m{text}\x1b[0m")
        } else {
            text.to_string()
        }
    }
    pub fn bold(&self, t: &str) -> String {
        self.c(t, "1")
    }
    pub fn dim(&self, t: &str) -> String {
        self.c(t, "2")
    }
    pub fn red(&self, t: &str) -> String {
        self.c(t, "31;1")
    }
    pub fn green(&self, t: &str) -> String {
        self.c(t, "32;1")
    }
    pub fn yellow(&self, t: &str) -> String {
        self.c(t, "33;1")
    }
    pub fn tag(&self, text: &str, code: &str) -> String {
        self.c(&format!(" {text} "), code)
    }

    pub fn rule(&self, text: &str, hh: bool) {
        let ch = if hh { self.hh } else { self.h };
        if text.is_empty() {
            println!("{}", self.dim(&ch.to_string().repeat(self.width)));
        } else {
            let lead = format!("{} {text} ", ch.to_string().repeat(3));
            let pad = self.width.saturating_sub(vislen(&lead));
            println!(
                "{}",
                self.dim(&format!("{lead}{}", ch.to_string().repeat(pad)))
            );
        }
    }

    pub fn title(&self, name: &str, platform: &str) {
        println!();
        self.rule(
            &format!(
                "{}{}",
                self.bold(name),
                self.dim(&format!(" {} {platform}", self.dot))
            ),
            true,
        );
    }

    /// A block you cannot scroll past without noticing.
    pub fn setup(&self, lines: &[String], prompt: &str) {
        println!();
        println!(
            "{}",
            self.yellow(&format!(
                "{}{} SETUP {}",
                self.hh,
                self.hh,
                self.hh.to_string().repeat(8)
            ))
        );
        for line in lines {
            println!("{}  {}", self.yellow(&self.vb.to_string()), self.bold(line));
        }
        print!(
            "{} {prompt} {} ",
            self.yellow(&format!("{}{} ", self.hh, self.hh)),
            self.arrow
        );
        let _ = std::io::stdout().flush();
    }

    pub fn step_header(&self, n: usize, total: usize, description: &str) {
        println!();
        self.rule(&self.bold(&format!("step {n}/{total}")), false);
        if !description.is_empty() {
            println!("    {description}");
        }
    }

    pub fn action_banner(&self) {
        println!();
        println!("  {}", self.tag("ACTION NEEDED", "30;43;1"));
    }
    pub fn look_banner(&self) {
        println!();
        println!("  {}", self.tag("LOOK AT SCREEN", "30;46;1"));
    }
    pub fn working_banner(&self) {
        println!();
        println!(
            "  {} {}",
            self.dim(&self.dot.repeat(2)),
            self.dim("WORKING - no input needed")
        );
    }

    pub fn detail(&self, marker: &str, text: &str) {
        println!("     {marker} {text}");
    }
    pub fn bullet(&self, text: &str) {
        println!("      {text}");
    }
    pub fn passed(&self, label: &str, text: &str) {
        println!("     {} {} {text}", self.green(self.tick), self.dim(label));
    }
    pub fn failed(&self, label: &str, text: &str) {
        println!(
            "     {} {} {text}",
            self.red(&format!("{} FAIL", self.cross)),
            self.dim(label)
        );
    }
    pub fn note(&self, text: &str) {
        for line in text.lines() {
            println!("{}", self.dim(&format!("       {line}")));
        }
    }
    pub fn log_dump(&self, seen: &str) {
        let lines: Vec<&str> = seen.lines().filter(|l| !l.trim().is_empty()).collect();
        if lines.is_empty() {
            self.note("direwolf logged nothing during this step");
            return;
        }
        self.note("direwolf logged during this step:");
        for line in lines {
            println!("{}", self.dim(&format!("       {} {line}", self.vb)));
        }
    }

    pub fn to_air(&self) -> &'static str {
        self.to_air
    }
    pub fn to_wire(&self) -> &'static str {
        self.to_wire
    }
    pub fn box_marker(&self) -> &'static str {
        self.box_marker
    }
    pub fn dot(&self) -> &'static str {
        self.dot
    }

    /// Redraws in place, so a long window does not look like a hang.
    pub fn progress(&mut self, label: &str, deadline: Instant) {
        let left = deadline.saturating_duration_since(Instant::now());
        let frame = self.spinner[self.spin % self.spinner.len()];
        self.spin += 1;
        let secs = left.as_secs() + u64::from(left.subsec_nanos() > 0);
        print!("\r{}", self.dim(&format!("     {frame} {label} {secs}s ")));
        let _ = std::io::stdout().flush();
    }

    pub fn progress_done(&self) {
        print!("\r{}\r", " ".repeat(self.width.saturating_sub(1)));
        let _ = std::io::stdout().flush();
    }

    /// Drops anything typed while we were busy. Without this a keypress
    /// during a five second spinner silently answers the next question.
    fn flush_stdin(&self) {
        use std::os::fd::AsRawFd;
        if std::io::IsTerminal::is_terminal(&std::io::stdin()) {
            unsafe {
                libc::tcflush(std::io::stdin().as_raw_fd(), libc::TCIFLUSH);
            }
        }
    }

    /// y, n or q. Enter is yes. EOF quits, so a piped run cannot spin
    /// forever.
    pub fn ask(&self, prompt: &str) -> Answer {
        self.flush_stdin();
        loop {
            print!("      {prompt} {} ", self.arrow);
            let _ = std::io::stdout().flush();
            let mut line = String::new();
            match std::io::stdin().read_line(&mut line) {
                Ok(0) | Err(_) => {
                    println!();
                    return Answer::Quit;
                }
                Ok(_) => {}
            }
            match line.trim().to_ascii_lowercase().as_str() {
                "" | "y" | "yes" => return Answer::Yes,
                "n" | "no" => return Answer::No,
                "q" | "quit" => return Answer::Quit,
                _ => println!("{}", self.dim("      answer y, n or q")),
            }
        }
    }

    pub fn finish_setup_prompt(&self) -> Answer {
        self.flush_stdin();
        let mut line = String::new();
        if std::io::stdin().read_line(&mut line).unwrap_or(0) == 0 {
            println!();
            return Answer::Quit;
        }
        if matches!(line.trim().to_ascii_lowercase().as_str(), "q" | "quit") {
            Answer::Quit
        } else {
            Answer::Yes
        }
    }
}

/// Length ignoring ANSI escapes, so rules line up when colour is on.
fn vislen(text: &str) -> usize {
    let mut out = 0;
    let mut chars = text.chars().peekable();
    while let Some(c) = chars.next() {
        if c == '\x1b' {
            for c in chars.by_ref() {
                if c == 'm' {
                    break;
                }
            }
            continue;
        }
        out += 1;
    }
    out
}

fn terminal_width() -> usize {
    #[repr(C)]
    struct Winsize {
        ws_row: libc::c_ushort,
        ws_col: libc::c_ushort,
        ws_xpixel: libc::c_ushort,
        ws_ypixel: libc::c_ushort,
    }
    unsafe {
        let mut ws: Winsize = std::mem::zeroed();
        if libc::ioctl(libc::STDOUT_FILENO, libc::TIOCGWINSZ, &mut ws) == 0 && ws.ws_col > 0 {
            return ws.ws_col as usize;
        }
    }
    80
}
