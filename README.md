# kisstty

*A dead simple terminal and packet radio app for 8-bit computers and modern PCs*

* KISS - Keep it Simple Stupid. A protocol used for APRS/Packet Radio. Also the design intent for this app.
* TTY  - A text-only terminal. Not to be confused with teletype, but there's definitely some overlap here!

## About

kisstty is meant to be a live chat app. The goal is to be able to launch
it and start having contacts with other hams. Actual text conversations.

It's meant to be ephemeral. When you launch the app, it starts fresh.
This is even more true with the 8-bit version, where you can't scroll
backwards and see messages that have scrolled off screen.

The point is to have real, in-the-moment contacts.

This means a few things:
* I'm intentionally not including a history beyond the active session. When you exit the app, nothing is retained except your settings.
* kisstty is designed around the APRS `message` data type. Other message types are shown (in monitor mode, rust version) and logged (rust version), but not yet parsed. I may remove them entirely.
* Related to the previous bullet, the 8-bit version only handles `message` right now. All other frames are thrown away.

## Protocol / Usage notes

### Versions

Because of platform limitations, there are some distinct differences between
the rust version and the 8-bit version. You'll see some of that below.

### Tocall

APRS puts a "tocall" in the AX.25 destination field. It's a software identifier,
so other stations can tell what app sent a packet.

kisstty's is `APKTY1`. `AP` is the APRS prefix, `KTY` is kisstty, and `1` is the major
version. It's registered, so if you see `APKTY1` on the air that's this app.

### Broadcasting to CQ

Both versions address broadcast messages to `CQ`. Receiving stations read messages
addressed to `ALL`, `QST` or `CQ` as a general call, and none of the three are
ever acked. I considered APRS bulletins (`BLN1`, `BLN2`, ...) instead, but other
software gives those special handling and I wanted to play nicely.

### Net mode and qso mode (rust only)

In the rust version these are real modes. They change what you send and what you see:

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

The atari version has no modes. It always shows every message (APRS `message` type
it decodes, whether or not it's addressed to you, and there's no way to filter. `/tx` picks who
your next messages will go to:

```
/tx               # send subsequent messages to CQ
/tx <callsign>    # send subsequent messaages to <callsign>
/h                # help
```

There's no `/config` on the atari. Hit `SELECT` to enter the config screen.

## Background

This started as a project to build a terminal/aprs/rtty app for 8-bit computers.
Also as a way for me to have conversations with my dad over packet radio because we're
at a weird distance from each other for having voice conversations.

This program is still that, and I almost have that part fully working for the Atari 800.

But what I realized was that I really wanted a way have real conversations. With people.
Ok, not voice conversations, but text conversations at least. I think some software exists out there,
but I wanted this to be as dead simple as possible. No realtime maps, not fancy features. Just a simple
text interface that will work in a broadcast/monitor mode and a QSO mode.

Basically, a purpose-built app to trade messages with people and a community.
Kinda like IRC or discord, but over the air and even simpler.

Target platforms in order:
* Atari 800 (in active development). Works as a standard terminal, and sends and receives APRS messages.
* Linux and Windows (next). Will be built in rust.
* Apple II
* Commodore 64

## Status

Both versions send and receive APRS messages.

The atari version handles `message` and drops everything else. It dedups messages
and deals with acks appropriately, too. What it doesn't have is any of the extra
rust modes, scrollback, or a session log. But I'd say it's nearly complete since
I probably won't do any of that stuff given the system constraints.

The rust version is nearly complete now.

Apple and C64 are TODO. I may get to them, I may not. The code has modules that
could reasonably be made 6502-machine agnostic, but there's definitely some
atari-specific stuff blended in. I don't think it would be massive effort and
claude could probably be used to split out any atari-specific stuff from the abstract.

## Docs

Each platform-specific version has its own readme that tells you how to build, run, and debug it.

There's no automated test for the atari build, so [tests/README.md](tests/README.md) covers
the scenario tests instead. They drive a real direwolf, inject real packets, and walk you
through checking what shows up on screen.

## Use of open source

Special thanks to:
* [fredlcore](https://github.com/fredlcore) for [AtariWozmon](https://github.com/fredlcore/AtariWozMon). Also, all the people he thanked in his repo.
* Andrew Jacobs for the [binary to BCD code](https://6502.org/source/integers/hex2dec-more.htm) 
* Bruce Clark for [mem move](https://6502.org/source/general/memory_move.html)
* Paul Guertin for [CRC-16 CCITT version](https://6502.org/source/integers/crc.htm)

## Use of AI (and not!)

I'm old school-ish and I wanted to learn the way I used to learn and code the way I used to code: by reading a ton of books, copying code and tweaking it, getting my hands dirty. Just building until I understood things reasonably deeply.

That's how I approached this project. However, I'm also aware of the advantages of AI, so I used it in a few ways as indicated below.

Here's what I did myself:
* I wrote *almost all* the 6502 assembly code.
* I wrote *most* of the rust code myself, very much as a learning exercise.
* I did all the architecture myself.
* I designed the user experience and UIs myself.
* I bought and read several books, read tons of online content, etc.

Here's where I used AI:
* OCR. Specifically, I wrote code that dumped memory to my screen and I took a photo with my phone. I had Claude convert that to text for a file on my PC.
* I copied and pasted the keycode to ATASCII lookup table from the Atari OS User's manual and had Claude turn that into a lookup table for me.
* I used it to update some of the instructions in my readme files.
* It wrote some of the helper scripts like `run-atari.sh`
* It did some non-logic-changing refactors, like renaming things.
* I asked it questions sometimes after banging my head on the wall a dozen times first.
* It wrote most of the unit tests and the manual scenario runner.

## License

kisstty is licensed under the MIT License — see [LICENSE](LICENSE).

Third-party code incorporated into this project is credited in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
