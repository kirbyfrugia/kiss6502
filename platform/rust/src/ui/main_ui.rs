use std::{
    cmp::min, sync::mpsc, time::{ Instant },
};

use ratatui::{
    crossterm::event::{KeyCode, KeyEvent, KeyModifiers},
    layout::{ Alignment, Constraint, Direction, Layout, Position, Rect, Size, Spacing, },
    style::{ Color, Modifier, Style, },
    widgets::{ Block, BorderType, Borders, Clear, List, ListItem, ListState, Paragraph, },
    symbols::merge::MergeStrategy,
    Frame,
};

use crate::{
    config::Config,
    globals::TERMINAL_WIDTH,
    kiss::{Ax25Addr, AprsMessage},
    log::{FrameLogItem, Log, LogItem},
    ui::{LineInput,LogView,MultiLineOutput},
    message::Message,
    slash::{SlashCommand, SLASH_COMMANDS},
};

const MAX_INPUT_LEN: usize     = 67;
const OUTPUT_AREA_WIDTH: u16   = TERMINAL_WIDTH + 4;
const MAX_AUTOCOMP_HEIGHT: u16 = 8;
const INPUT_HEIGHT: u16        = 3;

/// APRS data type ids that count as conversations
const CONVERSATIONAL_DATA_TYPES: &[char] = &[':'];

#[derive(Debug)]
pub enum AppMode {
    Monitor,
    Net,
    Qso { mycall: String, addressee: String },
}

impl AppMode {
    /// Notices are always shown no matter the app mode.
    pub fn shows(&self, item: &LogItem) -> bool {
        match item {
            LogItem::Notice { .. } => true,
            LogItem::Frame { item, .. } => self.shows_frame(item),
        }
    }

    fn shows_frame(&self, frame: &FrameLogItem) -> bool {
        let conversational = CONVERSATIONAL_DATA_TYPES.contains(&frame.data_type_id);
        match self {
            Self::Monitor => true,
            Self::Net => conversational,
            Self::Qso { mycall, addressee } => conversational && frame.between(mycall, addressee),
        }
    }
}

#[derive(Clone,Debug)]
pub struct Contact {
    station: String,
    last_comm: Instant,
}

impl Contact {
    pub fn new(station: String) -> Contact {
        Contact {
            station,
            last_comm: Instant::now(),
        }
    }
}

#[derive(Clone,Debug)]
pub struct ContactBook {
    contacts: Vec<Contact>,
}

impl ContactBook {
    pub fn new() -> ContactBook {
        Self {
            contacts: Vec::new(),
        }
    }

    fn add_or_update_contact(&mut self, station: String) {
        if let Some(s) = self.contacts.iter_mut().find(|s| s.station == station) {
            s.last_comm = Instant::now();
        }
        else {
            let contact = Contact::new(station.to_uppercase());
            self.contacts.push(contact);
        }
    }

    pub fn matching(&self, match_str: &str) -> Vec<Contact> {
        let match_str = match_str.to_uppercase();

        let mut matching_contacts: Vec<Contact> = self.contacts
            .iter()
            .filter(|c| c.station.starts_with(&match_str))
            .cloned()
            .collect();

        matching_contacts.sort_by(|a, b| b.last_comm.cmp(&a.last_comm));
        matching_contacts
    }
}

#[derive(Debug)]
pub struct MainUi {
    message_sender: mpsc::Sender<Message>,
    terminal_input: LineInput,
    terminal_output: MultiLineOutput,
    mycall: String,
    app_mode: AppMode,
    log: Log,
    contact_book: ContactBook,
    typing_slash: bool,
    matching_slashes: Vec<&'static SlashCommand>,
    selected_slash: usize,
    slash_command_popup_state: ListState,
    typing_contact: bool,
    matching_contacts: Vec<Contact>,
    selected_contact: usize,
    contact_command_popup_state: ListState,
}

impl MainUi {
    pub const MIN_SIZE: Size = Size {
        width: OUTPUT_AREA_WIDTH,
        height: INPUT_HEIGHT + MAX_AUTOCOMP_HEIGHT + 3,
    };

    pub fn new(message_sender: mpsc::Sender<Message>) -> Self {
        let li_message_sender = message_sender.clone();
        let terminal_input = LineInput::new(
            MAX_INPUT_LEN,
            MAX_INPUT_LEN,
            li_message_sender,
        );

        Self {
            app_mode: AppMode::Net,
            terminal_input,
            terminal_output: MultiLineOutput::new(),
            log: Log::new(),
            contact_book: ContactBook::new(),
            mycall: String::new(),
            message_sender,
            typing_slash: false,
            matching_slashes: Vec::new(),
            selected_slash: 0,
            slash_command_popup_state: ListState::default()
                .with_selected(Some(0)),
            typing_contact: false,
            matching_contacts: Vec::new(),
            selected_contact: 0,
            contact_command_popup_state: ListState::default()
                .with_selected(Some(0)),
        }
    }

