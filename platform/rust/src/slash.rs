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
        slash:      "/all",
        args:       "",
        friendly:   "Display all Aprs packets",
        to_message: |_| Some(Message::DisplayAprsAll),
    },
    SlashCommand {
        slash:      "/messages",
        args:       "",
        friendly:   "Display only Aprs 'message' packets",
        to_message: |_| Some(Message::DisplayAprsMessages),
    },
    SlashCommand {
        slash:      "/forget",
        args:       "<station>",
        friendly:   "Don't highlight <station> or show in auto-complete",
        to_message: |a| match a {
            [c] => Some(Message::Forget(c.to_uppercase())),
            _   => None,
        },
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
            .filter(|cmd| cmd.slash.to_uppercase().starts_with(&prefix.to_uppercase()))
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
