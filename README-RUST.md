This readme has two sections. The top is a user's guide if you just want to use kisstty. The bottom is for folks who want to build and test it.

# User's guide

The rust build runs on Linux and Windows (not yet tested) and talks KISS over TCP only. It was only tested with [direwolf](https://github.com/wb2osz/direwolf) as the TNC, but should work on anything else that speaks KISS.

## Requirements

Rust and a KISS TNC reachable over TCP. See "Connecting to a TNC" below.

## Running

```
cargo run --bin kisstty
```

First run writes a default config into your OS's standard config directory (e.g. `~/.config/kisstty/config.toml` on Linux) and drops you straight into the config screen. You'll need to set a callsign to continue.

## The config screen

`/config` opens the config screen at any time. Tab/Shift+Tab (or the Up/Down) move between fields and buttons, and Esc cancels.

* Callsign - your station's callsign, with an optional `-SSID`.
* Digipeaters - comma separated path, e.g. `WIDE1-1,WIDE2-1`.
* KISS host / KISS port - where your TNC's KISS-over-TCP is listening.
  Defaults to `127.0.0.1:8001`, direwolf's own default `KISSPORT`.

## Modes

kisstty starts in Net mode. See the main [README.md](README.md#net-mode-and-qso-mode-rust-only)
for what each mode shows. The commands themselves are below, under "Slash commands".

## Connecting to a TNC

If you're using direwolf, you'll need to make sure that the KISSPORT is set to whatever you configure in kisstty. E.g. if you set the KISS Port to 8001 in kisstty (the default):

```
# ~/.config/direwolf/direwolf.conf
KISSPORT 8001

direwolf -c ~/.config/direwolf/direwolf.conf -t 0
```

## Using it

Once you save your config, it will drop you into `net` mode. If you configured everything correctly, you should start seeing messages fly by (assuming there is local traffic).

### Basic controls

* Scroll: Up/Down arrow keys
* Pausing the view: `Esc`
* Returning to tail mode: `Esc`
* Scrolling to top or bottom: `Ctrl+Home`/`Ctrl+End`
* Executing commands: See 'Slash Commands' below.
* Getting help: `/help`

### Slash commands

kisstty makes use of slash commands. If you type a `/` as the first character, you'll see a pop-up showing all commands. As you type, the popup will filter to what you're typing. You can hit `tab` to tab-complete.

Here are the basic commands:

```
/net              # send to CQ, show only APRS messages
/qso <callsign>   # send to that station, show only messages between you and them
/monitor          # send to CQ, show every APRS data type (not all parsed yet)
/dump             # every copy and ack seen for a packet
/clear            # clears all messages from the terminal
/config           # access the config screen
/exit             # I wonder what this does
/help             # Hmmm, this one's also confusing. What could it be?
```

You can type `/help` at any time to see the usage notes.

## Known limitations

* Only one instance of kisstty can run per machine at a time.
* TCP KISS only, no direct serial TNC support.
* I'm not actually parsing non-`message` type APRS messages yet. They're displayed in monitor mode as raw text.

------

Everything below here is for developers wanting to work on kisstty.

------

# Building and running

```
cargo build --release -p kisstty
```

Produces `target/release/kisstty` (`kisstty.exe` on Windows).

```
cargo run --bin kisstty             # debug build
cargo run --bin kisstty --release
RUST_LOG=debug cargo run --bin kisstty   # verbose logging
```

Logs land in your OS's standard data directory (e.g. `~/.local/share/kisstty/logs/kisstty.log` on Linux).

# Releasing and distributing

Pushing a tag matching the `version` in `platform/rust/Cargo.toml` (e.g. `v0.1.0`) runs `.github/workflows/release.yml`, which builds an MSI, a `.deb`, a `.rpm`, and an Atari release zip (`.xex` + `.atr` + docs), and attaches them plus a `SHA256SUMS.txt` to a GitHub Release. See [README-ATARI.md](README-ATARI.md#building-kisstty) for the Atari build's own prerequisites.

Installers aren't code-signed, so the [Releases page](https://github.com/kirbyfrugia/kisstty/releases) is the only trusted source for official builds. Check a download against `SHA256SUMS.txt` to confirm it's unmodified.

## Building installers locally

### Windows: MSI

Needs the WiX Toolset v3 (`candle.exe`/`light.exe`):

1. Download and extract [wix314-binaries.zip](https://github.com/wixtoolset/wix3/releases/download/wix3141rtm/wix314-binaries.zip).
2. `cargo install cargo-wix --locked`
3. From `platform/rust` (the license path in `wix/main.wxs` is relative to the crate directory):

```
cargo wix -p kisstty --nocapture --bin-path "<path-to-wix-bin>"
```

Drop `--bin-path` if the WiX binaries are already on `PATH`. Output: `target\wix\kisstty-<version>-x86_64.msi`.

### Linux: .deb and .rpm

```
cargo install cargo-deb cargo-generate-rpm --locked
cargo build --release -p kisstty
cargo deb -p kisstty --no-build
mkdir -p target/generate-rpm
cargo generate-rpm -p platform/rust -o target/generate-rpm/
```

Output: `target/debian/*.deb` and `target/generate-rpm/*.rpm`. Both install to `/usr/bin/kisstty`, the standard location for a package-manager-installed tool, so installing needs root. Running `kisstty` doesn't. config, logs, and the lock file all resolve per-user at runtime (`~/.config/kisstty/`, `~/.local/share/kisstty/logs/`, `/tmp/kisstty.lock`).
