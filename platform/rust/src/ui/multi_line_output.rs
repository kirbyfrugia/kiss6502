//! The main output pane for the terminal.
//!

use std::cell::Cell;

use ratatui::{
    buffer::Buffer,
    layout::Rect,
    text::Line,
    widgets::{
        Scrollbar, ScrollbarOrientation, ScrollbarState, StatefulWidget, Widget,
    },
};

use crate::{
    log::{Log, LogItem},
    ui::DisplayMode,
};

#[derive(Debug)]
enum ViewMode {
    Follow,
    Paused(usize),
}

#[derive(Debug)]
pub struct MultiLineOutput {
    view_mode: ViewMode,
    max_scroll: Cell<usize>,
}

/// The log and the viewport used for a render.
/// Recreated each render.
pub struct LogView<'a> {
    log: &'a Log,
    output: &'a MultiLineOutput,
    display_mode: &'a DisplayMode,
}

impl<'a> LogView<'a> {
    pub fn new(log: &'a Log, output: &'a MultiLineOutput, display_mode: &'a DisplayMode) -> Self {
        Self { log, output, display_mode }
    }

    /// The items shown based on the current mode admits, oldest first.
    fn visible(&self) -> impl Iterator<Item = &LogItem> {
        self.log.iter().filter(|item| self.display_mode.shows(item))
    }

    fn total_lines(&self) -> usize {
        self.visible().map(|item| item.line_count()).sum()
    }
}

impl Widget for LogView<'_> {
    fn render(self, area: Rect, buf: &mut Buffer) {
        let max_lines = area.height as usize;
        let total_lines = self.total_lines();

        let text_area = Rect { width: area.width.saturating_sub(1), ..area };

        let max_scroll = total_lines.saturating_sub(max_lines);
        self.output.max_scroll.set(max_scroll);

        let top = match self.output.view_mode {
            ViewMode::Follow => max_scroll,
            ViewMode::Paused(top) => top.min(max_scroll),
        };

        // count past everything above the window and only render
        // what lands inside it
        let mut consumed = 0 as usize;
        let mut y = 0 as usize;

        'items: for item in self.visible() {
            let count = item.line_count();

            if consumed + count <= top {
                consumed += count;
                continue;
            }

            let skip = top.saturating_sub(consumed);
            for line in item.lines().into_iter().skip(skip) {
                if y == max_lines {
                    break 'items;
                }
                buf.set_line(
                    text_area.x,
                    text_area.y + y as u16,
                    &Line::from(line.as_str()),
                    text_area.width,
                );
                y += 1;
            }

            consumed += count;
        }

        if total_lines > max_lines {
            let scrollbar = Scrollbar::default()
                .orientation(ScrollbarOrientation::VerticalRight);

            let mut scrollbar_state = ScrollbarState::new(max_scroll + 1)
                .viewport_content_length(max_lines)
                .position(top);

            scrollbar.render(area, buf, &mut scrollbar_state);
        }
    }
}

impl MultiLineOutput {
    pub fn new() -> Self {
        Self {
            view_mode: ViewMode::Follow,
            max_scroll: Cell::new(0),
        }
    }

    pub fn toggle_view_mode(&mut self) {
        self.view_mode = match self.view_mode {
            ViewMode::Follow => {
                let top = self.max_scroll.get();
                ViewMode::Paused(top)
            },
            ViewMode::Paused(_) => ViewMode::Follow
        }
    }

    pub fn scroll_up(&mut self) {
        let top = match self.view_mode {
            ViewMode::Follow => self.max_scroll.get(),
            ViewMode::Paused(top) => top,
        };
        self.view_mode = ViewMode::Paused(top.saturating_sub(1));
    }

    pub fn scroll_down(&mut self) {
        let ViewMode::Paused(top) = self.view_mode else { return };
        if top + 1 >= self.max_scroll.get() {
            self.view_mode = ViewMode::Follow;
        } else {
            self.view_mode = ViewMode::Paused(top + 1);
        }
    }

    pub fn scroll_to_top(&mut self) {
        self.view_mode = ViewMode::Paused(0);
    }

    pub fn scroll_to_bottom(&mut self) {
        self.view_mode = ViewMode::Follow;
    }
}
