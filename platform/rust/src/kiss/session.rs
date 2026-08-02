//! Keeps track of what we hear on the air and what we send for the entire
//! duration of a kisstty session.
//!
//! Every distinct packet gets one `SessionFrame`, which publishes a single
//! item to the log under its own `LogId`.
//!
//! The "same" packet arriving again by a different digipeater path does not
//! get an item of its own. Instead it gets attached to the packet already
//! stored, and that frame publishes a fresh item under the same `LogId` so
//! the log replaces what it was showing.
//!
//! Acks behave the same way. An ack gets attached to the message it
//! acknowledges instead of being displayed to the user as a message.
//!
//! An incoming frame ends up in one of four places:
//!
//!   recorded   - a new SessionFrame, displayed as output to user
//!   attached   - attached to the SessionFrame we have, updates visual header
//!   dropped    - an ack we cannot match to any message we know about
//!   suppressed - a frame from our callsign that no digipeater repeated.
//!                Either the TNC handed our own bytes back, or somebody
//!                transmitted as us.
//!
//! Frames the user sends are recorded right away, before anything comes back,
//! so they see their message the moment they send it. Acks the user sends
//! are never displayed, though they'll get attached to the actual sender's
//! message if we get our ack echoed back to us.

use std::{
    collections::{ hash_map::DefaultHasher, HashMap, VecDeque },
    hash::{ Hash, Hasher },
    sync::mpsc,
    time::{ Duration, Instant, SystemTime },
};

use crate::{
    config::Config,
    kiss::{
        parse_digipeater_path,
        AprsData, AprsMessage, Ax25Addr, Ax25Frame,
        KissClient,
    },
    log::{format_digipeaters, next_log_id, utc_timestamp, FrameLogItem, LogId, LogItem},
    message::Message,
};

const MAX_SESSION_FRAMES: usize = 5000;
const ACK_THROTTLE: Duration    = Duration::from_secs(30);
const REPEAT_WINDOW: Duration   = Duration::from_secs(30);


// only care about source, dest, data.
// digis may differ, but the frame should still be considered a duplicate
fn dedup_hash(frame: &Ax25Frame) -> u64 {
    let mut hasher = DefaultHasher::new();
    frame.source().to_string().hash(&mut hasher);
    frame.dest().to_string().hash(&mut hasher);
    frame.data().encode().hash(&mut hasher);
    hasher.finish()
}

/// One frame exactly as it reached us, with the time we saw it. Used for both
/// frames we receive and frames we send.
#[derive(Debug)]
struct FrameInstance {
    at: SystemTime,
    frame: Ax25Frame,
}

impl FrameInstance {
    pub fn new(frame: Ax25Frame) -> Self {
        Self { at: SystemTime::now(), frame }
    }

    /// Outputs the unique part of a FrameInstance (digis, timestamp)
    pub fn describe(&self) -> String {
        let path = format_digipeaters(self.frame.digipeaters());
        let path = if path.is_empty() { String::from("direct") } else { path };
        format!("{} {}", utc_timestamp(self.at), path)
    }
}

/// One packet, plus every copy of it we heard. `first` is the copy that
/// created the group.
///
/// `repeats` are the ones that came in after, usually the same packet
/// repeated by digipeaters.
#[derive(Debug)]
struct FrameGroup {
    dedup_hash: u64,
    first: FrameInstance,
    repeats: Vec<FrameInstance>,
}

impl FrameGroup {
    pub fn new(frame: Ax25Frame) -> Self {
        Self {
            dedup_hash: dedup_hash(&frame),
            first: FrameInstance::new(frame),
            repeats: Vec::new(),
        }
    }

    pub fn matches_hash(&self, hash: u64) -> bool {
        self.dedup_hash == hash
    }

    pub fn record_repeat(&mut self, frame: Ax25Frame) {
        self.repeats.push(FrameInstance::new(frame));
    }

    pub fn repeat_count(&self) -> usize {
        self.repeats.len()
    }

    pub fn source(&self) -> &Ax25Addr {
        self.first.frame.source()
    }
}

/// One entry in the session.
///
/// `id` is the number shown in the display header and the one the user uses
/// to refer back to this frame. `log_id` is the id of the item this frame
/// references in the log, so a repeat or an ack can update (replace) it.
///
/// `acked_by` collects the acks, keyed on the same content hash used for
/// repeats, so digipeated copies of one ack collapse together rather than
/// looking like separate acks.
#[derive(Debug)]
struct SessionFrame {
    id: u64,
    log_id: LogId,
    instances: FrameGroup,
    acked_by: Vec<FrameGroup>,
}