    /// Renders the '/' or '@' popup if needed.
    fn maybe_render_autocomp_popup(&mut self, frame: &mut Frame, inputx: u16, inputy: u16) {
        let (color, num_items) = if self.typing_slash {
            (Color::Green, self.matching_slashes.len().try_into().unwrap())
        } else if self.typing_contact {
            (Color::Yellow, self.matching_contacts.len().try_into().unwrap())
        } else {
            (Color::Red, 0 as u16)
        };

        if num_items == 0 { return }

        let popup_height: u16 = min(num_items, MAX_AUTOCOMP_HEIGHT);
        let mut popupy = inputy - (popup_height + 1);

        // if we have too many items in the popup, render a ...
        if popup_height < num_items {
            let num_hidden = num_items - popup_height;
            let ellipsis_str = format!("  ...{} more", num_hidden);

            popupy -= 1;
            let area = Rect {
                x: inputx,
                y: inputy - 2,
                width: OUTPUT_AREA_WIDTH - 3,
                height: 1
            };

            let ellipsis = Paragraph::new(ellipsis_str);
            frame.render_widget(ellipsis, area);
        }

        let output_width_u16: u16 = OUTPUT_AREA_WIDTH - 3; // minus border and scroll
        let output_width_usize: usize = output_width_u16 as usize;

        let divider_area = Rect {
            x: inputx,
            y: popupy.saturating_sub(1),
            width: output_width_u16,
            height: 1,
        };

        let divider = Paragraph::new("=".repeat(output_width_usize.into()))
            .style(color)
            .alignment(Alignment::Left);

        frame.render_widget(divider, divider_area);

        let area = Rect {
            x: inputx,
            y: popupy,
            width: output_width_u16,
            height: popup_height,
        };
        frame.render_widget(Clear, area);

        if self.typing_slash {
            let usage_width = SlashCommand::max_usage_width();
            let items: Vec<ListItem> = self.matching_slashes
                .iter()
                .map(|cmd| ListItem::new(format!("{:<usage_width$}  {}", cmd.usage(), cmd.friendly)))
                .collect();

            let list = List::new(items)
                .style(color)
                .highlight_style(Modifier::REVERSED)
                .highlight_symbol("> ");

            self.slash_command_popup_state.select(Some(self.selected_slash));
            frame.render_stateful_widget(list, area, &mut self.slash_command_popup_state);
        }

        if self.typing_contact {
            let items: Vec<ListItem> = self.matching_contacts
                .iter()
                .map(|m| ListItem::new(m.station.clone()))
                .collect();

            let list = List::new(items)
                .style(color)
                .highlight_style(Modifier::REVERSED)
                .highlight_symbol("> ");

            self.contact_command_popup_state.select(Some(self.selected_contact));
            frame.render_stateful_widget(list, area, &mut self.contact_command_popup_state);
        }
    }

