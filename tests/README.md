# kisstty scenario tests

> [!NOTE]
> Unlike the main app, this test program was vibe-coded by claude, guided by me.

Manual-with-assist tests. A scenario drives a live direwolf, injects real 1200 baud
packets, and walks you through checking what the app under test does with them.

## Running one

```
cargo run -p scenario-runner -- tests/scenarios/atari/acks.toml
```

Start Altirra, kisstty, and socat first, and let the scenario's opening prompt tell
you which callsign to configure. The runner starts direwolf itself and stops it on the
way out, so do not have one already running. It refuses to start if port 8001 is taken.

An optional second argument overrides the scenario's serial device. Pass `''` for TCP
KISS only.

## Scenarios are per platform

`tests/scenarios/<platform>/` and the `platform` field inside each file have to agree,
and `cargo test -p scenario-runner` enforces it.

This matters because the `see` lines describe one platform's screen. The atari scenarios
assume the 40 column display, its `SOURCE>ADDRESSEE:text#id` line format, and its `/tx`
command, so they mean nothing against the rust build. The runner itself is platform
neutral: it only knows about direwolf, packets, and prompting you.

## Writing one

```toml
name = "acks"
platform = "atari"
serial = "/tmp/altirra-tty"   # omit for tcp kiss only
mycall = "NOCALL"

[[step]]
to_kisstty   = "NOCALL-7>APKTY1,WIDE1-1,WIDE2-1::NOCALL   :Test message{0001"
see          = "NOCALL-7>NOCALL:Test message#0001"
from_kisstty = "::NOCALL-7 :ack0001"
```

Direction is always named from both ends, so there is no perspective to guess at.

| verb | what it does |
|---|---|
| `to_kisstty` | a TNC2 packet, or a list of them, to put on the air for kisstty to receive |
| `from_kisstty` | substring the direwolf log must contain, polled for 5s. **checked automatically** |
| `see` | what should be on screen. answer `y`, `n` or `q` |
| `do` | something for you to do, like sending a message. Enter when done, `q` to quit |
| `wait` | seconds to sleep, for crossing the 30s dedup window |
| `random` | send a message from the built in corpus instead of a literal `to_kisstty` |
| `repeat` | how many times to inject. `0` runs until you interrupt it, so put nothing after it |
| `every` | seconds between repeats, default 1 |

`see`, `from_kisstty` and `to_kisstty` all take a string or a list of strings.

Word a `do` step for the moment it is read, not for what happens next. The runner is
blocked waiting for you, so "watch for X" before the traffic starts leaves you waiting
for the runner while it waits for you. Say what pressing Enter will do.

A list of packets goes out back to back with no prompt between them, which is how a
scenario stays inside a timing window. `dedup.toml` needs its duplicates inside one 30
second window, and a prompt between each would let the window expire while you type. Put
the whole group in one `to_kisstty` list and check the result once at the end.

`repeat` and `every` apply to `to_kisstty` and `random` alike, which is how `soak.toml` runs
indefinitely until you ctrl-c out of it.

Only `from_kisstty` can fail on its own, because the runner cannot see the atari screen.
For `see`
you are the check: `y` passes, `n` records a failure and carries on, `q` stops the run.
Enter is the same as `y`.

A scenario exits non-zero if anything failed or if you quit early, and prints what went
wrong at the end. Quitting counts as not passing, since the remaining steps never ran.

Write `from_kisstty` as the shortest substring that pins the frame down. Matching on the whole
TNC2 line means reproducing direwolf's monitor prefix and whatever digipeater path is in
your config, and neither is worth encoding.

## Callsigns

Everything uses `NOCALL` and its SSID variants so no real callsign ends up in the repo.
By convention bare `NOCALL` is the station under test and `NOCALL-n` is whoever is on
the other end. Where a scenario needs a peer with no SSID, use `NOCAL2`.

**Never source a `to_kisstty` packet from the scenario's own `mycall`.** kisstty drops frames
whose source is its own callsign, because it already showed them when it sent them, so
such a step silently displays nothing and looks like a rendering bug.

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

## Requirements

`direwolf` and `gen_packets` on PATH. `gen_packets` ships with direwolf.