impl SessionFrame {
    pub fn new(id: u64, frame: Ax25Frame) -> Self {
        Self {
            id,
            log_id: next_log_id(),
            instances: FrameGroup::new(frame),
            acked_by: Vec::new(),
        }
    }

    pub fn first_frame(&self) -> &Ax25Frame {
        &self.instances.first.frame
    }

    pub fn first_at(&self) -> SystemTime {
        self.instances.first.at
    }

    pub fn is_acked(&self) -> bool {
        !self.acked_by.is_empty()
    }

    /// Whether an ack is possible at all. Only messages carrying an id can be
    /// acked. i.e., APRS info type 'message'.
    pub fn is_ackable(&self) -> bool {
        matches!(self.first_frame().data(), AprsData::Message(msg) if msg.id.is_some())
    }

    /// This frame converted into a format for the log.
    ///
    /// The FrameLogItem is recreated when there's a repeat or an ack that
    /// changed what might get displayed to the user.
    pub fn to_frame_log_item(&self) -> FrameLogItem {
        let frame = self.first_frame();
        let data = frame.data();

        let (addressee, msg_id) = match data {
            AprsData::Message(msg) => (Some(msg.addressee.clone()), msg.id.clone()),
            _ => (None, None),
        };

        FrameLogItem {
            seq: self.id,
            at: self.first_at(),
            source: frame.source().to_string(),
            dest: frame.dest().to_string(),
            addressee,
            msg_id,
            data_type_id: data.data_type_id(),
            body: data.body().to_string(),
            digipeaters: format_digipeaters(frame.digipeaters()),
            ackable: self.is_ackable(),
            acked: self.is_acked(),
            repeats: self.instances.repeat_count(),
        }
    }

    pub fn to_log_item(&self) -> LogItem {
        LogItem::frame(self.log_id, self.to_frame_log_item())
    }

    /// The header and body, then one line per instance and ack.
    ///
    /// Instances only differ by the digi path and the timestamp.
    pub fn render_dump(&self) -> Vec<String> {
        let data = self.first_frame().data();
        let mut lines = vec![
            format!("dump of frame {:04}:", self.id),
            self.to_frame_log_item().header(),
            format!("  {} {}", data.data_type_id(), data.body()),
            format!("  first {}", self.instances.first.describe()),
        ];

        for repeat in &self.instances.repeats {
            lines.push(format!("  rpt   {}", repeat.describe()));
        }

        for ack in &self.acked_by {
            lines.push(format!("  ack   {} {}", ack.source(), ack.first.describe()));
            for repeat in &ack.repeats {
                lines.push(format!("    rpt {}", repeat.describe()));
            }
        }

        lines.push(String::new());
        lines
    }
}

#[derive(Debug)]
pub struct KissSession {
    message_sender: mpsc::Sender<Message>,
    client: Option<KissClient>,
    mycall: Option<Ax25Addr>,
    digipeaters: Vec<Ax25Addr>,
    outgoing_ids: HashMap<String, u64>,
    last_ack_sent: HashMap<(String, String), Instant>,
    frames: VecDeque<SessionFrame>,
    next_frame_id: u64,
    max_frames: usize,
}

fn to_base36(mut value: u64) -> String {
    const DIGITS: &[u8] = b"0123456789abcdefghijklmnopqrstuvwxyz";
    if value == 0 {
        return String::from("0");
    }

    let mut buf = Vec::new();
    while value > 0 {
        buf.push(DIGITS[(value % 36) as usize]);
        value /= 36;
    }
    buf.reverse();
    String::from_utf8(buf).expect("base36 digits are ascii")
}

impl KissSession {
    pub fn new(message_sender: mpsc::Sender<Message>) -> Self {
        Self {
            message_sender: message_sender,
            client: None,
            mycall: None,
            digipeaters: Vec::new(),
            outgoing_ids: HashMap::new(),
            last_ack_sent: HashMap::new(),
            frames: VecDeque::with_capacity(MAX_SESSION_FRAMES),
            next_frame_id: 0,
            max_frames: MAX_SESSION_FRAMES,
        }
    }

    pub fn start(&mut self, config: &Config) {
        if self.client.is_some() {
            return;
        }
        self.configure(config);
        self.client = Some(KissClient::new(
            config.kiss_host.clone(),
            config.kiss_port,
            self.message_sender.clone(),
        ));
    }

