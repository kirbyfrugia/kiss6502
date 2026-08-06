use serde::Deserialize;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{Duration, Instant};

const KISS_PORT: u16 = 8001;

/// gen_packets emits 44100 Hz, 16 bit, mono.
const SAMPLE_RATE: usize = 44100;

/// Silence written after every packet. Direwolf will not key up while it
/// thinks the channel is busy, and that state comes from the audio it is
/// demodulating. Stop feeding it and the demodulator blocks on the read with
/// the channel still marked busy, so anything kisstty sends us sits in the
/// transmit queue forever.
const TRAILING_SILENCE: Duration = Duration::from_secs(2);

/// So the ctrl-c handler can stop direwolf without reaching into the struct
/// that owns it.
static DIREWOLF_PID: AtomicU32 = AtomicU32::new(0);

/// Message bodies for `random` steps, short enough through long enough to wrap.
const LOREM: &[&str] = &[
    "OK",
    "Roger that.",
    "Back in 5.",
    "QSL, 73 and good DX.",
    "Heading home now, traffic is light.",
    "The quick brown fox jumps over the lazy dog.",
    "She sells seashells by the seashore at dawn.",
    "All work and no play makes Jack a dull boy today.",
    "Pack my box with five dozen liquor jugs before noon.",
    "Lorem ipsum dolor sit amet, consectetur adipiscing elit.",
    "The morning sun rises slowly above the quiet green hills.",
    "How vexingly quick daft zebras jump under the pale moonlight.",
    "Sphinx of black quartz, judge my vow on this calm clear night.",
    "The river winds gently through the valley toward the harbor light.",
    "A gentle breeze drifts across the wide open meadow on a summer day.",
];

/// xorshift64, so a soak run varies without pulling in a rand crate.
///
/// The ssid is 1 to 15 and never 0, because a frame sourced from bare NOCALL
/// is the station under test talking to itself and kisstty drops those.
/// Varying the sender also keeps the small corpus from tripping dedup on
/// every other packet.
fn random_packet(state: &mut u64) -> String {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    let body = LOREM[(*state % LOREM.len() as u64) as usize];
    let ssid = 1 + (*state >> 8) % 15;
    format!("NOCALL-{ssid}>APKTY1,WIDE1-1,WIDE2-1::NOCALL   :{body}")
}
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(5);

#[derive(Deserialize)]
struct Scenario {
    name: String,
    /// Which build this drives. The `look_for` lines describe that platform's
    /// display, so a scenario is not portable between them.
    platform: String,
    /// Serial device the app under test is on. Empty means TCP KISS only.
    #[serde(default)]
    serial: String,
    mycall: String,
    #[serde(default)]
    step: Vec<Step>,
}

