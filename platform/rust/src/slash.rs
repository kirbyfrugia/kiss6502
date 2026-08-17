use crate::message::Message;

#[derive(Debug)]
pub struct SlashCommand {
    pub slash:      &'static str,
    pub args:       &'static str,
    pub friendly:   &'static str,
    pub to_message: fn(&[&str]) -> Option<Message>,
}

pub const SLASH_COMMANDS: &[SlashCommand] = &[
    SlashCommand {
        slash:      "/help",
        args:       "",
        friendly:   "Show help",
        to_message: |_| Some(Message::Help),
    },
    SlashCommand {
        slash:      "/net",
        args:       "",
        friendly:   "Net mode (broadcast send, rcv only APRS msg data type)",
        to_message: |_| Some(Message::Net),
    },
    SlashCommand {
        slash:      "/qso",
        args:       "<callsign>",
        friendly:   "QSO mode (one-to-one convo)",
        to_message: |a| match a {
            [c] => Some(Message::Qso(c.to_uppercase())),
            _   => None,
        },
    },
    SlashCommand {
        slash:      "/monitor",
        args:       "",
        friendly:   "Monitor mode (broadcast send, rcv all APRS data types)",
        to_message: |_| Some(Message::Monitor),
    },
    SlashCommand {
        slash:      "/dump",
        args:       "<id>",
        friendly:   "Show every instance and ack seen for a packet",
        to_message: |a| match a {
            [id] => id.parse().ok().map(Message::Dump),
            _    => None,
        },
    },
    SlashCommand {
        slash:      "/clear",
        args:       "",
        friendly:   "Clear all the output",
        to_message: |_| Some(Message::Clear),
    },
    SlashCommand {
        slash:      "/config",
        args:       "",
        friendly:   "Open configuration",
        to_message: |_| Some(Message::Config),
    },
    SlashCommand {
        slash:      "/exit",
        args:       "",
        friendly:   "Exit kisstty",
        to_message: |_| Some(Message::Exit),
    },
];

impl SlashCommand {
    pub fn matching(prefix: &str) -> Vec<&'static SlashCommand> {
        SLASH_COMMANDS
            .iter()
            .filter(|cmd| cmd.slash.starts_with(prefix))
            .collect()
    }

    pub fn find(name: &str) -> Option<&'static SlashCommand> {
        SLASH_COMMANDS
            .iter()
            .find(|cmd| cmd.slash == name)
    }

    pub fn usage(&self) -> String {
        if self.args.is_empty() {
            self.slash.to_string()
        } else {
            format!("{} {}", self.slash, self.args)
        }
    }

    pub fn max_usage_width() -> usize {
        SLASH_COMMANDS
            .iter()
            .map(|cmd| cmd.usage().len())
            .max()
            .unwrap_or(0)
    }
}
