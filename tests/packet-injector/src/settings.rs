//! This tool's own persisted defaults. Direwolf always listens for KISS over
//! TCP on `tcp_port`; `use_serial` says whether to also bridge `serial_port`,
//! for a hardware or emulated setup that listens there instead. Set from the
//! interactive menu's settings entry, or `-s`/`--tcp` on the command line.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

fn default_serial_port() -> String {
    "/tmp/altirra-tty".to_string()
}

fn default_tcp_port() -> u16 {
    kisstty_harness::KISS_PORT
}

fn default_use_serial() -> bool {
    true
}

#[derive(Serialize, Deserialize)]
pub struct Settings {
    #[serde(default = "default_serial_port")]
    pub serial_port: String,
    #[serde(default = "default_tcp_port")]
    pub tcp_port: u16,
    #[serde(default = "default_use_serial")]
    pub use_serial: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            serial_port: default_serial_port(),
            tcp_port: default_tcp_port(),
            use_serial: default_use_serial(),
        }
    }
}

fn path() -> Option<PathBuf> {
    Some(
        dirs::config_dir()?
            .join("kisstty-tests")
            .join("packet-injector.toml"),
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

    /// The device to hand direwolf: `serial_port` if it's in use, empty for
    /// TCP KISS only.
    pub fn serial(&self) -> String {
        if self.use_serial {
            self.serial_port.clone()
        } else {
            String::new()
        }
    }
}
