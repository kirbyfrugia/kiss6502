//! The scenario TOML model: parsing, validation, and the invariants that
//! make a scenario meaningful.

use kisstty_harness::unescape;
use serde::Deserialize;
use std::fs;
use std::path::{Path, PathBuf};

const DEFAULT_TIMEOUT: u64 = 5;

/// A problem with the scenario file, reported without a traceback.
pub type ScenarioError = String;

/// Every text key takes a string or a list of them, uniformly.
#[derive(Deserialize)]
#[serde(untagged)]
enum Lines {
    One(String),
    Many(Vec<String>),
}

impl Lines {
    fn into_vec(self) -> Vec<String> {
        match self {
            Lines::One(s) => vec![s],
            Lines::Many(v) => v,
        }
    }
}

fn lines(value: Option<Lines>) -> Vec<String> {
    value.map(Lines::into_vec).unwrap_or_default()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawScenario {
    name: String,
    #[serde(default)]
    mycall: String,
    #[serde(default)]
    step: Vec<RawStep>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct RawStep {
    description: Option<String>,
    #[serde(rename = "do")]
    action: Option<Lines>,
    to_kisstty: Option<Lines>,
    to_serial: Option<Lines>,
    from_serial: Option<Lines>,
    from_kisstty: Option<Lines>,
    not_from_kisstty: Option<Lines>,
    look_for: Option<Lines>,
    #[serde(default)]
    random: bool,
    repeat: Option<u64>,
    every: Option<u64>,
    wait: Option<u64>,
    timeout: Option<u64>,
}

#[derive(Debug)]
pub struct Step {
    pub index: usize,
    pub description: String,
    pub do_: Vec<String>,
    pub to_kisstty: Vec<String>,
    pub to_serial: Vec<String>,
    pub from_serial: Vec<String>,
    pub from_kisstty: Vec<String>,
    pub not_from_kisstty: Vec<String>,
    pub look_for: Vec<String>,
    pub random: bool,
    pub repeat: u64,
    pub every: u64,
    pub wait: Option<u64>,
    pub timeout: u64,
}

impl Step {
    fn from_raw(raw: RawStep, index: usize) -> Self {
        Self {
            index,
            description: raw.description.unwrap_or_default(),
            do_: lines(raw.action),
            to_kisstty: lines(raw.to_kisstty),
            to_serial: lines(raw.to_serial),
            from_serial: lines(raw.from_serial),
            from_kisstty: lines(raw.from_kisstty),
            not_from_kisstty: lines(raw.not_from_kisstty),
            look_for: lines(raw.look_for),
            random: raw.random,
            repeat: raw.repeat.unwrap_or(1),
            every: raw.every.unwrap_or(1),
            wait: raw.wait,
            timeout: raw.timeout.unwrap_or(DEFAULT_TIMEOUT),
        }
    }

    pub fn needs_you_to_act(&self) -> bool {
        !self.do_.is_empty()
    }

    pub fn needs_you_to_look(&self) -> bool {
        !self.look_for.is_empty()
    }

    /// Whether this step means the scenario needs direwolf on the air.
    pub fn uses_air(&self) -> bool {
        self.random
            || !self.to_kisstty.is_empty()
            || !self.from_kisstty.is_empty()
            || !self.not_from_kisstty.is_empty()
    }

    /// Whether this step means the scenario drives the serial device itself.
    pub fn uses_wire(&self) -> bool {
        !self.to_serial.is_empty() || !self.from_serial.is_empty()
    }
}

#[derive(Debug)]
pub struct Scenario {
    pub path: PathBuf,
    pub name: String,
    /// The look_for lines describe one platform's screen, so a scenario is
    /// not portable between builds. The directory is the single source of
    /// truth for which one it is.
    pub platform: String,
    pub mycall: String,
    pub steps: Vec<Step>,
}

impl Scenario {
    pub fn load(path: &Path) -> Result<Self, ScenarioError> {
        let where_ = path.display().to_string();
        let text = fs::read_to_string(path).map_err(|e| format!("reading {where_}: {e}"))?;

        let raw: RawScenario =
            toml::from_str(&text).map_err(|e| format!("parsing {where_}: {e}"))?;

        if raw.name.is_empty() {
            return Err(format!("{where_}: needs a name"));
        }
        if raw.step.is_empty() {
            return Err(format!("{where_}: no steps"));
        }

        let platform = path
            .parent()
            .and_then(|p| p.file_name())
            .map(|n| n.to_string_lossy().into_owned())
            .unwrap_or_default();
        let steps = raw
            .step
            .into_iter()
            .enumerate()
            .map(|(i, s)| Step::from_raw(s, i + 1))
            .collect();

        Ok(Scenario {
            path: path.to_path_buf(),
            name: raw.name,
            platform,
            mycall: raw.mycall,
            steps,
        })
    }

    /// Whether anything here actually needs direwolf.
    ///
    /// A scenario made only of `do` and `look_for` steps drives the app
    /// some other way, so starting direwolf would take the serial device
    /// for nothing.
    pub fn uses_air(&self) -> bool {
        self.steps.iter().any(Step::uses_air)
    }

    pub fn uses_wire(&self) -> bool {
        self.steps.iter().any(Step::uses_wire)
    }

    /// The invariants that make a scenario meaningful. Checked before we
    /// start anything, so a bad scenario costs no hardware setup.
    pub fn validate(&self, serial: &str) -> Result<(), ScenarioError> {
        let where_ = self.path.display();

        // Direwolf opens the serial device itself, so a scenario cannot
        // also write to it.
        if self.uses_air() && self.uses_wire() {
            return Err(format!(
                "{where_}: uses direwolf and the serial device at the same time, and \
                 direwolf would already have the device open. split it in two."
            ));
        }
        if self.uses_air() && self.mycall.is_empty() {
            return Err(format!(
                "{where_}: sends or checks packets, so it needs a mycall"
            ));
        }
        if self.uses_wire() && serial.is_empty() {
            return Err(format!(
                "{where_}: to_serial and from_serial need a serial device"
            ));
        }

        for step in &self.steps {
            for (key, chunks) in [
                ("to_serial", &step.to_serial),
                ("from_serial", &step.from_serial),
            ] {
                for chunk in chunks {
                    let data = unescape(chunk).map_err(|e| {
                        format!("{where_}: step {}: bad escape in {key}: {e}", step.index)
                    })?;
                    // A backslash reaching the wire means the scenario was
                    // written with \\r where it meant \r, which sends the
                    // escape as text and silently tests nothing.
                    if data.contains(&b'\\') {
                        return Err(format!(
                            "{where_}: step {}: {key} value {chunk:?} puts a literal \
                             backslash on the wire, so it is double escaped. write \\r, \
                             not \\\\r.",
                            step.index
                        ));
                    }
                }
            }
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn write(dir: &std::path::Path, platform: &str, body: &str) -> PathBuf {
        let d = dir.join(platform);
        std::fs::create_dir_all(&d).unwrap();
        let p = d.join("scratch.toml");
        std::fs::write(&p, body).unwrap();
        p
    }

    #[test]
    fn unknown_and_wrong_type_keys_are_rejected() {
        let dir = tempfile::tempdir().unwrap();
        for body in [
            "name = \"x\"\n[[step]]\nlook_fro = \"typo\"\n",
            "name = \"x\"\nmycal = \"NOCALL\"\n[[step]]\ndo = \"thing\"\n",
            "name = \"x\"\n[[step]]\nlook_for = 3\n",
            // platform comes from the directory, serial from settings.
            "name = \"x\"\nplatform = \"atari\"\n[[step]]\ndo = \"thing\"\n",
            "name = \"x\"\nserial = \"/tmp/altirra-tty\"\n[[step]]\ndo = \"thing\"\n",
        ] {
            assert!(Scenario::load(&write(dir.path(), "atari", body)).is_err());
        }
    }

    #[test]
    fn text_keys_accept_string_or_list() {
        let dir = tempfile::tempdir().unwrap();
        let p = write(
            dir.path(),
            "atari",
            "name = \"x\"\n[[step]]\nlook_for = \"one\"\ndo = [\"first\", \"second\"]\n",
        );
        let s = Scenario::load(&p).unwrap();
        assert_eq!(s.steps[0].look_for, vec!["one"]);
        assert_eq!(s.steps[0].do_, vec!["first", "second"]);
    }

    #[test]
    fn validate_catches_setup_problems() {
        let dir = tempfile::tempdir().unwrap();

        let p = write(
            dir.path(),
            "atari",
            "name = \"x\"\nmycall = \"NOCALL\"\n\
             [[step]]\nto_kisstty = \"A>B::C   :hi\"\n\
             [[step]]\nto_serial = 'AB\\r'\n",
        );
        let err = Scenario::load(&p).unwrap().validate("/tmp/t").unwrap_err();
        assert!(err.contains("same time"), "{err}");

        let p = write(
            dir.path(),
            "atari",
            "name = \"x\"\n[[step]]\nto_kisstty = \"A>B::C   :hi\"\n",
        );
        let err = Scenario::load(&p).unwrap().validate("").unwrap_err();
        assert!(err.contains("needs a mycall"), "{err}");

        let p = write(
            dir.path(),
            "atari",
            "name = \"x\"\n[[step]]\nto_serial = 'AB\\r'\n",
        );
        let err = Scenario::load(&p).unwrap().validate("").unwrap_err();
        assert!(err.contains("need a serial device"), "{err}");

        let p = write(
            dir.path(),
            "atari",
            "name = \"x\"\n[[step]]\nto_serial = 'AB\\\\r'\n",
        );
        let err = Scenario::load(&p).unwrap().validate("/tmp/t").unwrap_err();
        assert!(err.contains("double escaped"), "{err}");

        // Manual scenario: needs neither a mycall nor a device.
        let p = write(
            dir.path(),
            "atari",
            "name = \"x\"\n[[step]]\ndo = \"press a key\"\nlook_for = \"a thing\"\n",
        );
        let s = Scenario::load(&p).unwrap();
        s.validate("").unwrap();
        assert!(!s.uses_air() && !s.uses_wire());
    }
}