    pub fn render(&mut self, frame: &mut Frame) {
        let window_layout = Layout::default()
            .direction(Direction::Horizontal)
            .spacing(Spacing::Overlap(1))
            .constraints(vec![
                Constraint::Fill(1),
                Constraint::Length(Self::MIN_SIZE.width),
                Constraint::Fill(1),
            ])
            .split(frame.area());

        // layout for  the output and input area of the main app
        let terminal_layout = Layout::default()
            .direction(Direction::Vertical)
            .spacing(Spacing::Overlap(1))
            .constraints(vec![
                Constraint::Fill(1),   // output
                Constraint::Length(3), // input plus top/bottom border
            ])
            .split(window_layout[1]);

        let terminal_output_block = Block::bordered()
            .style(Style::default())
            .title(" kisstty ")
            .title_style(Style::default().add_modifier(Modifier::REVERSED))
            .title_alignment(Alignment::Center)
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .merge_borders(MergeStrategy::Fuzzy);

        frame.render_widget(&terminal_output_block, terminal_layout[0]);

        let terminal_output_block_inner_area = terminal_output_block
            .inner(terminal_layout[0]);

        frame.render_widget(
            LogView::new(&self.log, &self.terminal_output, &self.app_mode),
            terminal_output_block_inner_area,
        );

        let addressee_rx;
        let addressee_tx;

        let (mode, rx, tx) = match &self.app_mode {
            AppMode::Monitor => ("MODE: monitor", "all data types", AprsMessage::BROADCAST_ADDRESSEE),
            AppMode::Net => ("MODE: net", "all messages", AprsMessage::BROADCAST_ADDRESSEE),
            AppMode::Qso { addressee, .. } => {
                addressee_rx = format!("from {}", addressee);
                addressee_tx = format!("to {}", addressee);
                ("MODE: qso", addressee_rx.as_str(), addressee_tx.as_str())
            }
        };

        let app_mode_text = format!("{} | RX: {} | TX: {}", mode, rx, tx);

        let terminal_input_block = Block::bordered()
            .title(format!(" {} ", app_mode_text))
            .title_style(Style::default().add_modifier(Modifier::REVERSED))
            .title_alignment(Alignment::Center)
            .style(Style::default())
            .border_type(BorderType::Rounded)
            .merge_borders(MergeStrategy::Fuzzy);

        frame.render_widget(&terminal_input_block, terminal_layout[1]);

        let terminal_input_block_inner_area = terminal_input_block
            .inner(terminal_layout[1]);

        let terminal_input_layout = Layout::default()
            .direction(Direction::Horizontal)
            .spacing(Spacing::Overlap(1))
            .constraints(vec![
                Constraint::Length(3),                     // prompt
                Constraint::Length(MAX_INPUT_LEN as u16 + 1), // input field (+1 spacer the divider overlaps)
                Constraint::Fill(1),                       // divider + char counter
            ])
            .split(terminal_input_block_inner_area);

        let terminal_input_prompt = Paragraph::new(format!("> "))
            .style(Style::default())
            .alignment(Alignment::Left);

        frame.render_widget(terminal_input_prompt, terminal_input_layout[0]);
        frame.render_widget(&self.terminal_input, terminal_input_layout[1]);

        let char_counter = Paragraph::new(format!(
            "│ {}/{}",
            self.terminal_input.data.len(),
            MAX_INPUT_LEN,
        ))
            .style(Style::default().fg(Color::DarkGray))
            .alignment(Alignment::Left);

        frame.render_widget(char_counter, terminal_input_layout[2]);

        let terminal_input_area = terminal_input_layout[1];
        let cursor_pos = Position{
            x: terminal_input_area.x + self.terminal_input.screen_cursor as u16,
            y: terminal_input_area.y,
        };
        frame.set_cursor_position(cursor_pos);

        self.maybe_render_autocomp_popup(
            frame, 
            terminal_input_block_inner_area.x,
            terminal_input_block_inner_area.y,
        );

    }

    pub fn tick(&mut self) {
//        let new_line = format!("message #{}", self.counter);
//        self.terminal_output.add_line(&new_line);
//        self.counter += 1;
    }

    pub fn configure(&mut self, config: &Config) {
        self.mycall = config.callsign.clone();
    }

    /// Switches modes and jumps to the newest traffic.
    fn set_app_mode(&mut self, app_mode: AppMode) {
        self.app_mode = app_mode;
        self.terminal_output.scroll_to_bottom();
    }

    fn update_contacts(&mut self, log_item: &LogItem) {
        if let LogItem::Frame {item,..} = log_item {
            if let Some(station) = item.get_contact_station(&self.mycall) {
                self.contact_book.add_or_update_contact(station);
            }
        }
    }

    pub fn try_claim(&mut self, message: Message) -> Option<Message> {
        match message {
            Message::LogPublish(item) => {
                self.update_contacts(&item);
                self.log.push(item);
                None
            },
            Message::LogUpdate(item) => {
                self.update_contacts(&item);
                self.log.replace(item);
                None
            },
            other => Some(other),
        }
    }

    pub fn try_claim_while_active(&mut self, message: Message) -> Option<Message> {
        match message {
            Message::UserKey(key_event) => self.handle_key(key_event),
            Message::Help => {
                self.print_help();
                None
            },
            Message::Monitor => {
                self.set_app_mode(AppMode::Monitor);
                None
            }
            Message::Net => {
                self.set_app_mode(AppMode::Net);
                None
            }
            Message::Qso(addressee) => {
                let mycall = self.mycall.clone();
                self.set_app_mode(AppMode::Qso { mycall, addressee });
                None
            }
            Message::Clear => {
                self.log.clear();
                self.terminal_output.scroll_to_bottom();
                None
            }
            other => self.terminal_input.try_claim(other),
        }
    }


