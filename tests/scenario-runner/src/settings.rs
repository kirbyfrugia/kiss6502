//! This tool's own persisted defaults. Atari scenarios talk over a serial
//! device -- real hardware or the emulator's socat bridge, which varies by
//! machine -- so `serial_port` is the device path to use when a scenario
//! needs one. Rust scenarios talk KISS over TCP directly, so `tcp_port` is
//! the port direwolf listens on (and the one to point kisstty's own KISS
//! setting at). Set from the picker's settings entry.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

fn default_serial_port() -> String {
    "/tmp/altirra-tty".to_string()
}

fn default_tcp_port() -> u16 {
    kisstty_harness::KISS_PORT
}

#[derive(Serialize, Deserialize)]
pub struct Settings {
    #[serde(default = "default_serial_port")]
    pub serial_port: String,
    #[serde(default = "default_tcp_port")]
    pub tcp_port: u16,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            serial_port: default_serial_port(),
            tcp_port: default_tcp_port(),
        }
    }
}

fn path() -> Option<PathBuf> {
    Some(
        dirs::config_dir()?
            .join("kisstty-tests")
            .join("scenario-runner.toml"),
    )
}

impl Settings {
    pub fn load() -> Self {
        path()
            .and_then(|p| std::fs::read_to_string(p).ok())
            .and_then(|text| toml::from_str(&text).ok())
            .unwrap_or_default()
    }

    /// Best-effort: a stale default is a minor annoyance, not worth failing
    /// the run over.
    pub fn save(&self) {
        let Some(path) = path() else { return };
        if let Some(dir) = path.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if let Ok(text) = toml::to_string_pretty(self) {
            let _ = std::fs::write(path, text);
        }
    }
}
