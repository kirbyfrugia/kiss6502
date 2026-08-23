use ratatui::crossterm::event::KeyEvent;

use crate::{
    kiss::Ax25Frame,
    log::LogItem,
};

#[derive(Debug)]
pub enum Message {
    Ax25FrameReceived(Ax25Frame),
    Clear,
    Config,
    ConfigCanceled,
    ConfigSaved,
    ConnectedToTnc(bool),
    DisplayAprsAll,
    DisplayAprsMessages,
    Dump(u64),
    Exit,
    Forget(String),
    Help,
    LogPublish(LogItem),
    LogUpdate(LogItem),
    Quit,
    SendAprsMessage { addressee: String, text: String },
    Tick,
    UserKey(KeyEvent),
}
