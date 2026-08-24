//! packet-injector - simulate an APRS packet arriving at kisstty.
//!
//! Picks a packet test (interactively, or by name) from the `tests.toml`
//! tree under `packets/`, and feeds it through a temporary direwolf so it
//! decodes to KISS. Run with `-h` for options; see tests/README.md for the
//! tests.toml format.
//!
//! Requires `direwolf` and `gen_packets` on PATH.

mod interactive;
mod packets;
mod settings;

use interactive::pick_interactive;
use kisstty_harness::{Direwolf, TRAILING_SILENCE, Xorshift64, emergency_stop};
use packets::{FindResult, Test, all_tests, find_test};
use settings::Settings;
use std::io::IsTerminal;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Duration;

struct Args {
    conf: PathBuf,
    dir: PathBuf,
    test: Option<String>,
    random_cat: Option<String>,
    interval: Option<f64>,
    count: Option<u64>,
    list: bool,
}

fn manifest_dir() -> &'static Path {
    Path::new(env!("CARGO_MANIFEST_DIR"))
}

fn usage() {
    eprintln!("usage: packet-injector [options]");
    eprintln!("       with no options and a terminal on stdin, opens the interactive menu");
    eprintln!();
    eprintln!("options:");
    eprintln!("  -c, --conf PATH        direwolf.conf template (default: next to this binary)");
    eprintln!(
        "  -d, --dir PATH         root packet directory (default: packets/ next to this binary)"
    );
    eprintln!(
        "  -s, --serial DEVICE    serial device to bridge, and switch to using it (sticky default)"
    );
    eprintln!("      --tcp              use TCP KISS only, no serial bridge (sticky default)");
    eprintln!("  -t, --test NAME        inject this test, by <dir>/<name> or a unique bare name");
    eprintln!(
        "  -T, --random CATEGORY  inject a random test from this category subtree each repetition"
    );
    eprintln!("  -r, --interval SECONDS repeat every N seconds (forever unless -n also given)");
    eprintln!("  -n, --count N          repeat N times (default: 1)");
    eprintln!("  -l, --list             list every test in the tree and exit");
}

fn parse_args() -> Result<Args, String> {
    let mut args = Args {
        conf: manifest_dir().join("..").join("direwolf.conf.template"),
        dir: manifest_dir().join("..").join("packets"),
        test: None,
        random_cat: None,
        interval: None,
        count: None,
        list: false,
    };
    let mut serial_given = false;
    let mut tcp_given = false;
    let mut it = std::env::args().skip(1);
    while let Some(arg) = it.next() {
        let mut need = |flag: &str| it.next().ok_or_else(|| format!("{flag} needs a value"));
        match arg.as_str() {
            "-c" | "--conf" => args.conf = PathBuf::from(need("--conf")?),
            "-d" | "--dir" => args.dir = PathBuf::from(need("--dir")?),
            "-s" | "--serial" => {
                serial_given = true;
                let mut settings = Settings::load();
                settings.serial_port = need("--serial")?;
                settings.use_serial = true;
                settings.save();
            }
            "--tcp" => {
                tcp_given = true;
                let mut settings = Settings::load();
                settings.use_serial = false;
                settings.save();
            }
            "-t" | "--test" => args.test = Some(need("--test")?),
            "-T" | "--random" => args.random_cat = Some(need("--random")?),
            "-r" | "--interval" => {
                args.interval = Some(
                    need("--interval")?
                        .parse()
                        .map_err(|_| "--interval needs a number")?,
                )
            }
            "-n" | "--count" => {
                args.count = Some(
                    need("--count")?
                        .parse()
                        .map_err(|_| "--count needs a number")?,
                )
            }
            "-l" | "--list" => args.list = true,
            "-h" | "--help" => {
                usage();
                std::process::exit(0);
            }
            other => return Err(format!("unrecognized argument: {other}")),
        }
    }
    if serial_given && tcp_given {
        return Err("use either --serial or --tcp, not both".to_string());
    }
    Ok(args)
}

fn pick_interactive_stdin(root: &Path, current: &mut PathBuf) -> Option<Test> {
    pick_interactive(
        root,
        current,
        &mut kisstty_harness::read_menu_key,
        &mut kisstty_harness::read_menu_line,
    )
}