    fn configure(&mut self, config: &Config) {
        self.mycall = match Ax25Addr::parse(&config.callsign) {
            Ok(addr) => Some(addr),
            Err(err) => {
                tracing::warn!(%err, "ignoring invalid source callsign from config");
                None
            }
        };
        self.digipeaters = parse_digipeater_path(&config.digipeaters).unwrap_or_else(|err| {
            tracing::warn!(%err, "ignoring invalid digipeater path from config");
            Vec::new()
        });
    }

    pub fn restart(&mut self, config: &Config) {
        self.client = None;
        self.start(config);
    }

    pub fn try_claim(&mut self, message: Message) -> Option<Message> {
        match message {
            Message::SendAprsMessage { addressee, text } => {
                let id = if AprsMessage::is_broadcast_addressee(&addressee) {
                    None
                } else {
                    Some(self.next_message_id(&addressee))
                };
                if let Some(frame) = self.send_aprs_message(AprsMessage::new(addressee, text, id)) {
                    self.record_first_frame(frame);
                }
                None
            },
            Message::Ax25FrameReceived(frame) => {
                self.handle_received_frame(frame);
                None
            },
            Message::Dump(id) => {
                self.dump_frame(id);
                None
            },
            other => Some(other),
        }
    }

    fn send_aprs_message(&mut self, message: AprsMessage) -> Option<Ax25Frame> {
        let Some(source) = self.mycall.clone() else { return None; };

        let dest = Ax25Addr::new(Ax25Addr::AX25DEST.to_string(), 0);
        let data = AprsData::Message(message);
        let frame = Ax25Frame::new(dest, source, self.digipeaters.clone(), data);
        self.send_frame(&frame);
        Some(frame)
    }


    fn next_message_id(&mut self, addressee: &str) -> String {
        let next = self.outgoing_ids.entry(addressee.to_string()).or_insert(1);
        let id = to_base36(*next);
        *next += 1;
        id
    }

    fn send_frame(&self, frame: &Ax25Frame) {
        tracing::trace!(
            source = %frame.source(),
            dest = %frame.dest(),
            body = %frame.data().body(),
            "tx frame",
        );

        match &self.client {
            Some(client) => client.send(frame.encode()),
            None => tracing::warn!("no kiss connection; dropping outgoing frame"),
        }
    }

    /// Decides where an incoming frame goes, narrowing from most specific to
    /// least:
    ///
    ///   is it our own bytes handed back? suppress it
    ///   does it acknowledge a message?   attach it there
    ///   have we already got this packet? attach it as a repeat
    ///   otherwise                        it is new, record it
    ///
    /// Acking happens up front, outside that chain, because we ack a message
    /// whether or not the copy carrying it turns out to be a duplicate.
    fn handle_received_frame(&mut self, frame: Ax25Frame) {
        tracing::trace!(
            source = %frame.source(),
            dest = %frame.dest(),
            body = %frame.data().body(),
            "rx frame",
        );

        if self.is_local_echo(&frame) { return }

        self.maybe_send_ack(&frame);

        let Some(frame) = self.try_attach_ack(frame) else { return };
        let Some(frame) = self.try_attach_repeat(frame) else { return };

        self.record_first_frame(frame);
    }

    fn is_mycall(&self, call: &str) -> bool {
        self.mycall.as_ref().is_some_and(|c| c.to_string() == call)
    }

    /// True if the frame source is our callsign but no digipeater repeated it.
    ///
    /// This could happen if:
    /// * the TNC hands back the bytes we gave it
    /// * someone is impersonating us
    ///
    /// In that case, we log it but don't count it in our totals.
    fn is_local_echo(&self, frame: &Ax25Frame) -> bool {
        if !self.is_mycall(&frame.source().to_string()) {
            return false;
        }

        if frame.digipeaters().iter().any(|d| d.repeated()) {
            return false;
        }

        tracing::debug!(
            body = %frame.data().body(),
            "suppressing frame from our callsign that no digipeater repeated",
        );
        true
    }

    /// Attaches a duplicate copy to the frame it duplicates.
    ///
    /// Only looks back as far as `REPEAT_WINDOW`.
    fn try_attach_repeat(&mut self, frame: Ax25Frame) -> Option<Ax25Frame> {
        let hash = dedup_hash(&frame);
        let now = SystemTime::now();

        let mut found = None;
        for (i, session_frame) in self.frames.iter().enumerate().rev() {
            let elapsed = now.duration_since(session_frame.first_at()).unwrap_or_default();
            if elapsed > REPEAT_WINDOW {
                break;
            }
            if session_frame.instances.matches_hash(hash) {
                found = Some(i);
                break;
            }
        }

        let Some(idx) = found else { return Some(frame) };

        let session_frame = &mut self.frames[idx];
        session_frame.instances.record_repeat(frame);
        tracing::debug!(
            id = session_frame.id,
            repeats = session_frame.instances.repeat_count(),
            "attached repeat",
        );

        let update = session_frame.to_log_item();
        let _ = self.message_sender.send(Message::LogUpdate(update));
        None
    }

