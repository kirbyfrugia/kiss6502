//! The app's serial device, for scenarios that drive it directly.

use crate::HarnessError;
use crate::escape::contains;
use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// A thread drains it continuously, so bytes the app sends while you are
/// typing are still there when the step gets round to checking for them.
pub struct Serial {
    dev: File,
    rx: Arc<Mutex<Vec<u8>>>,
}

impl Serial {
    pub fn open(path: &str) -> Result<Self, HarnessError> {
        let dev = OpenOptions::new()
            .read(true)
            .write(true)
            .custom_flags(libc::O_NOCTTY)
            .open(path)
            .map_err(|e| format!("opening {path}: {e}. is socat running?"))?;
        let mut reader = dev
            .try_clone()
            .map_err(|e| format!("cloning {path}: {e}"))?;
        let rx = Arc::new(Mutex::new(Vec::new()));
        let sink = Arc::clone(&rx);
        std::thread::spawn(move || {
            let mut buf = [0u8; 256];
            loop {
                match reader.read(&mut buf) {
                    Ok(0) | Err(_) => return,
                    Ok(n) => {
                        if let Ok(mut sink) = sink.lock() {
                            sink.extend_from_slice(&buf[..n]);
                        }
                    }
                }
            }
        });
        Ok(Self { dev, rx })
    }

    pub fn write(&mut self, data: &[u8]) -> Result<(), HarnessError> {
        self.dev
            .write_all(data)
            .map_err(|e| format!("writing to serial: {e}"))
    }

    /// Forgets anything seen so far, so a step only reads its own bytes.
    pub fn new_window(&self) {
        if let Ok(mut rx) = self.rx.lock() {
            rx.clear();
        }
    }

    pub fn seen(&self) -> Vec<u8> {
        self.rx.lock().map(|rx| rx.clone()).unwrap_or_default()
    }

    /// Waits for every wanted byte string, or for the window to run out.
    pub fn expect(
        &self,
        wants: &[Vec<u8>],
        timeout: Duration,
        mut on_tick: impl FnMut(Instant),
    ) -> (bool, Vec<u8>) {
        let deadline = Instant::now() + timeout;
        loop {
            let seen = self.seen();
            if wants.iter().all(|w| contains(&seen, w)) {
                return (true, seen);
            }
            if Instant::now() >= deadline {
                return (false, seen);
            }
            on_tick(deadline);
            std::thread::sleep(Duration::from_millis(100));
        }
    }
}
