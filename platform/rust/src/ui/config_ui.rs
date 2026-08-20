use std::sync::mpsc;

use ratatui::{
    crossterm::event::{KeyCode, KeyEvent},
    layout::{Alignment, Constraint, Direction, Layout, Position, Rect, Size},
    style::{Color, Modifier, Style},
    widgets::{Block, BorderType, Borders, Paragraph},
    Frame,
};

use crate::{
    config::{self, Config},
    message::Message,
    ui::LineInput,
};

#[derive(Debug, Clone, Copy, PartialEq)]
enum Button {
    Cancel,
    Save,
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum Focus {
    Field(usize),
    Button(Button),
}

fn button_label(label: &str) -> String {
    format!("[ {} ]", label)
}

#[derive(Debug, Clone, Copy, PartialEq)]
enum FieldKey {
    Station,
    KissHost,
    KissPort,
    Digipeaters,
}

fn validate_field(key: FieldKey, value: &str) -> Result<(), String> {
    let value = value.trim();
    match key {
        FieldKey::Station => return config::validate_station(value),
        FieldKey::Digipeaters => return config::validate_digipeaters(value),
        FieldKey::KissHost => return config::validate_host(value),
        FieldKey::KissPort => match value.parse::<u16>() {
            Ok(port) => return config::validate_port(port),
            Err(_) => return Err("port must be a number from 1-65535".into()),
        },
    }
}

#[derive(Debug)]
struct ConfigField {
    key: FieldKey,
    name: String,
    input: LineInput,
    error: Option<String>,
}
impl ConfigField {
    pub fn new(key: FieldKey, name: String, input: LineInput) -> Self {
        Self {
            key,
            name,
            input,
            error: None,
        }
    }
}

#[derive(Debug)]
pub struct ConfigUi {
    message_sender: mpsc::Sender<Message>,
    focus: Focus,
    config_fields: Vec<ConfigField>,
    fields_width: u16,
    inputs_width: u16,
}

impl ConfigUi {
    pub const MIN_SIZE: Size = Size { width: 40, height: 10 };

    pub fn new(message_sender: mpsc::Sender<Message>) -> Self {
        let input_len: usize = 40;
        let station_input = LineInput::new(9, input_len, message_sender.clone());
        let digipeaters_input = LineInput::new(80, input_len, message_sender.clone());
        let kiss_host_input = LineInput::new(config::MAX_HOST_LEN, input_len, message_sender.clone());
        let kiss_port_input = LineInput::new(5, input_len, message_sender.clone());

        let config_fields = vec![
            ConfigField::new(FieldKey::Station, String::from("Station:"), station_input),
            ConfigField::new(FieldKey::Digipeaters, String::from("Digipeaters:"), digipeaters_input),
            ConfigField::new(FieldKey::KissHost, String::from("KISS host:"), kiss_host_input),
            ConfigField::new(FieldKey::KissPort, String::from("KISS port:"), kiss_port_input),
        ];

        let fields_width: u16 = config_fields
            .iter()
            .map(|field| field.name.len())
            .max()
            .unwrap_or(1).try_into().unwrap();

        Self {
            message_sender,
            config_fields,
            fields_width,
            inputs_width: input_len.try_into().unwrap(),
            focus: Focus::Field(0),
        }
    }

    pub fn load_config(&mut self, config: &Config) {
        for field in &mut self.config_fields {
            let value = match field.key {
                FieldKey::Station => config.station.clone(),
                FieldKey::Digipeaters => config.digipeaters.join(", "),
                FieldKey::KissHost => config.kiss_host.clone(),
                FieldKey::KissPort => config.kiss_port.to_string(),
            };
            field.input.replace_data(&value);
            field.error = None;
        }
        self.focus = Focus::Field(0);
    }

    pub fn apply_to(&self, config: &mut Config) {
        for field in &self.config_fields {
            let value = field.input.data.trim();
            match field.key {
                FieldKey::Station => config.station = value.to_uppercase(),
                FieldKey::Digipeaters => {
                    config.digipeaters = config::parse_digipeaters(value);
                },
                FieldKey::KissHost => config.kiss_host = value.to_string(),
                FieldKey::KissPort => {
                    config.kiss_port = value.parse::<u16>()
                        .expect("wtf");
                },
            }
        }
    }

    fn render_config_field(&self, frame: &mut Frame, area: Rect, field: &ConfigField, focused: bool) -> Rect {
        let field_layout = Layout::default()
            .direction(Direction::Horizontal)
            .constraints(vec![
                Constraint::Fill(1),
                Constraint::Length(self.fields_width),
                Constraint::Length(1),
                Constraint::Length(self.inputs_width),
                Constraint::Fill(1),
            ])
            .split(area);

        let mut label_style = Style::default();
        if field.error.is_some() {
            label_style = label_style.fg(Color::Red);
        }
        if focused {
            label_style = label_style.add_modifier(Modifier::BOLD);
        }

        let field_name = Paragraph::new(field.name.clone())
            .style(label_style)
            .alignment(Alignment::Left);

        if focused {
            let marker = Paragraph::new("> ").alignment(Alignment::Right);
            frame.render_widget(marker, field_layout[0]);
        }

        frame.render_widget(field_name, field_layout[1]);
        frame.render_widget(&field.input, field_layout[3]);

        field_layout[3]
    }

    pub fn render(&mut self, frame: &mut Frame) {
        let num_fields: usize = self.config_fields.len();
        let outer_layout = Layout::default()
            .direction(Direction::Horizontal)
            .constraints(vec![
                Constraint::Fill(1),
                Constraint::Length(60),
                Constraint::Fill(1),
            ])
            .split(frame.area());

        let outer_block = Block::default()
            .title(" Config ")
            .title_style(Style::default().add_modifier(Modifier::REVERSED))
            .title_alignment(Alignment::Center)
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded);