    /// Stores and counts an ack against the message it acknowledges.
    ///
    /// An ack's addressee is the source from the original message, and the
    /// ack's source is the addressee from the original message.
    ///
    /// A message shows as acked if we heard an ack for it, whether or not we
    /// are the sender, receiver, or just listening.
    ///
    /// An ack for a message not in our frames vec is dropped.
    fn try_attach_ack(&mut self, frame: Ax25Frame) -> Option<Ax25Frame> {
        let AprsData::Message(msg) = frame.data() else { return Some(frame) };
        let Some(ack_id) = msg.ack_id().map(|id| id.to_string()) else { return Some(frame) };

        let originator = msg.addressee.clone();
        let acker = frame.source().to_string();
        let hash = dedup_hash(&frame);

        let found = self.frames.iter().rposition(|session_frame| {
            let acked = session_frame.first_frame();
            let AprsData::Message(acked_msg) = acked.data() else { return false };
            acked.source().to_string() == originator
                && acked_msg.addressee == acker
                && acked_msg.id.as_deref() == Some(ack_id.as_str())
        });

        let Some(idx) = found else {
            tracing::debug!(%acker, %originator, %ack_id, "dropping ack; no matching message in history");
            return None;
        };

        let session_frame = &mut self.frames[idx];
        match session_frame.acked_by.iter_mut().find(|g| g.matches_hash(hash)) {
            Some(group) => group.record_repeat(frame),
            None => session_frame.acked_by.push(FrameGroup::new(frame)),
        }
        tracing::debug!(
            id = session_frame.id,
            %acker,
            ackers = session_frame.acked_by.len(),
            "attached ack",
        );

        let update = session_frame.to_log_item();
        let _ = self.message_sender.send(Message::LogUpdate(update));
        None
    }

    fn dump_frame(&self, id: u64) {
        match self.frames.iter().rev().find(|f| f.id == id) {
            Some(session_frame) => self.send_lines(session_frame.render_dump()),
            None => self.send_lines(vec![format!("{id:04}: frame not found"), String::new()]),
        }
    }

    fn send_lines(&self, lines: Vec<String>) {
        let _ = self.message_sender.send(Message::LogPublish(LogItem::notice(lines)));
    }

    /// Stores a frame we have not seen before and puts it on screen.
    ///
    /// The deque is a ring buffer. Once it is full the oldest frame drops off
    /// and ids wrap around, so an id always refers to whatever holds it now.
    fn record_first_frame(&mut self, frame: Ax25Frame) {
        tracing::debug!(
            id = self.next_frame_id,
            source = %frame.source(),
            "recorded first frame",
        );

        let id = self.next_frame_id;
        self.next_frame_id = (self.next_frame_id + 1) % self.max_frames as u64;

        let session_frame = SessionFrame::new(id, frame);
        let _ = self.message_sender.send(Message::LogPublish(session_frame.to_log_item()));

        if self.frames.len() == self.max_frames {
            self.frames.pop_front();
        }
        self.frames.push_back(session_frame);
    }

    /// Acks a message addressed to us, at most once per sender and message id
    /// within `ACK_THROTTLE`. Every digipeated copy reaches here, so the
    /// throttle is the only thing stopping us from acking each one.
    fn maybe_send_ack(&mut self, frame: &Ax25Frame) {
        let AprsData::Message(msg) = frame.data() else { return };
        if !self.is_mycall(&msg.addressee) || msg.is_ack() { return }
        let Some(msg_id) = msg.id.as_deref() else { return };
        let ack_addressee = frame.source();

        let now = Instant::now();
        self.last_ack_sent.retain(|_, &mut t| now.duration_since(t) < ACK_THROTTLE);

        let key = (ack_addressee.to_string(), msg_id.to_string());
        if self.last_ack_sent.contains_key(&key) { return; }

        tracing::debug!(to = %key.0, id = %key.1, "acking received message");
        self.send_aprs_message(AprsMessage::new(key.0.clone(), format!("ack{}", key.1), None));
        self.last_ack_sent.insert(key, now);
    }

}

