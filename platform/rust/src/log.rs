//! The list of things to be displayed on screen.
//!
//! An item is a record that can generate content for rendering.
//!
//! A `Log` owns its items outright and holds no reference back to whatever
//! produced them. Producers keep the `LogId` of anything they published and
//! send a whole replacement item when it changes.
use std::{
    collections::VecDeque,
    sync::atomic::{AtomicU64, Ordering},
    time::{SystemTime, UNIX_EPOCH},
};

use crate::globals::TERMINAL_WIDTH;
use crate::kiss::Ax25Addr;

const MAX_LOG_ITEMS: usize = 20000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LogId(u64);

static NEXT_LOG_ID: AtomicU64 = AtomicU64::new(1);

pub fn next_log_id() -> LogId {
    LogId(NEXT_LOG_ID.fetch_add(1, Ordering::Relaxed))
}

pub fn utc_timestamp(at: SystemTime) -> String {
    let secs = at
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("[{:02}:{:02}:{:02}Z]", (secs / 3600) % 24, (secs / 60) % 60, secs % 60)
}

pub fn format_digipeaters(digipeaters: &[Ax25Addr]) -> String {
    let last_repeated = digipeaters.iter().rposition(|d| d.repeated());
    digipeaters
        .iter()
        .enumerate()
        .map(|(i, d)| if Some(i) == last_repeated { format!("{d}*") } else { d.to_string() })
        .collect::<Vec<String>>()
        .join(",")
}

/// A flattened APRS packet for display.
#[derive(Debug, Clone)]
pub struct FrameLogItem {
    pub seq: u64,
    pub at: SystemTime,
    pub source: String,
    pub dest: String,
    pub addressee: Option<String>,
    pub msg_id: Option<String>,
    pub data_type_id: char,
    pub body: String,
    pub digipeaters: String,
    pub ackable: bool,
    pub acked: bool,
    pub repeats: usize,
    pub user_station: String,
}

impl FrameLogItem {
    /// Whether this packet is traffic between two stations in either direction.
    pub fn between(&self, one: &str, other: &str) -> bool {
        let Some(addressee) = self.addressee.as_deref() else { return false };

        let from_one = self.source.eq_ignore_ascii_case(one)
            && addressee.eq_ignore_ascii_case(other);
        let from_other = self.source.eq_ignore_ascii_case(other)
            && addressee.eq_ignore_ascii_case(one);

        from_one || from_other
    }

    /// If this is a contact between a station and user's station, returns
    /// the station
    pub fn get_contact_station(&self, my_station: &str) -> Option<String> {
        let Some(ref addressee) = self.addressee else { return None };
        if self.source.eq_ignore_ascii_case(my_station) {
            return Some(addressee.to_string());
        }

        if addressee.eq_ignore_ascii_case(my_station) {
            return Some(self.source.to_string());
        }
        None
    }

    pub fn header(&self) -> String {
        let mut left_components: Vec<String> = Vec::new(); 
        let mut right_components: Vec<String> = Vec::new();

        left_components.push(utc_timestamp(self.at));

        if let Some(addressee) = &self.addressee {
            left_components.push(format!("from: {} to: {}", self.source.clone(), addressee));
        } else {
            left_components.push(format!("from: {}", self.source.clone()));
        }

        if self.ackable {
            right_components.push(format!("ack:{}", if self.acked { "✓" } else { "_" }));
        };

        if self.repeats > 0 {
            right_components.push(format!("rpt:{}", self.repeats));
        }

        right_components.push(format!("[id: {:04}]", self.seq));

        let left = left_components.join(" ");
        let right = right_components.join(" ");

        let content_len = left.chars().count() + right.chars().count();
        let terminal_width: usize = TERMINAL_WIDTH.into();
        let pad_len = terminal_width.saturating_sub(content_len);
        let middle = ' '.to_string().repeat(pad_len);

        format!("{}{}{}", left_components.join(" "), middle, right_components.join(" "))
    }

    fn line_count(&self) -> usize {
        if self.digipeaters.is_empty() { 3 } else { 4 }
    }

    fn lines(&self) -> Vec<String> {
        let mut lines = vec![self.header()];
        if !self.digipeaters.is_empty() {
            lines.push(format!("via {}", self.digipeaters));
        }
        lines.push(format!("{} {}", self.data_type_id, self.body));
        lines.push(String::new());
        lines
    }

}

/// General purpose text, e.g. help/usage, a frame dump, an error.
#[derive(Debug, Clone)]
pub struct Notice {
    pub lines: Vec<String>,
    pub level: LogItemLevel,
}

#[derive(Debug, Clone)]
pub enum LogItemLevel {
    Normal,
    High,
}

#[derive(Debug, Clone)]
pub enum LogItem {
    Frame { id: LogId, item: FrameLogItem },
    Notice { id: LogId, notice: Notice },
}

impl LogItem {
    pub fn frame(id: LogId, item: FrameLogItem) -> Self {
        Self::Frame { id, item }
    }

    pub fn notice(lines: Vec<String>, level: LogItemLevel) -> Self {
        Self::Notice {
            id: next_log_id(),
            notice: Notice { lines, level },
        }
    }

    pub fn id(&self) -> LogId {
        match self {
            Self::Frame { id, .. } => *id,
            Self::Notice { id, .. } => *id,
        }
    }

    pub fn line_count(&self) -> usize {
        match self {
            Self::Frame { item, .. } => item.line_count(),
            Self::Notice { notice, .. } => notice.lines.len(),
        }
    }