#[derive(Deserialize)]
struct Step {
    /// What this step is testing, printed as the step's heading. Kept
    /// general: the verbs say what happens and `look_for` pins down the
    /// exact screen content, so this says what it is for.
    description: Option<String>,
    /// Packets to put on the air for kisstty to receive. A list goes out back
    /// to back with no prompt in between, which is how a scenario stays inside
    /// a timing window that human answering speed would otherwise blow.
    to_kisstty: Option<Lines>,
    /// Send a message picked from LOREM instead of a literal `to_kisstty`.
    #[serde(default)]
    random: bool,
    /// How many times to inject. Zero runs until you interrupt it.
    repeat: Option<u64>,
    /// Seconds between repeats.
    every: Option<u64>,
    #[serde(rename = "do")]
    action: Option<String>,
    /// Exactly what should be on screen, answered y, n or q.
    look_for: Option<Lines>,
    /// A frame kisstty should put on the air, matched in the direwolf log.
    from_kisstty: Option<Lines>,
    /// A frame kisstty must not put on the air. Costs the whole window,
    /// since the only way to be sure is to wait it out.
    not_from_kisstty: Option<Lines>,
    /// Seconds to allow the two log checks, default 5.
    timeout: Option<u64>,
    wait: Option<u64>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum Lines {
    One(String),
    Many(Vec<String>),
}

impl Lines {
    fn iter(&self) -> impl Iterator<Item = &String> {
        match self {
            Lines::One(s) => std::slice::from_ref(s).iter(),
            Lines::Many(v) => v.iter(),
        }
    }
}

struct Direwolf {
    child: Child,
    fifo_writer: Option<File>,
    log: PathBuf,
    log_pos: u64,
    fifo: PathBuf,
    conf: PathBuf,
}

impl Direwolf {
    fn start(template: &Path, serial: &str, mycall: &str) -> Result<Self, String> {
        let conf_text = fs::read_to_string(template)
            .map_err(|e| format!("reading {}: {e}", template.display()))?;
        let conf_text = conf_text.replace("MYCALL NOCALL", &format!("MYCALL {mycall}"));
        let conf_text = if serial.is_empty() {
            conf_text
                .lines()
                .filter(|l| l.trim() != "%%SERIALKISS%%")
                .collect::<Vec<_>>()
                .join("\n")
        } else {
            conf_text.replace("%%SERIALKISS%%", &format!("SERIALKISS {serial}"))
        };

        if std::net::TcpStream::connect(("127.0.0.1", KISS_PORT)).is_ok() {
            return Err(format!(
                "something is already listening on {KISS_PORT}, probably a leftover direwolf. \
                 stop it first (pkill direwolf) so we do not talk to the wrong one"
            ));
        }

        let dir = std::env::temp_dir();
        let conf = dir.join("kisstty-scenario.conf");
        let fifo = dir.join("kisstty-scenario.fifo");
        let log = dir.join("kisstty-scenario.log");
        fs::write(&conf, conf_text).map_err(|e| format!("writing conf: {e}"))?;

        let _ = fs::remove_file(&fifo);
        let ok = Command::new("mkfifo")
            .arg(&fifo)
            .status()
            .map_err(|e| format!("mkfifo: {e}"))?;
        if !ok.success() {
            return Err("mkfifo failed".into());
        }

        // Hold the fifo open read-write so direwolf never sees EOF between
        // packets. We only ever write to this handle.
        let fifo_writer = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&fifo)
            .map_err(|e| format!("opening fifo: {e}"))?;
        let dw_stdin = File::open(&fifo).map_err(|e| format!("opening fifo for direwolf: {e}"))?;
        let log_file = File::create(&log).map_err(|e| format!("creating log: {e}"))?;

        let child = Command::new("direwolf")
            .args(["-t", "0", "-c"])
            .arg(&conf)
            .stdin(Stdio::from(dw_stdin))
            .stdout(Stdio::from(log_file.try_clone().map_err(|e| e.to_string())?))
            .stderr(Stdio::from(log_file))
            .spawn()
            .map_err(|e| format!("starting direwolf: {e}"))?;

        DIREWOLF_PID.store(child.id(), Ordering::SeqCst);
        let mut dw = Direwolf {
            child,
            fifo_writer: Some(fifo_writer),
            log,
            log_pos: 0,
            fifo,
            conf,
        };
        dw.wait_for_kiss()?;
        Ok(dw)
    }

    fn wait_for_kiss(&mut self) -> Result<(), String> {
        let deadline = Instant::now() + Duration::from_secs(10);
        while Instant::now() < deadline {
            if std::net::TcpStream::connect(("127.0.0.1", KISS_PORT)).is_ok() {
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(250));
        }
        Err(format!("direwolf KISS port {KISS_PORT} never came up; see {}", self.log.display()))
    }

    fn inject(&mut self, packet: &str) -> Result<(), String> {
        // We hold the read end open, so a dead direwolf means no SIGPIPE and a
        // write that blocks forever once the pipe buffer fills.
        if let Ok(Some(status)) = self.child.try_wait() {
            return Err(format!("direwolf exited ({status}); see {}", self.log.display()));
        }

        let wav = std::env::temp_dir().join("kisstty-scenario.wav");
        let mut gp = Command::new("gen_packets")
            .arg("-o")
            .arg(&wav)
            .arg("-")
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .map_err(|e| format!("starting gen_packets: {e}"))?;
        gp.stdin
            .take()
            .expect("piped")
            .write_all(packet.as_bytes())
            .map_err(|e| format!("feeding gen_packets: {e}"))?;
        if !gp.wait().map_err(|e| e.to_string())?.success() {
            return Err("gen_packets failed".into());
        }

        let audio = fs::read(&wav).map_err(|e| format!("reading wav: {e}"))?;
        let w = self.fifo_writer.as_mut().expect("fifo open while running");
        w.write_all(&audio).map_err(|e| format!("writing to fifo: {e}"))?;
        w.flush().map_err(|e| e.to_string())?;
        self.silence(TRAILING_SILENCE)
    }