#[cfg(test)]
mod tests {
    use super::*;

    const MYCALL: &str = "NOCALL";

    fn session() -> (KissSession, mpsc::Receiver<Message>) {
        let (sender, receiver) = mpsc::channel();
        let mut session = KissSession::new(sender);
        session.configure(&Config {
            callsign: MYCALL.to_string(),
            digipeaters: vec!["WIDE1-1".to_string()],
            ..Config::default()
        });
        (session, receiver)
    }

    fn addr(call: &str) -> Ax25Addr {
        Ax25Addr::parse(call).expect("test callsign should be valid")
    }

    fn message(source: &str, addressee: &str, text: &str, id: Option<&str>) -> Ax25Frame {
        message_with_digis(source, addressee, text, id, &[])
    }

    fn message_with_digis(
        source: &str,
        addressee: &str,
        text: &str,
        id: Option<&str>,
        digis: &[&str],
    ) -> Ax25Frame {
        Ax25Frame::new(
            addr(Ax25Addr::AX25DEST),
            addr(source),
            digis.iter().map(|d| addr(d)).collect(),
            AprsData::Message(AprsMessage::new(
                addressee.to_string(),
                text.to_string(),
                id.map(|i| i.to_string()),
            )),
        )
    }

    // The only way to build an Ax25Addr with the H bit set is to decode one,
    // so round-trip through the wire format and flip it on the first digi.
    fn digipeated(frame: &Ax25Frame) -> Ax25Frame {
        let mut bytes = frame.encode();
        assert!(!frame.digipeaters().is_empty(), "frame needs a digipeater to repeat");
        bytes[14 + 6] |= 0b1000_0000;
        Ax25Frame::decode(&bytes).expect("re-encoded frame should decode")
    }

    fn raw_info_frame(source: &str, info: &[u8]) -> Ax25Frame {
        let mut bytes = Vec::new();
        bytes.extend(addr(Ax25Addr::AX25DEST).encode_dest());
        bytes.extend(addr(source).encode(true));
        bytes.push(0x03);
        bytes.push(0xf0);
        bytes.extend(info);
        Ax25Frame::decode(&bytes).expect("hand-built frame should decode")
    }

    fn receive(session: &mut KissSession, frame: Ax25Frame) {
        session.try_claim(Message::Ax25FrameReceived(frame));
    }

    fn send(session: &mut KissSession, addressee: &str, text: &str) {
        session.try_claim(Message::SendAprsMessage {
            addressee: addressee.to_string(),
            text: text.to_string(),
        });
    }

    fn last_log_update(receiver: &mpsc::Receiver<Message>) -> Option<LogItem> {
        let mut last = None;
        while let Ok(message) = receiver.try_recv() {
            if let Message::LogUpdate(item) = message {
                last = Some(item);
            }
        }
        last
    }

    fn publish_count(receiver: &mpsc::Receiver<Message>) -> usize {
        let mut count = 0;
        while let Ok(message) = receiver.try_recv() {
            if matches!(message, Message::LogPublish(_)) {
                count += 1;
            }
        }
        count
    }

    #[test]
    fn dedup_hash_ignores_digipeater_path() {
        let direct = message_with_digis("NOCALL-1", MYCALL, "hello", Some("1"), &[]);
        let one_hop = message_with_digis("NOCALL-1", MYCALL, "hello", Some("1"), &["WIDE1-1"]);
        let two_hops = message_with_digis("NOCALL-1", MYCALL, "hello", Some("1"), &["NOCALL-2", "WIDE2-1"]);

        assert_eq!(dedup_hash(&direct), dedup_hash(&one_hop));
        assert_eq!(dedup_hash(&direct), dedup_hash(&two_hops));
    }

    #[test]
    fn dedup_hash_distinguishes_frame_contents() {
        let base = message("NOCALL-1", MYCALL, "hello", Some("1"));
        let cases = vec![
            ("source", message("NOCALL-2", MYCALL, "hello", Some("1"))),
            ("addressee", message("NOCALL-1", "NOCALL-2", "hello", Some("1"))),
            ("text", message("NOCALL-1", MYCALL, "goodbye", Some("1"))),
            ("id", message("NOCALL-1", MYCALL, "hello", Some("2"))),
        ];

        for (field, other) in cases {
            assert_ne!(
                dedup_hash(&base),
                dedup_hash(&other),
                "differing {field} should change the hash",
            );
        }
    }

