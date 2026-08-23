//! A temporary direwolf, fed packet audio through a FIFO.

use crate::HarnessError;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Seek, SeekFrom, Write};
use std::net::{SocketAddr, TcpStream};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::Mutex;
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{Duration, Instant};

pub const KISS_PORT: u16 = 8001;

/// gen_packets emits 44100 Hz, 16 bit, mono.
const SAMPLE_RATE: f64 = 44100.0;

/// Silence written after every packet: direwolf won't key up while it
/// thinks the channel is busy, and stopping the audio feed leaves it
/// thinking that forever, so anything kisstty sends never goes out.
pub const TRAILING_SILENCE: Duration = Duration::from_secs(2);

/// Pushed before polling the log, for the same reason: the channel has to
/// read idle before direwolf will release a queued frame.
pub const LOG_CHECK_SILENCE: Duration = Duration::from_secs(1);

const STARTUP_TIMEOUT: Duration = Duration::from_secs(10);
const POLL_INTERVAL: Duration = Duration::from_millis(200);

/// Lets a signal handler stop whatever direwolf is running without reaching
/// into the `Direwolf` that owns it. `0` means nothing is active.
static ACTIVE_CHILD_PID: AtomicU32 = AtomicU32::new(0);
static ACTIVE_PATHS: Mutex<Option<(PathBuf, PathBuf, PathBuf)>> = Mutex::new(None);

/// Stops whatever direwolf is currently running: signals it and removes its
/// temp files by path. No-op if nothing is active; safe to call more than
/// once. Callers installing this as a signal handler must `process::exit`
/// immediately after -- deliberately never anything else in between.
///
/// This never touches the fifo fd, on purpose: the live `Direwolf` still
/// owns it and hasn't run its own cleanup yet (that only happens via
/// `Drop`, which `process::exit` skips), so closing it here as well would
/// be two owners closing the same fd -- a real, previously-hit abort, not a
/// hypothetical one. Killing the process and letting the OS reclaim its
/// fds on exit is what a signal handler can do safely; touching Rust-level
/// objects the main thread still holds is not.
pub(crate) fn stop_active_direwolf() {
    let pid = ACTIVE_CHILD_PID.swap(0, Ordering::SeqCst);
    if pid != 0 {
        unsafe { libc::kill(pid as libc::pid_t, libc::SIGTERM) };
    }
    if let Some((fifo, conf, wav)) = ACTIVE_PATHS.lock().unwrap().take() {
        for p in [&fifo, &conf, &wav] {
            let _ = fs::remove_file(p);
        }
    }
}

/// Resolve the substitution anchors in a `direwolf.conf.template`.
pub fn render_conf(
    template: &Path,
    serial: &str,
    mycall: &str,
    port: u16,
) -> Result<String, HarnessError> {
    let text =
        fs::read_to_string(template).map_err(|e| format!("reading {}: {e}", template.display()))?;
    Ok(render_conf_text(&text, serial, mycall, port))
}

/// `%%KISSPORT%%` becomes `port`. `%%SERIALKISS%%` becomes a `SERIALKISS`
/// line for `serial`, or is dropped entirely for TCP KISS only. `MYCALL
/// NOCALL` becomes the given callsign; an empty `mycall` leaves the
/// template's own line alone.
pub fn render_conf_text(text: &str, serial: &str, mycall: &str, port: u16) -> String {
    let text = text.replace("%%KISSPORT%%", &port.to_string());
    let text = if mycall.is_empty() {
        text
    } else {
        text.replace("MYCALL NOCALL", &format!("MYCALL {mycall}"))
    };
    let text = if serial.is_empty() {
        text.lines()
            .filter(|l| l.trim() != "%%SERIALKISS%%")
            .collect::<Vec<_>>()
            .join("\n")
    } else {
        text.replace("%%SERIALKISS%%", &format!("SERIALKISS {serial}"))
    };
    format!("{}\n", text.trim_end_matches('\n'))
}

/// Whether something already accepts connections on the KISS port.
pub fn kiss_port_busy(port: u16) -> bool {
    let addr: SocketAddr = ([127, 0, 0, 1], port).into();
    TcpStream::connect_timeout(&addr, Duration::from_millis(250)).is_ok()
}

fn on_path(exe: &str) -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    std::env::split_paths(&path).any(|dir| {
        let candidate = dir.join(exe);
        candidate
            .metadata()
            .map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
            .unwrap_or(false)
    })
}

/// Turns TNC2 packet text into 1200 baud WAV audio.
fn gen_packets(packet: &str, wav: &Path) -> Result<Vec<u8>, HarnessError> {
    let mut gp = Command::new("gen_packets")
        .arg("-o")
        .arg(wav)
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
        return Err(format!("gen_packets failed on: {packet}"));
    }
    // The whole file, RIFF header included, goes to the fifo.
    fs::read(wav).map_err(|e| format!("reading {}: {e}", wav.display()))
}

