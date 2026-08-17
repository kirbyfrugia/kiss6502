use std::{ cmp, sync::mpsc };

use ratatui::{
    buffer::Buffer,
    crossterm::event::{KeyCode, KeyEvent},
    layout::Rect,
    style::Style,
    widgets::Widget,
};

use crate::message::Message;

#[derive(Debug)]
pub struct LineInput {
    _message_sender:     mpsc::Sender<Message>,
    pub screen_cursor:  usize,
    pub data:           String,
    data_cursor:        usize,
    max_data_len:       usize,
    max_screen_len:     usize,
    data_first_visible: usize,
    data_last_visible:  usize,
}

impl Widget for &LineInput {
    fn render(self, area: Rect, buf: &mut Buffer) {
        buf.set_string(
            area.left(),
            area.top(),
            &self.data[self.data_first_visible..self.data_last_visible],
            Style::default()
        );
    }
}

impl LineInput {
    pub fn new(max_data_len: usize, max_screen_len: usize, message_sender: mpsc::Sender<Message>) -> Self {
        Self {
            max_data_len,
            max_screen_len,
            _message_sender: message_sender,
            data_cursor: 0,
            screen_cursor: 0,
            data_first_visible: 0,
            data_last_visible: 0,
            data: String::new(),
        }
    }

    pub fn set_max_len(&mut self, max_data_len: usize, max_screen_len: usize) {
        self.max_data_len = max_data_len;
        self.max_screen_len = max_screen_len;
    }

    pub fn set_max_data_len(&mut self, max_data_len: usize) {
        self.max_data_len = max_data_len;
    }

    fn update_screen_vars(&mut self) {
        // if the data cursor is off the screen to the left,
        // bring it back on screen.
        if self.data_first_visible > self.data_cursor {
            self.data_first_visible = self.data_cursor;
        }

        // if the data cursor is off the screen to the right,
        // bring it back on screen
        if self.data_cursor - self.data_first_visible >= self.max_screen_len {
            self.data_first_visible = self.data_cursor - self.max_screen_len;
        }

        // now let's set the screen cursor to the position of the data cursor
        self.screen_cursor = self.data_cursor - self.data_first_visible;

        self.data_last_visible = cmp::min(
            self.max_screen_len,
            self.data.len() - self.data_first_visible
        ) + self.data_first_visible;

    }

    pub fn move_cursor_left(&mut self) {
        if self.data_cursor == 0 { return }

        self.data_cursor -= 1;
        self.update_screen_vars();

    }

    pub fn move_cursor_right(&mut self) {
        if self.data_cursor == self.data.len() { return }

        self.data_cursor += 1;
        self.update_screen_vars();
    }

    pub fn insert_char(&mut self, c: char) {
        if !(c.is_ascii_graphic() || c == ' ') { return }
        if self.data.len() >= self.max_data_len { return }

        self.data.insert(self.data_cursor.into(), c);
        self.move_cursor_right();
    }

    pub fn delete_char(&mut self) {
        if self.data.len() == 0 { return }
        if self.data_cursor >= self.data.len() { return }
        self.data.remove(self.data_cursor.into());
        self.update_screen_vars();
    }

    pub fn backspace(&mut self) {
        if self.data_cursor == 0 { return }
        self.move_cursor_left();
        self.delete_char();
        self.update_screen_vars();
    }

    pub fn replace_data(&mut self, data: &str) {
        if data.len() > self.max_data_len {
            self.data = data[0..self.max_data_len].to_string();
        } else {
            self.data = data.to_string();
        }

        self.data_cursor = self.data.len();
        self.update_screen_vars();
    }

    pub fn is_typing_command(&mut self, command_byte: u8) -> bool {
        if self.data_cursor == 0 { return false }

        let data_bytes = self.data.as_bytes();
        let first_byte = data_bytes[0];
        if first_byte != command_byte { return false }

        for &this_char in data_bytes {
            match this_char {
                b' ' => return false,
                _ => {}
            }
        }
        return true

    }

    pub fn handle_key(&mut self, key: KeyEvent) -> Option<Message> {
        match key.code {
            KeyCode::Left      => self.move_cursor_left(),
            KeyCode::Right     => self.move_cursor_right(),
            KeyCode::Backspace => self.backspace(),
            KeyCode::Delete    => self.delete_char(),
            KeyCode::Char(c)   => self.insert_char(c),
            _ => return Some(Message::UserKey(key)),
        }
        None
    }

    pub fn try_claim(&mut self, message: Message) -> Option<Message> {
        Some(message)
    }

}