    #[test]
    fn to_frame_log_item_carries_the_fields_the_display_filters_on() {
        let frame = message_with_digis(MYCALL, "NOCALL-1", "hello", Some("5"), &["WIDE1-1"]);
        let item = SessionFrame::new(3, frame).to_frame_log_item();

        assert_eq!(item.seq, 3);
        assert_eq!(item.source, MYCALL);
        assert_eq!(item.dest, Ax25Addr::AX25DEST);
        assert_eq!(item.addressee.as_deref(), Some("NOCALL-1"));
        assert_eq!(item.msg_id.as_deref(), Some("5"));
        assert_eq!(item.data_type_id, ':');
        assert_eq!(item.body, "hello");
        assert_eq!(item.digipeaters, "WIDE1-1");
    }

    #[test]
    fn to_frame_log_item_message_with_an_id_is_ackable() {
        let frame = message(MYCALL, "NOCALL-1", "hello", Some("1"));
        let item = SessionFrame::new(0, frame).to_frame_log_item();

        assert!(item.ackable);
        assert!(!item.acked);
    }

    #[test]
    fn to_frame_log_item_message_with_no_id_is_not_ackable() {
        let frame = message(MYCALL, "NOCALL-1", "hello", None);

        assert!(!SessionFrame::new(0, frame).to_frame_log_item().ackable);
    }

    #[test]
    fn to_frame_log_item_non_message_has_no_addressee_and_is_not_ackable() {
        let frame = raw_info_frame("NOCALL-1", b">status text");
        let item = SessionFrame::new(0, frame).to_frame_log_item();

        assert_eq!(item.addressee, None);
        assert_eq!(item.data_type_id, '>');
        assert!(!item.ackable);
    }

    #[test]
    fn to_frame_log_item_counts_repeats_and_acks() {
        let frame = message(MYCALL, "NOCALL-1", "hello", Some("1"));
        let mut session_frame = SessionFrame::new(0, frame.clone());
        session_frame.instances.record_repeat(frame.clone());
        session_frame.instances.record_repeat(frame.clone());
        session_frame.acked_by.push(FrameGroup::new(frame));

        let item = session_frame.to_frame_log_item();

        assert_eq!(item.repeats, 2);
        assert!(item.acked);
    }

    #[test]
    fn to_log_item_keeps_the_same_log_id_across_updates() {
        let frame = message(MYCALL, "NOCALL-1", "hello", Some("1"));
        let mut session_frame = SessionFrame::new(0, frame.clone());
        let before = session_frame.to_log_item().id();

        session_frame.instances.record_repeat(frame);

        assert_eq!(session_frame.to_log_item().id(), before);
    }

    #[test]
    fn render_dump_lists_every_copy_and_ack() {
        let frame = message_with_digis(MYCALL, "NOCALL-1", "hello", Some("1"), &["WIDE1-1"]);
        let mut session_frame = SessionFrame::new(3, frame.clone());
        session_frame.instances.record_repeat(digipeated(&frame));

        let ack = message_with_digis("NOCALL-1", MYCALL, "ack1", None, &["WIDE2-1"]);
        let mut ack_group = FrameGroup::new(ack.clone());
        ack_group.record_repeat(digipeated(&ack));
        session_frame.acked_by.push(ack_group);

        let dump = session_frame.render_dump();

        assert_eq!(dump[0], "dump of frame 0003:");
        assert!(dump[1].starts_with("0003: "), "got {:?}", dump[1]);
        assert_eq!(dump[2], "  : hello");
        assert!(dump[3].starts_with("  first "), "got {:?}", dump[3]);
        assert!(dump[3].ends_with(" WIDE1-1"), "got {:?}", dump[3]);
        assert!(dump[4].starts_with("  rpt   "), "got {:?}", dump[4]);
        assert!(dump[4].ends_with(" WIDE1-1*"), "got {:?}", dump[4]);
        assert!(dump[5].starts_with("  ack   NOCALL-1 "), "got {:?}", dump[5]);
        assert!(dump[6].starts_with("    rpt "), "got {:?}", dump[6]);
        assert_eq!(dump[7], "");
    }

    #[test]
    fn render_dump_with_no_digipeaters_reads_as_direct() {
        let frame = message(MYCALL, "NOCALL-1", "hello", Some("1"));
        let dump = SessionFrame::new(0, frame).render_dump();

        assert!(dump[3].ends_with(" direct"), "got {:?}", dump[3]);
    }

    #[test]
    fn render_dump_omits_ack_section_when_unacked() {
        let frame = message(MYCALL, "NOCALL-1", "hello", Some("1"));
        let dump = SessionFrame::new(0, frame).render_dump();

        assert!(!dump.iter().any(|l| l.contains("ack   ")), "got {dump:?}");
    }