    pub fn handle_key(&mut self, key_event: KeyEvent) -> Option<Message> {
        match key_event.code {
            KeyCode::Up if key_event.modifiers == KeyModifiers::CONTROL => {
                self.terminal_output.scroll_up();
            }
            KeyCode::Down if key_event.modifiers == KeyModifiers::CONTROL => {
                self.terminal_output.scroll_down();
            }
            KeyCode::Up => { self.handle_up(); },
            KeyCode::Down => { self.handle_down(); },
            KeyCode::Home if key_event.modifiers == KeyModifiers::CONTROL => self.terminal_output.scroll_to_top(),
            KeyCode::End if key_event.modifiers == KeyModifiers::CONTROL => self.terminal_output.scroll_to_bottom(),
            KeyCode::Tab => { self.handle_tab(); }
            KeyCode::Esc => self.terminal_output.toggle_view_mode(),
            KeyCode::Enter => self.handle_enter(),
            KeyCode::Char('c') | KeyCode::Char('C') if key_event.modifiers == KeyModifiers::CONTROL => {
                self.clear_input();
            }
            _ => {
                let handled = self.terminal_input.handle_key(key_event);
                if handled.is_none() {
                    self.update_popup_state();
                }
                return handled;
            }
        }
        None
    }

    /// Called whenever the user types something and our
    /// popup state might be invalidated
    fn update_popup_state(&mut self) {
        self.typing_slash = self.terminal_input.is_typing_command(b'/');
        if self.typing_slash {
            self.matching_slashes = SlashCommand::matching(&self.terminal_input.data);
            self.selected_slash = 0;
            return;
        }

        self.typing_contact = self.terminal_input.is_typing_command(b'@');
        if self.typing_contact {
            let match_str = &self.terminal_input.data[1..].trim().to_uppercase();
            self.matching_contacts = self.contact_book.matching(match_str);
            self.selected_contact = 0;
            return;
        }
    }

    fn tab_complete_slash(&mut self) {
        if self.matching_slashes.len() == 0 { return }
        let cmd = self.matching_slashes[self.selected_slash];

        let completed = format!("{} ", cmd.slash);
        self.terminal_input.replace_data(&completed);
        self.update_popup_state();
    }

    fn tab_complete_contact(&mut self) {
        if self.matching_contacts.len() == 0 { return }
        let contact = &self.matching_contacts[self.selected_contact];

        let completed = format!("@{} ", contact.station);
        self.terminal_input.replace_data(&completed);
        self.update_popup_state();
    }

    fn handle_up(&mut self) -> bool {
        if self.typing_slash {
            self.selected_slash = self.selected_slash.saturating_sub(1);
            return true;
        } else if self.typing_contact {
            self.selected_contact = self.selected_contact.saturating_sub(1);
            return true;
        }
        false
    }

    fn handle_down(&mut self) -> bool {
        if self.typing_slash {
            let len = self.matching_slashes.len();
            self.selected_slash = min(self.selected_slash+1, len-1);
            return true;
        } else if self.typing_contact {
            let len = self.matching_contacts.len();
            self.selected_contact = min(self.selected_contact+1, len-1);
            return true;
        }
        false
    }

    fn handle_tab(&mut self) -> bool {
        if self.terminal_input.is_typing_command(b'/') {
            self.tab_complete_slash();
            return true;
        } else if self.terminal_input.is_typing_command(b'@') {
            self.tab_complete_contact();
            return true;
        }
        false
    }

    fn handle_slash_command(&mut self, command_name: &str, args: Vec<&str>) {
        if let Some(slash) = SlashCommand::find(command_name) {
            match (slash.to_message)(&args) {
                Some(message) => {
                    let _ = self.message_sender.send(message);
                    self.clear_input();
                }
                None => {
                    self.log.push(LogItem::notice(vec![
                        format!("usage: {}", slash.usage()),
                        String::new(),
                    ]));
                }
            }
        } else {
            self.print_help();
        }
    }

    fn handle_send_message_command(&mut self, addressee: &str, text: &str) {
        let addr = match Ax25Addr::parse(addressee) {
            Ok(addr) => addr,
            Err(_) => {
                self.log.push(LogItem::notice(vec![
                    format!("Invalid callsign: '{}'", addressee),
                    String::new(),
                ]));
                return
            }
        };

        // TODO: Validate: < 67 chars.
        // Update: char count (not here, but on typing).
        self.send_message(addr.to_string(), text.to_string());
        self.clear_input();
    }

