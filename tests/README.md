# kisstty scenario tests

> [!NOTE]
> Unlike the main app, this test program was vibe-coded by claude, guided by me.
> I haven't even looked at this code. It's likely horrible based on my experiences
> with it. But it's working for what I needed.
> Don't judge me.

Manual-with-assist tests. A scenario drives a live direwolf, injects real 1200 baud
packets, and walks you through checking what the app under test does with them.

## Running one

`scenario-runner` and `packet-injector` are their own Cargo workspace under `tests/`,
separate from kisstty's own, so run them from there:

```
cd tests
cargo run --bin scenario-runner                              # interactive picker
cargo run --bin scenario-runner -- scenarios/atari/acks.toml
cargo run --bin scenario-runner -- --check scenarios/*/*.toml
```

Start Altirra, kisstty, and socat first, and let the scenario's opening prompt tell you
which callsign to configure. The runner starts direwolf itself and stops it on the way
out, so don't have one already running.

Each tool remembers its own settings (serial device, TCP port) under
`~/.config/kisstty-tests/`. Set them by passing a value on the command line, or from the
`.) settings` entry in the interactive menu.

In the interactive menu, picking an item is a single keypress -- no Enter needed. Items
are numbered `1`-`9`, then `A`-`Z` (35 per directory, case-insensitive). `0` goes back
a level; ctrl-c quits outright, from anywhere.

`--check` validates scenarios without touching any hardware.

Direwolf only starts if the scenario needs it -- some step uses `to_kisstty`, `random`,
`from_kisstty` or `not_from_kisstty`. A scenario built only from `do` and `look_for`
steps drives the app some other way (`line-endings.toml` does this over the serial
device directly), so it needs no callsign and no `mycall`.

## Scenarios are per platform

The platform comes from the directory a scenario lives in --
`tests/scenarios/<platform>/<name>.toml` -- not a field inside the file, so it can't
drift out of sync with where the file actually is.

This matters because the `look_for` lines describe one platform's screen. The atari
scenarios assume the 40 column display, its `SOURCE>ADDRESSEE:text#id` line format, and
its `/tx` command, so they mean nothing against the rust build. The runner itself is
platform neutral: it only knows about direwolf, packets, and prompting you.

## Writing one

```toml
name = "acks"
mycall = "NOCALL"

[[step]]
description  = "a message addressed to us is acked automatically"
to_kisstty   = "NOCALL-7>APKTY1,WIDE1-1,WIDE2-1::NOCALL   :Test message{0001"
from_kisstty = "::NOCALL-7 :ack0001"
look_for     = "NOCALL-7>NOCALL:Test message#0001"
```

Direction is always named from both ends, so there is no perspective to guess at.

| verb | what it does |
|---|---|
| `description` | what the step is testing, printed as its heading. keep it general: the verbs say what happens and `look_for` pins down the screen, so this says what it is for |
| `to_kisstty` | a TNC2 packet, or a list of them, to put on the air for kisstty to receive |
| `from_kisstty` | substring the direwolf log must contain. **checked automatically** |
| `not_from_kisstty` | substring the direwolf log must **not** contain. **checked automatically**, and costs the whole window since the only way to be sure is to wait it out |
| `timeout` | seconds to allow the two log checks, default 5 |
| `look_for` | what should be on screen. answer `y`, `n` or `q` |
| `do` | something for you to do, like sending a message. Enter when done, `q` to quit |
| `wait` | seconds to sleep, for crossing the 30s dedup window |
| `to_serial` | raw bytes to write straight to the serial device, backslash escaped |
| `from_serial` | bytes the app should put on the serial device. **checked automatically**, with the same `timeout` |
| `random` | send a message from the built in corpus instead of a literal `to_kisstty` |
| `repeat` | how many times to inject. `0` runs until you interrupt it, so put nothing after it |
| `every` | seconds between repeats, default 1 |

`look_for`, `from_kisstty`, `not_from_kisstty` and `to_kisstty` all take a string or a
list of strings.

Keys within a step read in the order the runner runs them: `description`, `do`,
`to_kisstty`, `to_serial`, `wait`, `timeout`, `from_kisstty`, `not_from_kisstty`,
`from_serial`, `look_for`.

## Driving the serial device directly

`to_serial` and `from_serial` skip direwolf and the radio entirely and talk to the app over
its serial device, which is what a terminal mode scenario needs. A scenario cannot use these
and direwolf at the same time, because direwolf would already have the device open, and both
the runner and `cargo test` (from inside `tests/`) reject one that tries.

Both take backslash escapes: `\r`, `\n`, `\t`, `\0`, `\\` and `\xNN` for any byte.

> [!IMPORTANT]
> Write these values in **TOML literal strings**, with single quotes. In a double quoted
> string TOML expands the escape first, so `"\x9b"` reaches the runner as the character
> U+009B and goes out as the two UTF-8 bytes `c2 9b` rather than the one byte you wrote.
> `\r` and `\n` happen to survive that, which is what makes the bug easy to miss. The
> runner refuses any non-ASCII character rather than sending it, so this fails loudly.