    /// Keeps the demodulator fed so direwolf sees the channel go idle and
    /// releases anything queued for transmit.
    fn silence(&mut self, how_long: Duration) -> Result<(), String> {
        let samples = SAMPLE_RATE * how_long.as_millis() as usize / 1000;
        let quiet = vec![0u8; samples * 2];
        let w = self.fifo_writer.as_mut().expect("fifo open while running");
        w.write_all(&quiet).map_err(|e| format!("writing silence: {e}"))?;
        w.flush().map_err(|e| e.to_string())?;
        Ok(())
    }

    /// Everything direwolf has logged since the last time we looked.
    fn new_log(&mut self) -> String {
        let Ok(mut f) = File::open(&self.log) else { return String::new() };
        if f.seek(SeekFrom::Start(self.log_pos)).is_err() {
            return String::new();
        }
        let mut buf = String::new();
        let _ = f.read_to_string(&mut buf);
        self.log_pos += buf.len() as u64;
        buf
    }

    /// Polls the log until every wanted substring shows up, or we give up.
    fn expect_from_kisstty(&mut self, wanted: &Lines, window: Duration) -> (bool, String) {
        let mut seen = String::new();
        // Give the demodulator something to chew on so the channel reads idle
        // and direwolf actually keys up.
        let _ = self.silence(Duration::from_secs(1));
        let mut pending: Vec<&String> = wanted.iter().collect();
        let deadline = Instant::now() + window;
        while Instant::now() < deadline {
            seen.push_str(&self.new_log());
            pending.retain(|w| !seen.contains(w.as_str()));
            if pending.is_empty() {
                progress_done();
                return (true, seen);
            }
            progress("waiting for the frame", deadline);
            std::thread::sleep(Duration::from_millis(200));
        }
        progress_done();
        (false, seen)
    }

    fn expect_nothing_from_kisstty(&mut self, unwanted: &Lines, window: Duration) -> (bool, String) {
        let mut seen = String::new();
        let _ = self.silence(Duration::from_secs(1));
        let deadline = Instant::now() + window;
        while Instant::now() < deadline {
            seen.push_str(&self.new_log());
            if unwanted.iter().any(|w| seen.contains(w.as_str())) {
                progress_done();
                return (false, seen);
            }
            progress("listening, should stay quiet", deadline);
            std::thread::sleep(Duration::from_millis(200));
        }
        progress_done();
        (true, seen)
    }
}

impl Drop for Direwolf {
    fn drop(&mut self) {
        // Closing the write end gives direwolf EOF so it can shut down on its
        // own. Only escalate if it does not take the hint.
        self.fifo_writer.take();
        let _ = Command::new("kill").arg(self.child.id().to_string()).status();

        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            match self.child.try_wait() {
                Ok(Some(_)) => break,
                Ok(None) if Instant::now() < deadline => {
                    std::thread::sleep(Duration::from_millis(100))
                }
                _ => {
                    let _ = self.child.kill();
                    let _ = self.child.wait();
                    break;
                }
            }
        }

        DIREWOLF_PID.store(0, Ordering::SeqCst);
        let _ = fs::remove_file(&self.fifo);
        let _ = fs::remove_file(&self.conf);
        println!("direwolf stopped, log kept at {}", self.log.display());
    }
}

enum Answer {
    Yes,
    No,
    Quit,
}

/// Enter defaults to yes. EOF quits, so a piped run cannot spin forever.
fn ask(msg: &str) -> Answer {
    loop {
        print!("{msg}");
        let _ = std::io::stdout().flush();
        let mut line = String::new();
        match std::io::stdin().lock().read_line(&mut line) {
            Ok(0) | Err(_) => return Answer::Quit,
            Ok(_) => {}
        }
        match line.trim().to_ascii_lowercase().as_str() {
            "" | "y" | "yes" => return Answer::Yes,
            "n" | "no" => return Answer::No,
            "q" | "quit" => return Answer::Quit,
            _ => println!("      answer y, n or q"),
        }
    }
}

