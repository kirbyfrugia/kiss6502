use std::{
    io::{ErrorKind, Read, Write},
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc, Mutex,
    },
    net::{Shutdown, TcpStream, ToSocketAddrs},
    thread,
    time::Duration,
};

use crate::{
    config,
    message::Message,
};

use super::ax25::{Ax25Error, Ax25Frame};
use super::KISS;

pub struct KissFrame {
    raw_bytes: Vec<u8>,
}

impl Default for KissFrame {
    fn default() -> Self {
        Self {
            raw_bytes: Vec::new(),
        }
    }
}

pub struct KissFrameState {
    waiting_on_first_fend: bool,
    in_fesc: bool,
    current_frame: KissFrame,
}

impl Default for KissFrameState {
    fn default() -> Self {
        Self {
            waiting_on_first_fend: true,
            in_fesc: false,
            current_frame: KissFrame::default(),
        }
    }
}

#[derive(Debug)]
pub struct KissClient {
    frame_sender: mpsc::Sender<Vec<u8>>,
    #[allow(dead_code)]
    handle: thread::JoinHandle<()>,
    #[allow(dead_code)]
    writer_handle: thread::JoinHandle<()>,
    running: Arc<AtomicBool>,
    kiss_connection: Arc<Mutex<Option<TcpStream>>>,
}

impl Drop for KissClient {
    fn drop(&mut self) {
        self.running.store(false, Ordering::Relaxed);

        if let Some(connection) = self.kiss_connection.lock().expect("failed to acquire kiss connection lock").as_ref() {
            let _ = connection.shutdown(Shutdown::Both);
        }
    }
}

impl KissClient {
    pub fn new(host: String, port: u16, message_sender: mpsc::Sender<Message>) -> Self {
        let (frame_sender, frame_receiver) = mpsc::channel();
        let running = Arc::new(AtomicBool::new(true));
        let kiss_connection: Arc<Mutex<Option<TcpStream>>> = Arc::new(Mutex::new(None));

        let handle = {
            let running = running.clone();
            let kiss_connection = kiss_connection.clone();
            thread::spawn(move || Self::run(host, port, running, message_sender, kiss_connection))
        };

        let writer_handle = {
            let running = running.clone();
            let kiss_connection = kiss_connection.clone();
            thread::spawn(move || Self::write_loop(frame_receiver, kiss_connection, running))
        };

        Self {
            frame_sender,
            handle,
            writer_handle,
            running,
            kiss_connection,
        }
    }

    fn run(
        host: String,
        port: u16,
        running: Arc<AtomicBool>,
        message_sender: mpsc::Sender<Message>,
        kiss_connection: Arc<Mutex<Option<TcpStream>>>,
    ) {
        if let Err(e) = config::validate_host(&host) {
            tracing::error!(host, port, "invalid kiss host: {}", e);
            return;
        }

        let connect_timeout = Duration::from_secs(5);
        let read_timeout = Duration::from_secs(10);
        let write_timeout = Duration::from_secs(10);

        while running.load(Ordering::Relaxed) {
            let read_stream = match Self::connect(&host, port, connect_timeout) {
                Some(stream) => {
                    let _ = message_sender.send(Message::ConnectedToTnc(true));
                    stream
                }
                None => {
                    let _ = message_sender.send(Message::ConnectedToTnc(false));
                    thread::sleep(connect_timeout);
                    continue
                },
            };

            if !running.load(Ordering::Relaxed) {
                break
            }

            tracing::info!(host, port, "connected to kiss server");
            let _ = read_stream.set_read_timeout(Some(read_timeout));

            let write_stream = read_stream
                .try_clone()
                .expect("failed to clone kiss connection for writing");
            let _ = write_stream.set_write_timeout(Some(write_timeout));
            *kiss_connection.lock().expect("failed to acquire kiss connection lock") = Some(write_stream);

            Self::read_loop(read_stream, &running, &message_sender);

            *kiss_connection.lock().expect("failed to acquire kiss connection lock") = None;
        }
    }

    fn connect(host: &str, port: u16, timeout: Duration) -> Option<TcpStream> {
        let addrs = match (host, port).to_socket_addrs() {
            Ok(addrs) => addrs,
            Err(e) => {
                tracing::warn!(kind = ?e.kind(), host, port, "error resolving kiss host");
                return None
            },
        };

        // A hostname can resolve to several addresses.
        // try each until one connects.
        for addr in addrs {
            match TcpStream::connect_timeout(&addr, timeout) {
                Ok(stream) => return Some(stream),
                Err(e) => {
                    tracing::warn!(kind = ?e.kind(), %addr, host, port, "error connecting to kiss server");
                },
            }
        }

        None
    }