```toml
to_serial   = 'ATASCII ONE\x9bATASCII TWO\x9b'
from_serial = 'AB\r\n'
```

The device is whatever the runner's serial-port setting says, so switching from the
emulator to a real Atari on a real port is a settings change, not an edit to the
scenario.

Word a `do` step for the moment it is read, not for what happens next. The runner is
blocked waiting for you, so "watch for X" before the traffic starts leaves you waiting
for the runner while it waits for you. Say what pressing Enter will do.

A list of packets goes out back to back with no prompt between them, which is how a
scenario stays inside a timing window. `dedup.toml` needs its duplicates inside one 30
second window, and a prompt between each would let the window expire while you type. Put
the whole group in one `to_kisstty` list and check the result once at the end.

`repeat` and `every` apply to `to_kisstty` and `random` alike, which is how `soak.toml` runs
indefinitely until you press q to stop it, or ctrl-c to quit outright.

Only `from_kisstty` and `not_from_kisstty` can fail on their own, because the runner
cannot see the atari screen. For `look_for` you are the check: `y` passes, `n` records a failure and carries on, `q` stops the run.
Enter is the same as `y`.

A scenario exits non-zero if anything failed or if you quit early, and prints what went
wrong at the end. Quitting counts as not passing, since the remaining steps never ran.

Each step reads only what direwolf logged during that step, so a frame from an earlier
step can neither satisfy a `from_kisstty` nor trip a `not_from_kisstty`.

Anything the app must *not* put on the air belongs in `not_from_kisstty`, not in a
`look_for`. There is nothing on the atari screen that shows a frame was never sent.

Write `from_kisstty` as the shortest substring that pins the frame down. Matching on the whole
TNC2 line means reproducing direwolf's monitor prefix and whatever digipeater path is in
your config, and neither is worth encoding.

## Callsigns

Everything uses `NOCALL` and its SSID variants so no real callsign ends up in the repo.
By convention bare `NOCALL` is the station under test and `NOCALL-n` is whoever is on
the other end. Where a scenario needs a peer with no SSID, use `NOCAL2`.

A `to_kisstty` packet sourced from the scenario's own `mycall` is a digipeated copy of our
own traffic. kisstty already showed the message when it sent it, so the frame never reaches
the screen: it counts against the last message sent, shows up in the status bar `rpt:` field,
and is dropped. `repeats.toml` is built on that. Anywhere else, a step that sources from
`mycall` and then waits for a line to appear will wait forever.

Watch the addressee field. APRS pads it to nine characters, so `NOCALL   :` has three
significant trailing spaces and `NOCALL-15:` has none. Getting that wrong means the
message is not addressed to you and nothing will ack it. Nine is also the limit: SSIDs
stop at 15, so `NOCALL-15` is the longest an addressee can be.

## Column widths

The atari text area is `TERMINAL_WIDTH`, which is **38**, not the 40 column screen. The
two columns go to the left and right border. Any scenario that pins down where a line
wraps has to do its arithmetic against 38.

The rendered line is `SOURCE>ADDRESSEE:text`, where the addressee is trimmed at its
first space and the `:` comes from the info field. So `NOCALL-7>NOCALL:` is a 16
character prefix and an exact two line fill needs a body of `2 * 38 - 16`.

## Packet injector

`packet-injector` fires one simulated packet at a running kisstty so you can eyeball how it
renders, then exits. It shares its direwolf/audio plumbing with `scenario-runner` (the
`kisstty-harness` crate) but is otherwise independent -- there's no scenario file, no
pass/fail, just "does this look right on screen".

```
cd tests
cargo run --bin packet-injector                              # interactive menu
cargo run --bin packet-injector -- -t protocol/status/timestamped
cargo run --bin packet-injector -- -T rendering -n 5          # 5 random rendering tests
cargo run --bin packet-injector -- -l                         # list every test
```

Tests live in a `tests.toml` in each directory under `tests/packets/`. Subdirectories are
subcategories, each with their own `tests.toml`:

```toml
title = "40-column rendering"
description = "Messages sized around the 40-char wrap boundary"

[[test]]
name = "wraps-to-two-lines"
label = "Wraps to two lines"
description = "Message long enough to wrap, ending partway through line 2"
packet = "NOCALL>APZ001::NOCALL   :This message should end mid line 2!"
```

Tests list in the order they're written here, not alphabetically. A test is addressed as
`<dir>/<name>`, or by its bare name if that's unambiguous across the whole tree (`-t position`
resolves to `protocol/position`). Adding a test is a new `[[test]]` entry; adding a category
is a new directory plus its own `tests.toml`.
Categories are named by what they're for: `protocol/` by the input (what the packet *is*),
`rendering/` by the outcome (what should render), since that's what you check when you look
at the screen.

## Requirements

`direwolf` and `gen_packets` on PATH. `gen_packets` ships with direwolf.
