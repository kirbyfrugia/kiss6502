use std::{ cmp, sync::mpsc };

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
    kiss::AprsMessage,
    log::{FrameLogItem, Log, LogItem},
    ui::{LineInput,LogView,MultiLineOutput},
    message::Message,
    slash::{SlashCommand, SLASH_COMMANDS},
};

const MAX_INPUT_LEN: usize             = 67;
const OUTPUT_AREA_WIDTH: u16           = TERMINAL_WIDTH + 4;
const MAX_SLASH_POPUP_HEIGHT: u16      = 8;
const INPUT_HEIGHT: u16                = 3;

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

#[derive(Debug)]
pub struct MainUi {
    terminal_input: LineInput,
    terminal_output: MultiLineOutput,
    log: Log,
    mycall: String,
    message_sender: mpsc::Sender<Message>,
    command_popup_list_state: ListState,
    app_mode: AppMode,
}

impl MainUi {
    pub const MIN_SIZE: Size = Size {
        width: OUTPUT_AREA_WIDTH,
        height: INPUT_HEIGHT + MAX_SLASH_POPUP_HEIGHT + 3,
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
            mycall: String::new(),
            message_sender,
            command_popup_list_state: ListState::default()
                .with_selected(Some(0)),
        }
    }

    fn render_command_popup(&mut self, frame: &mut Frame, inputx: u16, inputy: u16) {
        let matching = SlashCommand::matching(&self.terminal_input.data);

        let num_matching: u16 = matching.len().try_into().unwrap();

        if num_matching == 0 { return }

        let popup_height: u16 = cmp::min(num_matching, MAX_SLASH_POPUP_HEIGHT);
        let mut popupy = inputy - (popup_height + 1);

        // if we have too many items in the popup, render a ...
        if popup_height < num_matching {
            let num_hidden = num_matching - popup_height;
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

        let area = Rect {
            x: inputx,
            y: popupy,
            width: OUTPUT_AREA_WIDTH - 3, // minus border and scroll
            height: popup_height,
        };
        frame.render_widget(Clear, area);

        let usage_width = SlashCommand::max_usage_width();

        let items: Vec<ListItem> = matching
            .iter()
            .map(|cmd| ListItem::new(format!("{:<usage_width$}  {}", cmd.usage(), cmd.friendly)))
            .collect();

        let list = List::new(items)
            .style(Color::White)
            .highlight_style(Modifier::REVERSED)
            .highlight_symbol("> ");

        frame.render_stateful_widget(list, area, &mut self.command_popup_list_state);

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

        let in_slash = self.terminal_input.is_typing_slash_command();

        if in_slash {
            self.render_command_popup(
                frame, 
                terminal_input_block_inner_area.x,
                terminal_input_block_inner_area.y,
            );
        }

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

    pub fn try_claim(&mut self, message: Message) -> Option<Message> {
        match message {
            Message::LogPublish(item) => {
                self.log.push(item);
                None
            }
            Message::LogUpdate(item) => {
                self.log.replace(item);
                None
            }
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
            KeyCode::Up => self.terminal_output.scroll_up(),
            KeyCode::Down => self.terminal_output.scroll_down(),
            KeyCode::Home if key_event.modifiers == KeyModifiers::CONTROL => self.terminal_output.scroll_to_top(),
            KeyCode::End if key_event.modifiers == KeyModifiers::CONTROL => self.terminal_output.scroll_to_bottom(),
            KeyCode::Tab => { self.handle_tab(); }
            KeyCode::Esc => self.terminal_output.toggle_view_mode(),
            KeyCode::Enter => self.handle_enter(),
            KeyCode::Char('c') | KeyCode::Char('C') if key_event.modifiers == KeyModifiers::CONTROL => {
                self.clear_input();
            }
            _ => return self.terminal_input.handle_key(key_event),
        }
        None
    }

    fn tab_complete(&mut self) {
        let matched = SlashCommand::matching(&self.terminal_input.data);

        if matched.len() == 0 { return }

        let cmd = matched.first().expect("wtf");
        let completed = format!("{} ", cmd.slash);
        self.terminal_input.replace_data(&completed);
    }

    fn handle_tab(&mut self) -> bool {
        if self.terminal_input.is_typing_slash_command() {
            self.tab_complete();
            return true;
        }
        false
    }

    fn handle_enter(&mut self) {
        if self.handle_tab() { return }

        let input = self.terminal_input.data.clone();
        if input.len() == 0 { return }
        let mut parts = input.split_whitespace();
        let name = parts.next().unwrap_or("");
        let args: Vec<&str> = parts.collect();

        if let Some(slash) = SlashCommand::find(name) {
            match (slash.to_message)(&args) {
                Some(message) => {
                    self.tab_complete();
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
        }
        else {
            if name.starts_with("/") {
                self.print_help();
                return
            }
            self.send_message(input);
            self.clear_input();
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

    fn send_message(&mut self, text: String) {
        let addressee = match &self.app_mode {
            AppMode::Qso { addressee, .. } => addressee.to_string(),
            _ => AprsMessage::BROADCAST_ADDRESSEE.to_string(),
        };

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
