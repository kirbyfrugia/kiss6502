//! scenario-runner - semi-interactive integration tests for kisstty.
//!
//! Reads a scenario TOML, drives a live direwolf, injects real packets, and
//! walks you through checking what the app does with them.
//!
//!     scenario-runner scenarios/atari/acks.toml
//!     scenario-runner --check scenarios/*/*.toml
//!
//! Start the app under test first; the runner starts and stops direwolf
//! itself. See tests/README.md for the scenario format.

mod picker;
mod run;
mod scenario;
mod settings;
mod ui;

use kisstty_harness::emergency_stop;
use run::Run;
use scenario::Scenario;
use settings::Settings;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use ui::Ui;

struct Args {
    scenario: Vec<String>,
    serial_override: Option<String>,
    /// Whether the override above came from this run's own command line, as
    /// opposed to just being unset -- an explicit argument wins over the
    /// picker's settings entry, which can only change the latter.
    serial_override_given: bool,
    conf_template: PathBuf,
    check: bool,
}

fn default_template() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("direwolf.conf.template")
}

fn scenarios_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("scenarios")
}

fn usage() {
    eprintln!("usage: scenario-runner [options] <scenario.toml> [serial-device]");
    eprintln!("       scenario-runner --check <scenario.toml>...");
    eprintln!("       scenario-runner                          (interactive menu)");
    eprintln!();
    eprintln!("       serial-device overrides the one in the scenario, and is a sticky");
    eprintln!("       default from then on; pass '' for TCP KISS only");
    eprintln!();
    eprintln!("options:");
    eprintln!("  -c, --conf-template PATH  direwolf.conf template (default: next to this binary)");
    eprintln!("      --check               parse and validate the scenarios, then exit");
}

fn parse_args() -> Result<Args, String> {
    let mut args = Args {
        scenario: Vec::new(),
        serial_override: None,
        serial_override_given: false,
        conf_template: default_template(),
        check: false,
    };
    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "-c" | "--conf-template" => {
                args.conf_template =
                    PathBuf::from(it.next().ok_or("--conf-template needs a path")?);
            }
            "--check" => args.check = true,
            "-h" | "--help" => {
                usage();
                std::process::exit(0);
            }
            _ if args.scenario.is_empty() || args.check => args.scenario.push(arg),
            _ if !args.serial_override_given => {
                args.serial_override = Some(arg.clone());
                args.serial_override_given = true;
                let mut settings = Settings::load();
                settings.serial_port = arg;
                settings.save();
            }
            _ => return Err(format!("unexpected argument: {arg}")),
        }
    }
    Ok(args)
}

/// Parses and validates scenarios without touching any hardware.
fn check_only(paths: &[String], ui: &Ui) -> i32 {
    let mut bad = 0;
    let mut sorted: Vec<&String> = paths.iter().collect();
    sorted.sort();
    for p in sorted {
        let path = Path::new(p);
        // Just needs to be non-empty, to satisfy the "a wire scenario needs
        // a device" check structurally -- --check never opens one.
        let result = Scenario::load(path).and_then(|s| {
            s.validate("placeholder")?;
            Ok(s)
        });
        match result {
            Ok(s) => {
                let kind = if s.uses_air() {
                    "air"
                } else if s.uses_wire() {
                    "wire"
                } else {
                    "manual"
                };
                println!(
                    "{} {p:<44} {}",
                    ui.green("OK"),
                    ui.dim(&format!(
                        "{:<6} {:>3} steps  {kind}",
                        s.platform,
                        s.steps.len()
                    ))
                );
            }
            Err(e) => {
                println!("{} {e}", ui.red("XX"));
                bad += 1;
            }
        }
    }
    if bad > 0 {
        println!(
            "\n{}",
            ui.red(&format!("{bad} scenario(s) failed to validate"))
        );
    }
    if bad > 0 { 1 } else { 0 }
}

fn run_scenario(run: &mut Run) -> i32 {
    match run.start_hardware() {
        Ok(true) => {}
        Ok(false) => {
            println!("\n   quit before starting");
            return 1;
        }
        Err(e) => {
            eprintln!("\n{e}");
            return 1;
        }
    }
    run.run();
    run.summary()
}

/// Loads, validates, previews and runs one scenario, start to finish.
fn run_one(path: &Path, args: &Args) -> i32 {
    let settings = Settings::load();
    let ui = Ui::new();

    let scenario = match Scenario::load(path) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("{} {e}", ui.red("XX"));
            return 2;
        }
    };

    // Only atari scenarios talk over a serial device at all; an explicit
    // command-line argument still wins over the persisted default.
    let serial = args.serial_override.clone().unwrap_or_else(|| {
        if scenario.platform == "atari" {
            settings.serial_port.clone()
        } else {
            String::new()
        }
    });
    if let Err(e) = scenario.validate(&serial) {
        eprintln!("{} {e}", ui.red("XX"));
        return 2;
    }

    let mut run = Run::new(
        &scenario,
        ui,
        serial,
        settings.tcp_port,
        args.conf_template.clone(),
    );
    run.preview();
    let code = run_scenario(&mut run);
    run.stop_hardware();
    code
}

fn main() -> ExitCode {
    // exit() skips Drop, so the handler has to stop direwolf itself or it
    // keeps the KISS port and the serial device.
    if let Err(e) = ctrlc::set_handler(|| {
        emergency_stop();
        std::process::exit(130);
    }) {
        eprintln!("could not install ctrl-c handler: {e}");
        return ExitCode::from(2);
    }

    let args = match parse_args() {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{e}");
            usage();
            return ExitCode::from(2);
        }
    };

    if args.check {
        let ui = Ui::new();
        if args.scenario.is_empty() {
            usage();
            return ExitCode::from(2);
        }
        return ExitCode::from(check_only(&args.scenario, &ui) as u8);
    }

    if !args.scenario.is_empty() {
        if args.scenario.len() > 1 {
            eprintln!("give one scenario (and optionally a serial device), or --check");
            return ExitCode::from(2);
        }
        let path = PathBuf::from(&args.scenario[0]);
        return ExitCode::from(run_one(&path, &args) as u8);
    }

    if !std::io::stdin().is_terminal() {
        usage();
        return ExitCode::from(2);
    }

    // The interactive picker: run a scenario, land back in the same
    // directory to pick another. Ctrl-c is the only way out from here.
    let root = scenarios_root();
    let mut current = root.clone();
    loop {
        match picker::pick_scenario(
            &root,
            &mut current,
            &mut kisstty_harness::read_menu_key,
            &mut kisstty_harness::read_menu_line,
        ) {
            Some(path) => {
                run_one(&path, &args);
            }
            None => return ExitCode::SUCCESS,
        }
    }
}