    #[test]
    fn dump_frame_with_unknown_id_reports_not_found() {
        let (mut session, receiver) = session();
        receive(&mut session, message("NOCALL-1", "NOCALL-2", "hello", None));
        while receiver.try_recv().is_ok() {}

        session.try_claim(Message::Dump(77));

        assert_eq!(publish_count(&receiver), 1);
    }

    #[test]
    fn receive_new_frame_records_session_frame() {
        let (mut session, receiver) = session();

        receive(&mut session, message("NOCALL-1", "NOCALL-2", "hello", Some("1")));

        assert_eq!(session.frames.len(), 1);
        assert_eq!(publish_count(&receiver), 1);
    }

    #[test]
    fn receive_duplicate_attaches_repeat_instead_of_new_frame() {
        let (mut session, _receiver) = session();
        let frame = message("NOCALL-1", "NOCALL-2", "hello", Some("1"));

        receive(&mut session, frame.clone());
        receive(&mut session, frame);

        assert_eq!(session.frames.len(), 1);
        assert_eq!(session.frames[0].instances.repeat_count(), 1);
    }

    #[test]
    fn receive_duplicate_via_different_digipeaters_attaches_repeat() {
        let (mut session, _receiver) = session();

        receive(&mut session, message_with_digis("NOCALL-1", "NOCALL-2", "hi", Some("1"), &["WIDE1-1"]));
        receive(&mut session, message_with_digis("NOCALL-1", "NOCALL-2", "hi", Some("1"), &["NOCALL-9", "WIDE2-1"]));

        assert_eq!(session.frames.len(), 1);
        assert_eq!(session.frames[0].instances.repeat_count(), 1);
    }

    #[test]
    fn receive_differing_frame_records_separate_session_frame() {
        let (mut session, _receiver) = session();

        receive(&mut session, message("NOCALL-1", "NOCALL-2", "hello", Some("1")));
        receive(&mut session, message("NOCALL-1", "NOCALL-2", "hello", Some("2")));

        assert_eq!(session.frames.len(), 2);
    }

    #[test]
    fn receive_repeat_updates_the_item_already_published() {
        let (mut session, receiver) = session();
        let frame = message("NOCALL-1", "NOCALL-2", "hello", Some("1"));

        receive(&mut session, frame.clone());
        receive(&mut session, frame);

        let update = last_log_update(&receiver).expect("repeat should emit a log update");
        assert!(update.lines()[0].contains("rpt:1"), "got {:?}", update.lines()[0]);
        assert_eq!(
            update.id(),
            session.frames[0].log_id,
            "update must target the item that was originally published",
        );
    }

    #[test]
    fn send_to_a_broadcast_addressee_carries_no_message_id() {
        for addressee in ["CQ", "ALL", "QST", "BLN1", "BLNA", "BLN1WX", "cq"] {
            let (mut session, _receiver) = session();
            send(&mut session, addressee, "hello");

            assert!(
                !session.frames[0].is_ackable(),
                "{addressee} is a broadcast addressee and should not be ackable",
            );
        }
    }

    #[test]
    fn send_to_a_callsign_carries_a_message_id() {
        let (mut session, _receiver) = session();
        send(&mut session, "NOCALL-1", "hello");

        assert!(session.frames[0].is_ackable());
    }

    #[test]
    fn receive_ack_for_our_message_attaches_to_sent_frame() {
        let (mut session, receiver) = session();
        send(&mut session, "NOCALL-1", "hello");

        receive(&mut session, message("NOCALL-1", MYCALL, "ack1", None));

        assert_eq!(session.frames.len(), 1);
        assert_eq!(session.frames[0].acked_by.len(), 1);

        let update = last_log_update(&receiver).expect("ack should emit a log update");
        assert!(update.lines()[0].contains("ack:✓"), "got {:?}", update.lines()[0]);
        assert_eq!(update.id(), session.frames[0].log_id);
    }

    #[test]
    fn receive_duplicate_ack_copies_attach_as_one_acker() {
        let (mut session, _receiver) = session();
        send(&mut session, "NOCALL-1", "hello");
        let ack = message("NOCALL-1", MYCALL, "ack1", None);

        receive(&mut session, ack.clone());
        receive(&mut session, ack);

        assert_eq!(session.frames[0].acked_by.len(), 1);
        assert_eq!(session.frames[0].acked_by[0].repeat_count(), 1);
    }