    fn read_loop(mut read_stream: TcpStream, running: &AtomicBool, message_sender: &mpsc::Sender<Message>) {
        let mut kiss_frame_state = KissFrameState::default();
        while running.load(Ordering::Relaxed) {
            let mut buf = [0; 128];
            match read_stream.read(&mut buf) {
                Ok(0) => break,
                Ok(num_read) => {
                    Self::process_bytes(&mut kiss_frame_state, &buf[..num_read], message_sender);
                },
                Err(e) => match e.kind() {
                    ErrorKind::Interrupted |
                    ErrorKind::TimedOut |
                    ErrorKind::WouldBlock => {
                        continue
                    },
                    _ => {
                        tracing::error!(kind = ?e.kind(), "error reading bytes from kiss server");
                        break
                    }
                },
            }
        }
    }

    fn process_frame(kiss_frame: &KissFrame) -> Result<Ax25Frame, Ax25Error> {
        if kiss_frame.raw_bytes.is_empty() {
            return Err(Ax25Error::InvalidFrame)
        }

        let cmd_type = kiss_frame.raw_bytes[0] & 0x0f;
        if cmd_type != KISS::CMD_TYPE_DATA {
            tracing::debug!(cmd_type, "ignoring non-data kiss frame");
            return Err(Ax25Error::InvalidFrame)
        }

        //tracing::debug!(raw = ?kiss_frame.raw_bytes, "raw bytes");

        Ax25Frame::decode(&kiss_frame.raw_bytes[1..])
    }

    fn process_byte(kiss_frame_state: &mut KissFrameState, byte: u8) {
        // discard any bytes until our first FEND
        if kiss_frame_state.waiting_on_first_fend && byte != KISS::FEND { return; }

        if kiss_frame_state.in_fesc {
            kiss_frame_state.in_fesc = false;
            match byte {
                KISS::TFESC => {
                    kiss_frame_state.current_frame.raw_bytes.push(KISS::FESC);
                }
                KISS::TFEND => {
                    kiss_frame_state.current_frame.raw_bytes.push(KISS::FEND);
                }
                _ => {
                    tracing::debug!(byte, "ignoring unexpected byte after escape");
                }
            }
        } else {
            kiss_frame_state.current_frame.raw_bytes.push(byte);
        }
    }

    fn process_bytes(mut kiss_frame_state: &mut KissFrameState, buf: &[u8], message_sender: &mpsc::Sender<Message>) {
        for &byte in buf.iter() {
            match byte {
                KISS::FEND => {
                    if kiss_frame_state.waiting_on_first_fend {
                        kiss_frame_state.waiting_on_first_fend = false;
                    }

                    match Self::process_frame(&kiss_frame_state.current_frame) {
                        Ok(frame) => {
                            let _ = message_sender.send(Message::Ax25FrameReceived(frame));
                        }
                        _ => {}
                    }
                    kiss_frame_state.current_frame = KissFrame::default();
                },
                KISS::FESC => {
                    kiss_frame_state.in_fesc = true;
                },
                _ => {
                    Self::process_byte(&mut kiss_frame_state, byte);
                }
            }
        }
    }

    fn write_loop(frame_receiver: mpsc::Receiver<Vec<u8>>, kiss_connection: Arc<Mutex<Option<TcpStream>>>, running: Arc<AtomicBool>) {
        while running.load(Ordering::Relaxed) {
            match frame_receiver.recv_timeout(Duration::from_millis(250)) {
                Ok(frame) => {
                    let bytes: &[u8] = &KISS::encode(&frame);
                    match kiss_connection.lock().expect("failed to acquire kiss connection lock").as_mut() {
                        Some(connection) => {
                            if let Err(e) = connection.write_all(&bytes) {
                                tracing::error!(kind = ?e.kind(), "error writing frame to kiss server");
                            }
                        },
                        None => tracing::warn!("dropping outgoing frame. not connected to kiss server"),
                    }
                },
                Err(mpsc::RecvTimeoutError::Timeout) => continue,
                Err(mpsc::RecvTimeoutError::Disconnected) => break,
            }
        }
    }

    pub fn send(&self, bytes: Vec<u8>) {
        self.frame_sender
            .send(bytes)
            .expect("kiss writer thread has died");
    }
}