/// A temporary direwolf, fed packet audio through a FIFO.
///
/// `Direwolf::start` both configures and launches it; there is no
/// unstarted state to hold. Dropping it (or calling [`Direwolf::stop`]
/// explicitly, which is idempotent) tears it down.
pub struct Direwolf {
    child: Child,
    fifo_writer: Option<File>,
    conf: PathBuf,
    fifo: PathBuf,
    log: PathBuf,
    wav: PathBuf,
    log_pos: u64,
    stopped: bool,
}

impl Direwolf {
    pub fn start(
        template: &Path,
        serial: &str,
        mycall: &str,
        name: &str,
        port: u16,
    ) -> Result<Self, HarnessError> {
        if !template.is_file() {
            return Err(format!("conf template not found: {}", template.display()));
        }
        for exe in ["direwolf", "gen_packets"] {
            if !on_path(exe) {
                return Err(format!("{exe} not found on PATH (it ships with direwolf)"));
            }
        }

        // A leftover direwolf holding the port means every later check
        // quietly talks to the wrong instance.
        if kiss_port_busy(port) {
            return Err(format!(
                "something is already listening on {port}, probably a leftover direwolf. \
                 stop it first (pkill direwolf) so we do not talk to the wrong one"
            ));
        }

        let dir = std::env::temp_dir();
        let conf = dir.join(format!("{name}.conf"));
        let fifo = dir.join(format!("{name}.fifo"));
        let log = dir.join(format!("{name}.log"));
        let wav = dir.join(format!("{name}.wav"));

        fs::write(&conf, render_conf(template, serial, mycall, port)?)
            .map_err(|e| format!("writing conf: {e}"))?;

        let _ = fs::remove_file(&fifo);
        let ok = Command::new("mkfifo")
            .arg(&fifo)
            .status()
            .map_err(|e| format!("mkfifo: {e}"))?;
        if !ok.success() {
            return Err("mkfifo failed".to_string());
        }

        // O_RDWR: write-only would see EOF between packets, and no read end
        // at all means SIGPIPE on a dead direwolf. This way a dead direwolf
        // is just a blocked write, which inject() checks for.
        let fifo_writer = OpenOptions::new()
            .read(true)
            .write(true)
            .open(&fifo)
            .map_err(|e| format!("opening fifo: {e}"))?;

        // direwolf's own read-only handle; closing ours on the way out is
        // what gives it EOF. Doesn't block since we already hold read-write.
        let dw_stdin = File::open(&fifo).map_err(|e| format!("opening fifo for direwolf: {e}"))?;
        let log_file = File::create(&log).map_err(|e| format!("creating log: {e}"))?;
        let log_file_clone = log_file.try_clone().map_err(|e| e.to_string())?;

        let child = Command::new("direwolf")
            .args(["-t", "0", "-c"])
            .arg(&conf)
            .stdin(Stdio::from(dw_stdin))
            .stdout(Stdio::from(log_file_clone))
            .stderr(Stdio::from(log_file))
            .spawn()
            .map_err(|e| format!("starting direwolf: {e}"))?;

        ACTIVE_CHILD_PID.store(child.id(), Ordering::SeqCst);
        *ACTIVE_PATHS.lock().unwrap() = Some((fifo.clone(), conf.clone(), wav.clone()));

        let mut dw = Direwolf {
            child,
            fifo_writer: Some(fifo_writer),
            conf,
            fifo,
            log,
            wav,
            log_pos: 0,
            stopped: false,
        };
        if let Err(e) = dw.wait_for_kiss(port) {
            dw.stop();
            return Err(e);
        }
        Ok(dw)
    }

    fn wait_for_kiss(&mut self, port: u16) -> Result<(), HarnessError> {
        let deadline = Instant::now() + STARTUP_TIMEOUT;
        while Instant::now() < deadline {
            if let Ok(Some(status)) = self.child.try_wait() {
                return Err(format!(
                    "direwolf exited during startup ({status}); see {}",
                    self.log.display()
                ));
            }
            if kiss_port_busy(port) {
                return Ok(());
            }
            std::thread::sleep(Duration::from_millis(250));
        }
        Err(format!(
            "direwolf KISS port {port} never came up; see {}",
            self.log.display()
        ))
    }

    /// Idempotent, so an explicit call and a drop can't double-act.
    pub fn stop(&mut self) {
        if self.stopped {
            return;
        }
        self.stopped = true;
        ACTIVE_CHILD_PID.store(0, Ordering::SeqCst);
        ACTIVE_PATHS.lock().unwrap().take();

        // Closing the write end gives direwolf EOF so it can shut down on its own.
        self.fifo_writer.take();

        if matches!(self.child.try_wait(), Ok(None)) {
            unsafe { libc::kill(self.child.id() as libc::pid_t, libc::SIGTERM) };
            let deadline = Instant::now() + Duration::from_secs(3);
            while Instant::now() < deadline {
                if matches!(self.child.try_wait(), Ok(Some(_))) {
                    break;
                }
                std::thread::sleep(Duration::from_millis(100));
            }
            if matches!(self.child.try_wait(), Ok(None)) {
                let _ = self.child.kill();
                let _ = self.child.wait();
            }
        }

        for p in [&self.fifo, &self.conf, &self.wav] {
            let _ = fs::remove_file(p);
        }
        // The log is deliberately kept. A late frame lands in it, and that
        // is worth checking before believing something was never sent.
    }