        frame.render_widget(&outer_block, outer_layout[1]);

        let outer_layout_inner_area = outer_block
            .inner(outer_layout[1]);

        let config_layout = Layout::default()
            .direction(Direction::Vertical)
            .constraints(vec![
                Constraint::Length(num_fields.try_into().unwrap()),
                Constraint::Length(1), // error line
                Constraint::Length(1), // buttons
            ])
            .split(outer_layout_inner_area);

        let field_rows = Layout::default()
            .direction(Direction::Vertical)
            .constraints(vec![Constraint::Length(1); num_fields])
            .split(config_layout[0]);

        let mut focused_input_area: Option<Rect> = None;
        for (i, config_field) in self.config_fields.iter().enumerate() {
            let focused = self.focus == Focus::Field(i);
            let field_input_area = self.render_config_field(frame, field_rows[i], config_field, focused);
            if focused {
                focused_input_area = Some(field_input_area);
            }
        }

        if let (Focus::Field(i), Some(area)) = (self.focus, focused_input_area) {
            let cursor_pos = Position {
                x: area.x + self.config_fields[i].input.screen_cursor as u16,
                y: area.y,
            };
            frame.set_cursor_position(cursor_pos);
        }

        if let Focus::Field(i) = self.focus {
            if let Some(error) = &self.config_fields[i].error {
                let error_widget = Paragraph::new(error.clone())
                    .style(Style::default().fg(Color::Red).add_modifier(Modifier::BOLD))
                    .alignment(Alignment::Center);
                frame.render_widget(error_widget, config_layout[1]);
            }
        }

        let buttons_layout = Layout::default()
            .direction(Direction::Horizontal)
            .constraints(vec![
                Constraint::Fill(1),
                Constraint::Length(button_label("Cancel").len() as u16),
                Constraint::Length(1),
                Constraint::Length(button_label("Save").len() as u16),
                Constraint::Fill(1),
            ])
            .split(config_layout[2]);

        frame.render_widget(self.button("Cancel", Button::Cancel), buttons_layout[1]);
        frame.render_widget(self.button("Save", Button::Save), buttons_layout[3]);
    }

    fn button(&self, label: &str, which_button: Button) -> Paragraph<'static> {
        let style = if self.focus == Focus::Button(which_button) {
            Style::default().add_modifier(Modifier::REVERSED)
        } else {
            Style::default()
        };

        Paragraph::new(button_label(label)).style(style)
    }

    pub fn tick(&mut self) {
    }

    pub fn try_claim_while_active(&mut self, message: Message) -> Option<Message> {
        match message {
            Message::UserKey(key_event) => self.handle_key(key_event),
            other => Some(other),
        }
    }

    fn handle_key(&mut self, key_event: KeyEvent) -> Option<Message> {
        match self.focus {
            Focus::Field(i) => match key_event.code {
                KeyCode::Tab | KeyCode::Down | KeyCode::Enter => self.focus_next(),
                KeyCode::BackTab | KeyCode::Up => self.focus_prev(),
                KeyCode::Esc => self.select(Button::Cancel),
                _ => {
                    let unclaimed = self.config_fields[i].input.handle_key(key_event);
                    if unclaimed.is_none() {
                        self.config_fields[i].error = None;
                    }
                    return unclaimed;
                }
            },
            Focus::Button(button) => match key_event.code {
                KeyCode::Left => self.focus = Focus::Button(Button::Cancel),
                KeyCode::Right => self.focus = Focus::Button(Button::Save),
                KeyCode::Tab | KeyCode::Down => self.focus_next(),
                KeyCode::BackTab | KeyCode::Up => self.focus_prev(),
                KeyCode::Enter | KeyCode::Char(' ') => self.select(button),
                KeyCode::Esc => self.select(Button::Cancel),
                _ => return Some(Message::UserKey(key_event)),
            },
        }
        None
    }

    fn focus_index(&self) -> usize {
        match self.focus {
            Focus::Field(i) => i,
            Focus::Button(Button::Cancel) => self.config_fields.len(),
            Focus::Button(Button::Save) => self.config_fields.len() + 1,
        }
    }

    fn focus_at(&self, index: usize) -> Focus {
        let num_fields = self.config_fields.len();
        if index < num_fields {
            Focus::Field(index)
        } else if index == num_fields {
            Focus::Button(Button::Cancel)
        } else {
            Focus::Button(Button::Save)
        }
    }

    fn focus_next(&mut self) {
        let count = self.config_fields.len() + 2;
        self.focus = self.focus_at((self.focus_index() + 1) % count);
    }

    fn focus_prev(&mut self) {
        let count = self.config_fields.len() + 2;
        self.focus = self.focus_at((self.focus_index() + count - 1) % count);
    }

    fn validate(&mut self) -> bool {
        let mut first_invalid: Option<usize> = None;
        for (i, field) in self.config_fields.iter_mut().enumerate() {
            match validate_field(field.key, &field.input.data) {
                Ok(()) => field.error = None,
                Err(msg) => {
                    field.error = Some(msg);
                    first_invalid.get_or_insert(i);
                }
            }
        }

        match first_invalid {
            Some(i) => {
                self.focus = Focus::Field(i);
                false
            }
            None => true,
        }
    }

    fn select(&mut self, button: Button) {
        let message = match button {
            Button::Save => {
                if !self.validate() {
                    return;
                }
                Message::ConfigSaved
            }
            Button::Cancel => Message::ConfigCanceled,
        };
        let _ = self.message_sender.send(message);
    }
}
