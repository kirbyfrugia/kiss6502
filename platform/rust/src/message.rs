use ratatui::crossterm::event::KeyEvent;

use crate::{
    kiss::Ax25Frame,
    log::LogItem,
};

#[derive(Debug)]
pub enum Message {
    Tick,
    UserKey(KeyEvent),
    ConfigSaved,
    ConfigCanceled,
    Ax25FrameReceived(Ax25Frame),
    SendAprsMessage { addressee: String, text: String },
    Clear,
    Config,
    Dump(u64),
    Exit,
    Help,
    DisplayAprsAll,
    DisplayAprsMessages,
    Forget(String),
    Quit,
    LogPublish(LogItem),
    LogUpdate(LogItem),
}