/// Redraws in place, so a long window does not look like a hang.
fn progress(label: &str, deadline: Instant) {
    const SPINNER: [char; 4] = ['|', '/', '-', '\\'];
    let left = deadline.saturating_duration_since(Instant::now());
    let secs = left.as_secs() + u64::from(left.subsec_nanos() > 0);
    let frame = SPINNER[(left.subsec_millis() / 250) as usize % SPINNER.len()];
    print!("\r      {frame} {label} {secs}s ");
    let _ = std::io::stdout().flush();
}

fn progress_done() {
    print!("\r{:60}\r", "");
    let _ = std::io::stdout().flush();
}

fn prompt(msg: &str) {
    print!("{msg}");
    let _ = std::io::stdout().flush();
    let mut line = String::new();
    let _ = std::io::stdin().lock().read_line(&mut line);
}

fn log_path() -> PathBuf {
    std::env::temp_dir().join("kisstty-scenario.log")
}

fn stop_stray_direwolf() {
    let pid = DIREWOLF_PID.swap(0, Ordering::SeqCst);
    if pid != 0 {
        let _ = Command::new("kill").arg(pid.to_string()).status();
    }
    let dir = std::env::temp_dir();
    let _ = fs::remove_file(dir.join("kisstty-scenario.fifo"));
    let _ = fs::remove_file(dir.join("kisstty-scenario.conf"));
}

