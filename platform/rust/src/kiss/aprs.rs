
#[derive(thiserror::Error, Debug)]
pub enum AprsError {
    #[error("empty info field")]
    EmptyInfo,
    #[error("empty message format")]
    InvalidFormat,
}

#[derive(Debug,Clone)]
pub enum AprsData {
    Message(AprsMessage),
    Status(AprsStatus),
    ThirdParty(AprsThirdParty),
    ToBeImplemented(AprsToBeImplemented),
}

#[derive(Debug,Clone)]
pub struct AprsMessage {
    pub addressee: String,
    pub text: String,
    pub id: Option<String>,
}

#[derive(Debug,Clone)]
pub struct AprsStatus {
    pub text: String,
}

#[derive(Debug,Clone)]
pub struct AprsThirdParty {
    pub text: String,
}

#[derive(Debug,Clone)]
pub struct AprsToBeImplemented {
    pub data_type_id: char,
    pub text: String,
}

impl AprsData {
    pub fn data_type_id(&self) -> char {
        match self {
            AprsData::Message(_) => ':',
            AprsData::Status(_) => '>',
            AprsData::ThirdParty(_) => '}',
            AprsData::ToBeImplemented(unimplemented) => unimplemented.data_type_id,
        }
    }

    pub fn body(&self) -> &str {
        match self {
            AprsData::Message(msg) => &msg.text,
            AprsData::Status(status) => &status.text,
            AprsData::ThirdParty(third_party) => &third_party.text,
            AprsData::ToBeImplemented(unimplemented) => &unimplemented.text,
        }
    }

    pub fn encode(&self) -> Vec<u8> {
        let mut bytes = vec![self.data_type_id() as u8];
        match self {
            AprsData::Message(msg) => bytes.extend(msg.encode()),
            AprsData::Status(status) => bytes.extend(status.encode()),
            AprsData::ThirdParty(third_party) => bytes.extend(third_party.encode()),
            AprsData::ToBeImplemented(unimplemented) => bytes.extend(unimplemented.encode()),
        }
        bytes
    }

    pub fn decode(info: &[u8]) -> Result<Self, AprsError> {
        let Some((&data_type_id, rest)) = info.split_first() else {
            tracing::warn!("frame has empty info field");
            return Err(AprsError::EmptyInfo);
        };

        match data_type_id {
            b':' => Ok(AprsData::Message(AprsMessage::decode(rest))),
            b'>' => Ok(AprsData::Status(AprsStatus::decode(rest))),
            b'}' => Ok(AprsData::ThirdParty(AprsThirdParty::decode(rest))),
            other => Ok(AprsData::ToBeImplemented(AprsToBeImplemented::decode(other, rest))),
        }
    }
}

impl AprsMessage {
    pub const BROADCAST_ADDRESSEE: &str = "CQ";

    pub fn is_broadcast_addressee(addressee: &str) -> bool {
        let addressee = addressee.trim().to_uppercase();
        matches!(addressee.as_str(), "ALL" | "QST" | "CQ") || addressee.starts_with("BLN")
    }

    pub fn new(addressee: String, text: String, id: Option<String>) -> Self {
        Self {
            addressee,
            text,
            id,
        }
    }

    pub fn is_ack(&self) -> bool {
        self.ack_id().is_some()
    }

    pub fn ack_id(&self) -> Option<&str> {
        let id = self.text.strip_prefix("ack")?;
        (1..=5).contains(&id.chars().count()).then_some(id)
    }

    fn encode(&self) -> Vec<u8> {
        let mut encoded = format!("{:<9}:{}", self.addressee, self.text);
        if let Some(id) = &self.id {
            encoded.push('{');
            encoded.push_str(id);
        }
        encoded.into_bytes()
    }

    fn decode(info: &[u8]) -> Self {
        let addressee = info.get(0..9)
            .map(|a| String::from_utf8_lossy(a).trim_end().to_string())
            .unwrap_or_default();
        let body = info.get(10..)
            .map(|t| String::from_utf8_lossy(t).into_owned())
            .unwrap_or_default();

        let (text, id) = match body.rsplit_once('{') {
            Some((text, id)) if (1..=5).contains(&id.chars().count()) => {
                (text.to_string(), Some(id.to_string()))
            },
            _ => (body, None),
        };

        Self { addressee, text, id }
    }

    /// Parses from a string, e.g.
    /// :ADDRESSEE:message
    pub fn parse(info: &str) -> Result<AprsMessage, AprsError> {
        let rest = info.strip_prefix(':').ok_or(AprsError::InvalidFormat)?;
        let (addressee, rest) = rest.split_once(':').ok_or(AprsError::InvalidFormat)?;
        let addressee = addressee.trim_end().to_string();

        let (text, id) = match rest.split_once('{') {
            Some((text, id)) => (text.to_string(), Some(id.to_string())),
            None => (rest.to_string(), None),
        };

        Ok(AprsMessage { addressee, text, id })
    }
}

impl std::fmt::Display for AprsMessage {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:<9}:{}", self.addressee, self.text)
    }
}

impl AprsStatus {
    fn encode(&self) -> Vec<u8> {
        self.text.as_bytes().to_vec()
    }

    fn decode(info: &[u8]) -> Self {
        Self {
            text: String::from_utf8_lossy(info).into_owned(),
        }
    }
}

impl AprsThirdParty {
    fn encode(&self) -> Vec<u8> {
        self.text.as_bytes().to_vec()
    }

    fn decode(info: &[u8]) -> Self {
        Self {
            text: String::from_utf8_lossy(info).into_owned(),
        }
    }
}

impl AprsToBeImplemented {
    fn encode(&self) -> Vec<u8> {
        self.text.as_bytes().to_vec()
    }

    fn decode(data_type_id: u8, info: &[u8]) -> Self {
        let data_type_id = data_type_id as char;
        Self {
            data_type_id,
            text: String::from_utf8_lossy(info).into_owned(),
        }
    }
}