    fn handle_enter(&mut self) {
        if self.handle_tab() { return }

        let input = self.terminal_input.data.clone();
        if input.len() == 0 { return }

        let mut parts = input.trim().splitn(2, char::is_whitespace);
        let arg0 = parts.next().unwrap_or("");
        let rest = parts.next().unwrap_or("").trim_start();

        if arg0.is_empty() { return }

        if arg0.starts_with("/") {
            let args: Vec<&str> = rest.split_whitespace().collect();
            self.handle_slash_command(arg0, args);
        } else if arg0.starts_with("@") {
            if rest.is_empty() { return }
            let addressee = &arg0[1..];
            self.handle_send_message_command(addressee, rest);
        }

    }

    fn clear_input(&mut self) {
        self.terminal_input.replace_data("");
    }

    fn print_help(&mut self) {
        let usage_width = SlashCommand::max_usage_width();

        let mut lines = vec![String::from("Available commands:")];
        for cmd in SLASH_COMMANDS {
            lines.push(format!(
                "  {:<usage_width$}  {}",
                cmd.usage(),
                cmd.friendly,
            ));
        }
        lines.push(String::new());
        self.log.push(LogItem::notice(lines));
    }

    fn send_message(&mut self, addressee: String, text: String) {
        let _ = self.message_sender.send(Message::SendAprsMessage { addressee, text });
    }

}

#[cfg(test)]
mod tests {
    use super::*;

    use std::time::UNIX_EPOCH;

    use crate::log::{next_log_id, FrameLogItem};

    const MYCALL: &str = "NOCALL";

    fn frame(source: &str, addressee: Option<&str>, data_type_id: char) -> LogItem {
        LogItem::frame(next_log_id(), FrameLogItem {
            seq: 0,
            at: UNIX_EPOCH,
            source: source.to_string(),
            dest: String::from("APKTY1"),
            addressee: addressee.map(|a| a.to_string()),
            msg_id: None,
            data_type_id,
            body: String::from("hello"),
            digipeaters: String::new(),
            ackable: false,
            acked: false,
            repeats: 0,
        })
    }

    fn message(source: &str, addressee: &str) -> LogItem {
        frame(source, Some(addressee), ':')
    }

    fn status(source: &str) -> LogItem {
        frame(source, None, '>')
    }

    #[test]
    fn monitor_shows_every_data_type() {
        let mode = AppMode::Monitor;

        assert!(mode.shows(&message("NOCALL-1", "NOCALL-2")));
        assert!(mode.shows(&status("NOCALL-1")));
    }

    #[test]
    fn net_shows_messages_between_any_addressees() {
        let mode = AppMode::Net;

        assert!(mode.shows(&message("NOCALL-1", "NOCALL-2")));
        assert!(!mode.shows(&status("NOCALL-1")));
    }

    fn qso(addressee: &str) -> AppMode {
        AppMode::Qso {
            mycall: String::from(MYCALL),
            addressee: String::from(addressee),
        }
    }

    #[test]
    fn qso_shows_messages_in_both_directions_between_the_pair() {
        let mode = qso("NOCALL-1");

        assert!(mode.shows(&message(MYCALL, "NOCALL-1")));
        assert!(mode.shows(&message("NOCALL-1", MYCALL)));
    }

    #[test]
    fn qso_hides_the_other_addressees_messages_with_anyone_else() {
        let mode = qso("NOCALL-1");

        assert!(!mode.shows(&message("NOCALL-1", "NOCALL-2")));
        assert!(!mode.shows(&message("NOCALL-2", "NOCALL-1")));
    }

    #[test]
    fn qso_hides_our_messages_with_anyone_else() {
        let mode = qso("NOCALL-1");

        assert!(!mode.shows(&message(MYCALL, "NOCALL-2")));
        assert!(!mode.shows(&message("NOCALL-2", MYCALL)));
    }

    #[test]
    fn qso_hides_traffic_between_two_other_addressees() {
        assert!(!qso("NOCALL-1").shows(&message("NOCALL-2", "NOCALL-3")));
    }

    #[test]
    fn qso_matches_an_addressee_typed_in_lower_case() {
        let mode = qso("nocall-1");

        assert!(mode.shows(&message("NOCALL-1", MYCALL)));
    }

    #[test]
    fn qso_hides_non_message_traffic_from_the_other_addressee() {
        assert!(!qso("NOCALL-1").shows(&status("NOCALL-1")));
    }

    #[test]
    fn every_mode_shows_notices() {
        let notice = LogItem::notice(vec![String::from("usage: /qso CALLSIGN")]);

        assert!(AppMode::Monitor.shows(&notice));
        assert!(AppMode::Net.shows(&notice));
        assert!(qso("NOCALL-1").shows(&notice));
    }
}