    #[test]
    fn receive_ack_with_no_matching_message_is_dropped() {
        let (mut session, receiver) = session();

        receive(&mut session, message("NOCALL-1", MYCALL, "ack9", None));

        assert_eq!(session.frames.len(), 0);
        assert_eq!(publish_count(&receiver), 0);
    }

    #[test]
    fn receive_our_own_ack_heard_back_attaches_to_their_message() {
        let (mut session, _receiver) = session();
        receive(&mut session, message("NOCALL-1", MYCALL, "hello", Some("1")));

        let our_ack = message_with_digis(MYCALL, "NOCALL-1", "ack1", None, &["WIDE1-1"]);
        receive(&mut session, digipeated(&our_ack));

        assert_eq!(session.frames.len(), 1);
        assert_eq!(session.frames[0].acked_by.len(), 1);
    }

    #[test]
    fn receive_our_own_ack_for_our_own_message_attaches() {
        let (mut session, _receiver) = session();
        send(&mut session, MYCALL, "test");

        let our_ack = message_with_digis(MYCALL, MYCALL, "ack1", None, &["WIDE1-1"]);
        receive(&mut session, digipeated(&our_ack));

        assert_eq!(session.frames[0].acked_by.len(), 1);
    }

    #[test]
    fn receive_echo_of_our_own_message_attaches_as_repeat() {
        let (mut session, _receiver) = session();
        send(&mut session, "NOCALL-1", "hello");
        let sent = session.frames[0].first_frame().clone();

        receive(&mut session, digipeated(&sent));

        assert_eq!(session.frames.len(), 1);
        assert_eq!(session.frames[0].instances.repeat_count(), 1);
    }

    #[test]
    fn receive_third_party_ack_for_third_party_message_attaches() {
        let (mut session, _receiver) = session();
        receive(&mut session, message("NOCALL-1", "NOCALL-2", "hello", Some("4")));

        receive(&mut session, message("NOCALL-2", "NOCALL-1", "ack4", None));

        assert_eq!(session.frames.len(), 1);
        assert_eq!(session.frames[0].acked_by.len(), 1);
    }

    #[test]
    fn receive_message_addressed_to_us_sends_ack() {
        let (mut session, _receiver) = session();

        receive(&mut session, message("NOCALL-1", MYCALL, "hello", Some("1")));

        assert!(session.last_ack_sent.contains_key(&("NOCALL-1".to_string(), "1".to_string())));
    }

    #[test]
    fn receive_message_for_another_station_sends_no_ack() {
        let (mut session, _receiver) = session();

        receive(&mut session, message("NOCALL-1", "NOCALL-2", "hello", Some("1")));

        assert!(session.last_ack_sent.is_empty());
    }

    #[test]
    fn receive_duplicate_message_throttles_second_ack() {
        let (mut session, _receiver) = session();
        let frame = message("NOCALL-1", MYCALL, "hello", Some("1"));

        receive(&mut session, frame.clone());
        receive(&mut session, frame);

        assert_eq!(session.last_ack_sent.len(), 1);
    }

    #[test]
    fn receive_own_frame_repeated_by_digipeater_is_recorded() {
        let (mut session, receiver) = session();
        let ours = message_with_digis(MYCALL, "NOCALL-1", "unmatched", None, &["WIDE1-1"]);

        receive(&mut session, digipeated(&ours));

        assert_eq!(session.frames.len(), 1);
        assert_eq!(publish_count(&receiver), 1);
    }

    #[test]
    fn receive_own_frame_with_no_digipeater_repeat_is_suppressed() {
        let (mut session, receiver) = session();

        receive(&mut session, message_with_digis(MYCALL, "NOCALL-1", "unmatched", None, &["WIDE1-1"]));

        assert_eq!(session.frames.len(), 0);
        assert_eq!(publish_count(&receiver), 0);
    }

    #[test]
    fn record_first_frame_at_capacity_evicts_oldest_and_wraps_id() {
        let (mut session, _receiver) = session();
        session.max_frames = 4;

        for i in 0..=session.max_frames {
            receive(&mut session, message("NOCALL-1", "NOCALL-2", &format!("msg{i}"), None));
        }

        assert_eq!(session.frames.len(), 4);
        assert_eq!(
            session.frames.front().expect("deque is non-empty").id,
            1,
            "the oldest frame should be evicted, not the newest",
        );
        assert_eq!(session.frames.back().expect("deque is non-empty").id, 0);
        assert_eq!(session.next_frame_id, 1);
    }
}