fn main() {
    // exit() skips Drop, so the handler has to stop direwolf itself or it
    // keeps port 8001 and the serial device.
    if let Err(e) = ctrlc::set_handler(|| {
        println!("\ninterrupted");
        stop_stray_direwolf();
        std::process::exit(130);
    }) {
        eprintln!("could not install ctrl-c handler: {e}");
        std::process::exit(2);
    }

    let mut args = std::env::args().skip(1);
    let Some(path) = args.next() else {
        eprintln!("usage: scenario-runner <scenario.toml> [serial-device]");
        eprintln!("       serial-device overrides the one in the scenario;");
        eprintln!("       pass '' for TCP KISS only");
        std::process::exit(2);
    };
    let serial_override = args.next();

    let text = match fs::read_to_string(&path) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("reading {path}: {e}");
            std::process::exit(2);
        }
    };
    let scenario: Scenario = match toml::from_str(&text) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("parsing {path}: {e}");
            std::process::exit(2);
        }
    };

    let template = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("direwolf.conf.template");

    let serial = serial_override.unwrap_or_else(|| scenario.serial.clone());

    println!("== {} ({}) ==", scenario.name, scenario.platform);
    if serial.is_empty() {
        println!("kiss over tcp on port {KISS_PORT}");
    } else {
        println!("kiss over serial on {serial}");
    }
    prompt(&format!(
        "Set your kisstty callsign to {} (no SSID unless shown), then press Enter: ",
        scenario.mycall
    ));

    let mut dw = match Direwolf::start(&template, &serial, &scenario.mycall) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("{e}");
            std::process::exit(1);
        }
    };
    println!("direwolf up, log at /tmp/kisstty-scenario.log\n");

    let mut rng = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.subsec_nanos() as u64 | 1)
        .unwrap_or(0x2545F4914F6CDD1D);

    let mut failures: Vec<String> = Vec::new();
    let mut stopped_at: Option<usize> = None;

    for (i, step) in scenario.step.iter().enumerate() {
        let n = i + 1;

        match &step.description {
            Some(d) => println!("{n}. {d}"),
            None => println!("{n}."),
        }
        let _ = dw.new_log();
        let window = step.timeout.map_or(DEFAULT_TIMEOUT, Duration::from_secs);

        if let Some(action) = &step.action {
            println!("   {:<12} {action}", "[do]");
            if let Answer::Quit = ask("      Enter when done, q to quit: ") {
                stopped_at = Some(n);
                break;
            }
        }

        if step.to_kisstty.is_some() || step.random {
            let repeat = step.repeat.unwrap_or(1);
            let every = Duration::from_secs(step.every.unwrap_or(1));
            let mut done = 0u64;
            let mut first = true;
            'repeat: loop {
                let packets: Vec<String> = match &step.to_kisstty {
                    Some(l) => l.iter().cloned().collect(),
                    None => vec![random_packet(&mut rng)],
                };
                for packet in packets {
                    if !first {
                        std::thread::sleep(every);
                    }
                    first = false;
                    println!("   {:<12} {packet}", "[-> kisstty]");
                    if let Err(e) = dw.inject(&packet) {
                        eprintln!("      inject failed: {e}");
                        failures.push(format!("step {n}: inject failed: {e}"));
                        break 'repeat;
                    }
                }
                done += 1;
                if repeat != 0 && done >= repeat {
                    break;
                }
            }
        }

        if let Some(wait) = step.wait {
            println!("   {:<12} {wait}s", "[wait]");
            let deadline = Instant::now() + Duration::from_secs(wait);
            while Instant::now() < deadline {
                progress("waiting", deadline);
                std::thread::sleep(Duration::from_millis(200));
            }
            progress_done();
        }

        if let Some(from) = &step.from_kisstty {
            let (ok, seen) = dw.expect_from_kisstty(from, window);
            for want in from.iter() {
                println!("   {:<12} [{}] {want}", "[<- kisstty]", if ok { "pass" } else { "FAIL" });
            }
            if !ok {
                for want in from.iter() {
                    failures.push(format!("step {n}: kisstty never sent: {want}"));
                }
                println!(
                    "      nothing matched in {window:?}. a late frame would still \
                     land in {}, worth checking before believing it was never sent.",
                    log_path().display()
                );
                println!("      direwolf logged during this step:");
                for line in seen.lines() {
                    println!("      | {line}");
                }
            }
        }

        if let Some(never) = &step.not_from_kisstty {
            let (ok, seen) = dw.expect_nothing_from_kisstty(never, window);
            for want in never.iter() {
                println!("   {:<12} [{}] {want}", "[<- nothing]", if ok { "pass" } else { "FAIL" });
            }
            if !ok {
                for want in never.iter() {
                    failures.push(format!("step {n}: kisstty sent: {want}"));
                }
                println!("      direwolf logged during this step:");
                for line in seen.lines() {
                    println!("      | {line}");
                }
            }
        }

        if let Some(look_for) = &step.look_for {
            for want in look_for.iter() {
                println!("   {:<12} {want}", "[look for]");
            }
            match ask("      is that what you see? [Y/n/q] ") {
                Answer::Yes => {}
                Answer::No => {
                    for want in look_for.iter() {
                        failures.push(format!("step {n}: did not see: {want}"));
                    }
                }
                Answer::Quit => {
                    stopped_at = Some(n);
                    break;
                }
            }
        }

        println!();
    }

    // Explicit so direwolf is stopped before any exit(); process::exit skips Drop.
    drop(dw);

    println!();
    if let Some(n) = stopped_at {
        println!("stopped at step {n} of {}", scenario.step.len());
    }
    if failures.is_empty() {
        if stopped_at.is_none() {
            println!("{} passed", scenario.name);
            return;
        }
    } else {
        println!("{} failure(s):", failures.len());
        for f in &failures {
            println!("  {f}");
        }
    }
    std::process::exit(1);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn random_packets_are_never_from_us() {
        let mut rng = 0x2545F4914F6CDD1D;
        for _ in 0..1000 {
            let packet = random_packet(&mut rng);
            let src = packet.split('>').next().unwrap();
            assert_ne!(src, "NOCALL", "{packet}");
        }
    }

    #[test]
    fn every_scenario_parses() {
        let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("scenarios");
        let mut count = 0;
        for platform_dir in fs::read_dir(&root).expect("scenarios dir") {
            let platform_dir = platform_dir.expect("dir entry").path();
            if !platform_dir.is_dir() {
                continue;
            }
            let expected = platform_dir.file_name().unwrap().to_string_lossy().into_owned();
            for entry in fs::read_dir(&platform_dir).expect("platform dir") {
                let path = entry.expect("dir entry").path();
                if path.extension().is_none_or(|e| e != "toml") {
                    continue;
                }
                let text = fs::read_to_string(&path).expect("read scenario");
                let scenario: Scenario = toml::from_str(&text)
                    .unwrap_or_else(|e| panic!("{}: {e}", path.display()));
                assert!(!scenario.step.is_empty(), "{}: no steps", path.display());
                assert_eq!(
                    scenario.platform,
                    expected,
                    "{}: platform does not match its directory",
                    path.display()
                );
                count += 1;
            }
        }
        assert!(count > 0, "no scenarios found in {}", root.display());
    }
}