fn main() -> ExitCode {
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
            eprintln!("Error: {e}");
            usage();
            return ExitCode::from(2);
        }
    };

    let root = match args.dir.canonicalize() {
        Ok(r) if r.is_dir() => r,
        _ => {
            eprintln!("Error: packet directory not found: {}", args.dir.display());
            return ExitCode::from(1);
        }
    };

    if args.list {
        packets::list_tree(&root);
        return ExitCode::SUCCESS;
    }

    if args.test.is_some() && args.random_cat.is_some() {
        eprintln!("Error: use either -t or -T, not both.");
        return ExitCode::from(2);
    }

    let mut random_pool: Option<Vec<Test>> = None;
    let mut fixed_test: Option<Test> = None;
    let interactive;

    if let Some(cat) = &args.random_cat {
        let cat = cat.trim();
        let cat_dir = if cat.is_empty() || cat == "." {
            root.clone()
        } else {
            root.join(cat)
        };
        if !cat_dir.is_dir() {
            eprintln!("Error: category not found: {cat}. Use -l to list.");
            return ExitCode::from(1);
        }
        let tests = all_tests(&cat_dir, &root);
        if tests.is_empty() {
            eprintln!("Error: no tests found under '{}'.", cat_dir.display());
            return ExitCode::from(1);
        }
        random_pool = Some(tests);
        interactive = false;
    } else if let Some(name) = &args.test {
        match find_test(&root, name) {
            FindResult::Found(t) => fixed_test = Some(t),
            FindResult::NotFound => {
                eprintln!("Error: test not found: {name}. Use -l to list.");
                return ExitCode::from(1);
            }
            FindResult::Ambiguous(paths) => {
                eprintln!(
                    "Error: '{name}' is ambiguous, it matches {}. Use the full <dir>/<name> address.",
                    paths.join(", ")
                );
                return ExitCode::from(1);
            }
        }
        interactive = false;
    } else if std::io::stdin().is_terminal() {
        interactive = true;
    } else {
        eprintln!("Error: -t or -T required in non-interactive mode. Use -l to list tests.");
        return ExitCode::from(2);
    }

    // -r with no -n runs forever; -r with -n runs that many, spaced by -r.
    let forever = args.interval.is_some() && args.count.is_none();
    let count = args.count.unwrap_or(1);
    let interval = args.interval.unwrap_or(1.0);

    let settings = Settings::load();
    let mut dw = match start_dw(&args.conf, &settings) {
        Ok(dw) => dw,
        Err(e) => {
            eprintln!("Error: {e}");
            return ExitCode::from(1);
        }
    };
    if forever {
        println!("Repeating every {interval}s. Ctrl-C to stop.");
    }

    if interactive {
        // Each pick injects once and returns to the menu, rather than
        // exiting -- repeat/interval below are for the scripted -t/-T case.
        let mut serial = settings.serial();
        let mut tcp_port = settings.tcp_port;
        let mut current = root.clone();
        while let Some(test) = pick_interactive_stdin(&root, &mut current) {
            // The menu's settings entry can change these out from under the
            // already-running direwolf; restart it so the change actually
            // takes effect this session, not just next run.
            let wanted = Settings::load();
            if wanted.serial() != serial || wanted.tcp_port != tcp_port {
                dw.stop();
                dw = match start_dw(&args.conf, &wanted) {
                    Ok(dw) => dw,
                    Err(e) => {
                        eprintln!("Error: {e}");
                        return ExitCode::from(1);
                    }
                };
                serial = wanted.serial();
                tcp_port = wanted.tcp_port;
            }

            if let Err(e) = inject(&mut dw, &test) {
                eprintln!("Error: {e}");
                return ExitCode::from(1);
            }
            // Direwolf can drain the fifo far faster than the audio's own
            // duration, so without this the menu reappears before the
            // packet has actually reached kisstty.
            std::thread::sleep(TRAILING_SILENCE);
        }
    } else {
        let mut rng = Xorshift64::new(None);

        let mut done = 0u64;
        loop {
            let test = match &random_pool {
                Some(pool) => &pool[(rng.next_u64() as usize) % pool.len()],
                None => fixed_test
                    .as_ref()
                    .expect("one of the two branches above set this"),
            };
            if forever {
                print!("[{}] ", done + 1);
            } else if count > 1 {
                print!("[{}/{count}] ", done + 1);
            }
            if let Err(e) = inject(&mut dw, test) {
                eprintln!("Error: {e}");
                return ExitCode::from(1);
            }

            done += 1;
            if !forever && done >= count {
                break;
            }
            std::thread::sleep(Duration::from_secs_f64(interval));
        }
    }

    std::thread::sleep(TRAILING_SILENCE);
    ExitCode::SUCCESS
}

fn start_dw(conf: &Path, settings: &Settings) -> Result<Direwolf, String> {
    let serial = settings.serial();
    if serial.is_empty() {
        println!("KISS over TCP on port {}", settings.tcp_port);
    } else {
        println!("KISS over serial on {serial}");
    }
    let dw = Direwolf::start(conf, &serial, "", "kisstty-inject", settings.tcp_port)?;
    println!(
        "direwolf up (pid {}), log at {}",
        dw.pid(),
        dw.log_path().display()
    );
    Ok(dw)
}

fn inject(dw: &mut Direwolf, test: &Test) -> Result<(), String> {
    if test.packet().is_empty() {
        println!(
            "Warning: test '{}' has no packet field; skipping.",
            test.path()
        );
        return Ok(());
    }
    println!(
        "Injecting [{}] ({}): {}",
        test.label(),
        test.path(),
        test.packet()
    );
    dw.inject(test.packet())
}