    pub fn lines(&self) -> Vec<String> {
        match self {
            Self::Frame { item, .. } => item.lines(),
            Self::Notice { notice, .. } => notice.lines.clone(),
        }
    }

    pub fn get_level(&self) -> LogItemLevel {
        match self {
            LogItem::Notice { .. } => LogItemLevel::Normal,
            LogItem::Frame { item, .. } => self.get_frame_level(item),
        }
    }

    fn get_frame_level(&self, item: &FrameLogItem) -> LogItemLevel {
        if item.source.eq_ignore_ascii_case(&item.user_station) {
            return LogItemLevel::High
        }

        if item.addressee.is_none() {
            return LogItemLevel::Normal
        }

        match &item.addressee {
            Some(addressee) => {
                if addressee.eq_ignore_ascii_case(&item.user_station) {
                    return LogItemLevel::High
                } else {
                    return LogItemLevel::Normal
                }
            },
            _ => { return LogItemLevel::Normal }
        }
    }

}

/// The items on screen, oldest first.
#[derive(Debug)]
pub struct Log {
    items: VecDeque<LogItem>,
    max_items: usize,
}

impl Log {
    pub fn new() -> Self {
        Self {
            items: VecDeque::with_capacity(MAX_LOG_ITEMS),
            max_items: MAX_LOG_ITEMS,
        }
    }

    pub fn push(&mut self, item: LogItem) {
        if self.items.len() == self.max_items {
            self.items.pop_front();
        }
        self.items.push_back(item);
    }

    /// Replaces an item with a newer version of itself, matched on `LogId`.
    ///
    /// If an item is not found, the replace is ignored.
    pub fn replace(&mut self, replacement: LogItem) {
        let id = replacement.id();
        if let Some(existing) = self.items.iter_mut().rev().find(|i| i.id() == id) {
            *existing = replacement;
        }
    }

    pub fn clear(&mut self) {
        self.items.clear();
    }

    pub fn iter(&self) -> impl Iterator<Item = &LogItem> {
        self.items.iter()
    }

}

#[cfg(test)]
mod tests {
    use super::*;

    fn frame_log_item(seq: u64) -> FrameLogItem {
        FrameLogItem {
            seq,
            at: UNIX_EPOCH,
            source: String::from("NOCALL"),
            dest: String::from("APKTY1"),
            addressee: None,
            msg_id: None,
            data_type_id: ':',
            body: String::from("hello"),
            digipeaters: String::new(),
            ackable: false,
            acked: false,
            repeats: 0,
            user_station: String::from("NOCALL"),
        }
    }

    #[test]
    fn replace_replaces_the_item_with_the_matching_id() {
        let mut log = Log::new();
        let id = next_log_id();

        log.push(LogItem::frame(id, frame_log_item(1)));
        log.push(LogItem::notice(vec![String::from("unrelated")], LogItemLevel::Normal));

        let mut changed = frame_log_item(1);
        changed.repeats = 2;
        log.replace(LogItem::frame(id, changed));

        let replaced = log.iter().find(|i| i.id() == id).expect("item should still be present");
        assert!(replaced.lines()[0].contains("rpt:2"), "got {:?}", replaced.lines()[0]);
    }

    #[test]
    fn replace_for_an_evicted_item_is_dropped() {
        let mut log = Log::new();
        log.replace(LogItem::frame(next_log_id(), frame_log_item(1)));

        assert_eq!(log.iter().count(), 0);
    }

    #[test]
    fn push_at_capacity_evicts_the_oldest_item() {
        let mut log = Log::new();
        log.max_items = 2;

        let first = next_log_id();
        log.push(LogItem::frame(first, frame_log_item(1)));
        log.push(LogItem::frame(next_log_id(), frame_log_item(2)));
        log.push(LogItem::frame(next_log_id(), frame_log_item(3)));

        assert!(log.iter().all(|i| i.id() != first));
    }

    #[test]
    fn line_count_includes_the_via_line_only_when_there_is_a_path() {
        let direct = LogItem::frame(next_log_id(), frame_log_item(1));
        assert_eq!(direct.line_count(), 3);

        let mut item = frame_log_item(2);
        item.digipeaters = String::from("WIDE1-1*");
        assert_eq!(LogItem::frame(next_log_id(), item).line_count(), 4);
    }

    #[test]
    fn header_shows_addressee_and_kiss_id() {
        let mut item = frame_log_item(3);
        item.addressee = Some(String::from("NOCALL-1"));
        item.msg_id = Some(String::from("5"));

        let header = item.header();

        assert!(header.contains("[id: 0003]"), "got {header}");
        assert!(header.contains("to: NOCALL-1"), "got {header}");
    }

    #[test]
    fn header_shows_ack_marker_and_repeat_count() {
        let mut item = frame_log_item(0);
        item.ackable = true;
        item.acked = true;
        item.repeats = 2;

        assert!(item.header().contains("  ack:✓ rpt:2"), "got {}", item.header());
    }

    #[test]
    fn header_unacked_ackable_message_shows_pending_marker() {
        let mut item = frame_log_item(0);
        item.ackable = true;

        let header = item.header();

        assert!(header.contains("ack:_"), "got {header}");
        assert!(!header.contains("rpt:"), "got {header}");
    }

    #[test]
    fn header_omits_ack_marker_when_not_ackable() {
        assert!(!frame_log_item(0).header().contains("ack:"));
    }

    #[test]
    fn header_omits_addressee_when_there_is_none() {
        assert!(!frame_log_item(0).header().contains("→"));
    }
}
