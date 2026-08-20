use std::net::IpAddr;
use std::path::PathBuf;
use dirs;

use serde::{Deserialize, Serialize};

use color_eyre::eyre::eyre;

use crate::kiss;
use crate::kiss::Ax25Error;

// DNS limits from RFC 1035
pub const MAX_HOST_LEN: usize = 253;
const MAX_SEGMENT_LEN: usize = 63;

#[derive(thiserror::Error, Debug)]
pub enum ConfigError {
    #[error("station cannot be empty")]
    EmptyStation,
    #[error("host cannot be empty")]
    EmptyHost,
    #[error("host is too long")]
    HostTooLong,
    #[error("host cannot contain an empty segment")]
    HostContainsEmptySegment,
    #[error("host segment too long")]
    HostSegmentTooLong,
    #[error("host segment cannot start or end with '-'")]
    HostSegmentStartsOrEndsWithDash,
    #[error("invalid host")]
    InvalidHost,
    #[error("port must be a number from 1-65535")]
    InvalidPort,
    #[error("{0}")]
    Ax25(#[from] Ax25Error),
}

pub fn validate_host(host: &str) -> Result<(), ConfigError> {
    let host = host.trim();
    if host.is_empty() {
        return Err(ConfigError::EmptyHost)
    }


    if host.len() > MAX_HOST_LEN {
        return Err(ConfigError::HostTooLong)
    }

    for segment in host.split('.') {
        if segment.is_empty() {
            return Err(ConfigError::HostContainsEmptySegment)
        }
        if segment.len() > MAX_SEGMENT_LEN {
            return Err(ConfigError::HostSegmentTooLong)
        }
        if segment.starts_with('-') || segment.ends_with('-') {
            return Err(ConfigError::HostSegmentStartsOrEndsWithDash)
        }
        if !segment.chars().all(|c| c.is_ascii_alphanumeric() || c == '-') {
            return Err(ConfigError::InvalidHost)
        }
    }

    if !host.parse::<IpAddr>().is_ok() {
        return Err(ConfigError::InvalidHost)
    }

    Ok(())
}

pub fn parse_digipeaters(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(|d| d.trim().to_uppercase())
        .filter(|d| !d.is_empty())
        .collect()
}

pub fn validate_digipeaters(value: &str) -> Result<(), ConfigError> {
    kiss::parse_digipeater_path(&parse_digipeaters(value))?;
    Ok(())
}

pub fn validate_port(port: u16) -> Result<(), ConfigError> {
    if port == 0 {
        return Err(ConfigError::InvalidPort);
    }
    Ok(())
}

pub fn validate_station(value: &str) -> Result<(), ConfigError> {
    if value.trim().is_empty() {
        return Err(ConfigError::EmptyStation)
    }
    kiss::Ax25Addr::parse(value)?;
    Ok(())
}

fn default_kiss_host() -> String {
    "127.0.0.1".into()
}

fn default_kiss_port() -> u16 {
    8001
}

#[derive(Debug, Deserialize, Serialize)]
pub struct Config {
    #[serde(rename = "callsign")]
    pub station: String,
    #[serde(default="default_kiss_host")]
    pub kiss_host: String,
    #[serde(default="default_kiss_port")]
    pub kiss_port: u16,
    #[serde(default)]
    pub digipeaters: Vec<String>,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            station: String::new(),
            kiss_host: default_kiss_host(),
            kiss_port: default_kiss_port(),
            digipeaters: Vec::new(),
        }
    }
}

impl Config {
    pub fn config_path() -> Option<PathBuf> {
        dirs::config_dir().map(|dir| dir.join("kisstty").join("config.toml"))
    }

    pub fn validate(&self) -> Result<(), ConfigError> {
        validate_station(&self.station)?;
        validate_host(&self.kiss_host)?;
        validate_port(self.kiss_port)?;
        kiss::parse_digipeater_path(&self.digipeaters)?;
        Ok(())
    }

    pub fn load() -> color_eyre::Result<Config> {
        let path = Self::config_path()
            .ok_or_else(|| eyre!("could not determine config path"))?;

        if !path.exists() {
            let default = Self::default();
            default.save()?;
            return Ok(default);
        }

        let contents = std::fs::read_to_string(&path)?;
        let config: Config = toml::from_str(&contents)?;
        Ok(config)
    }

    pub fn save(&self) -> color_eyre::Result<()> {
        let path = Self::config_path()
            .ok_or_else(|| eyre!("could not determine config path"))?;

        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        let toml_str = toml::to_string_pretty(self)?;
        std::fs::write(path, toml_str)?;
        Ok(())
    }
}