    pub fn pid(&self) -> u32 {
        self.child.id()
    }

    pub fn log_path(&self) -> &Path {
        &self.log
    }

    /// Puts one TNC2 packet on the air, then lets the channel go idle.
    pub fn inject(&mut self, packet: &str) -> Result<(), HarnessError> {
        // We hold the read end open, so a dead direwolf means no SIGPIPE and
        // a write that blocks forever once the pipe buffer fills.
        if let Ok(Some(status)) = self.child.try_wait() {
            return Err(format!(
                "direwolf exited ({status}); see {}",
                self.log.display()
            ));
        }
        let audio = gen_packets(packet, &self.wav)?;
        let w = self.fifo_writer.as_mut().expect("fifo open while running");
        w.write_all(&audio)
            .map_err(|e| format!("writing to fifo: {e}"))?;
        self.silence(TRAILING_SILENCE)
    }

    /// Keeps the demodulator fed so the channel reads idle.
    ///
    /// 16 bit mono, so two zero bytes per sample.
    pub fn silence(&mut self, how_long: Duration) -> Result<(), HarnessError> {
        let samples = (SAMPLE_RATE * how_long.as_secs_f64()) as usize;
        let w = self.fifo_writer.as_mut().expect("fifo open while running");
        w.write_all(&vec![0u8; samples * 2])
            .map_err(|e| format!("writing silence: {e}"))
    }

    /// Everything direwolf has logged since the last time we looked.
    pub fn new_log(&mut self) -> String {
        let Ok(mut f) = File::open(&self.log) else {
            return String::new();
        };
        if f.seek(SeekFrom::Start(self.log_pos)).is_err() {
            return String::new();
        }
        let mut buf = Vec::new();
        let _ = f.read_to_end(&mut buf);
        self.log_pos += buf.len() as u64;
        String::from_utf8_lossy(&buf).into_owned()
    }

    /// Polls the log until every wanted substring shows up, or gives up.
    /// `on_tick` is handed the deadline so a caller can draw a countdown.
    pub fn wait_for_log(
        &mut self,
        wanted: &[String],
        timeout: Duration,
        mut on_tick: impl FnMut(Instant),
    ) -> Result<(bool, String), HarnessError> {
        self.silence(LOG_CHECK_SILENCE)?;
        let mut seen = String::new();
        let mut pending: Vec<&String> = wanted.iter().collect();
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            seen.push_str(&self.new_log());
            pending.retain(|w| !seen.contains(w.as_str()));
            if pending.is_empty() {
                return Ok((true, seen));
            }
            on_tick(deadline);
            std::thread::sleep(POLL_INTERVAL);
        }
        Ok((false, seen))
    }

    /// Waits the whole window out, failing if anything unwanted shows up.
    /// The only way to be sure something was never sent is to wait, so this
    /// always costs the full timeout when it passes.
    pub fn wait_for_no_log(
        &mut self,
        unwanted: &[String],
        timeout: Duration,
        mut on_tick: impl FnMut(Instant),
    ) -> Result<(bool, String), HarnessError> {
        self.silence(LOG_CHECK_SILENCE)?;
        let mut seen = String::new();
        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            seen.push_str(&self.new_log());
            if unwanted.iter().any(|w| seen.contains(w.as_str())) {
                return Ok((false, seen));
            }
            on_tick(deadline);
            std::thread::sleep(POLL_INTERVAL);
        }
        Ok((true, seen))
    }
}

impl Drop for Direwolf {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn directives(conf: &str) -> Vec<&str> {
        conf.lines()
            .map(str::trim)
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .collect()
    }

    #[test]
    fn render_conf_resolves_all_anchors() {
        let template = "MYCALL NOCALL\nKISSPORT %%KISSPORT%%\n%%SERIALKISS%%\n";

        let out = render_conf_text(template, "/tmp/altirra-tty", "NOCALL-7", 8765);
        let lines = directives(&out);
        assert!(lines.contains(&"KISSPORT 8765"));
        assert!(lines.contains(&"SERIALKISS /tmp/altirra-tty"));
        assert!(lines.contains(&"MYCALL NOCALL-7"));

        // TCP-only: the anchor line goes entirely, not a bare SERIALKISS.
        let out = render_conf_text(template, "", "", 8001);
        let lines = directives(&out);
        assert!(!lines.iter().any(|l| l.starts_with("SERIALKISS")));
        assert!(
            lines.contains(&"MYCALL NOCALL"),
            "empty mycall leaves it alone"
        );
    }
}
