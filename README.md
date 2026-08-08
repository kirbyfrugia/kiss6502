# kisstty

*A dead simple terminal and packet radio app for 8-bit computers and modern PCs*

* KISS - Keep it Simple Stupid. A protocol used for APRS/Packet Radio. Also the design intent for this app.
* TTY  - A text-only terminal. Not to be confused with teletype, but there's definitely some overlap here!

## About

kisstty is meant to be a live chat app. The goal is to be able to launch it and start having contacts with other hams. Actual text conversations.

It's meant to be ephemeral. When you launch the app, it starts fresh. This is even more true with the 8-bit version, where you can't scroll backwards and see messages that have scrolled off screen.

The point is to have real, in-the-moment contacts.

This means a few things:

* I'm intentionally not including a history beyond the active session. When you exit the app, nothing is retained except your settings.
* kisstty is designed around the APRS `message` data type. Other message types are shown (in monitor mode, rust version) and logged (rust version), but not yet parsed. I may remove them entirely.
* Related to the previous bullet, the 8-bit version *only* handles `message`. All other frames are thrown away.

## APRS Protocol notes

### Tocall

APRS puts a "tocall" in the AX.25 destination field. It's a software identifier, so other stations can tell what app sent a packet.

kisstty's is `APKTY1`. `AP` is the APRS prefix, `KTY` is kisstty, and `1` is the major version. It's [registered here](https://aprsorg.github.io/aprs-deviceid-web/), so if you see `APKTY1` on the air that's this app.

### Broadcasting to CQ

Both versions address broadcast messages to `CQ`. Receiving stations read messages addressed to `ALL`, `QST` or `CQ` as a general call, and none of the three are ever acked. I considered APRS bulletins (`BLN1`, `BLN2`, ...) instead, but other software gives those special handling and I wanted to play nicely.

## APRS Usage notes

Because of platform limitations, there are some distinct differences between the rust version and the 8-bit version. You'll see some of that below, and more in each platform's own readme.

### Rust: Net mode and QSO mode

The rust version implements the concept of "modes" while in APRS, where the mode determines what messages are displayed and the addressee of any messages you send. You can switch between modes at any time. kisstty is listening for all APRS frames in the background, so when you switch modes you'll see activity that happened even while you were in another mode.

There are three main modes:

1. Net mode - shows only APRS `message` type messages and sends messages to `CQ` as the addressee.
2. Monitor mode - shows ALL APRS frame types (though most are raw, unparsed text at the moment) and sends messages to `CQ` as the addressee.
3. QSO mode - shows APRS `message` types received from the named station. Sends messages to the named station. Messages include message IDs and are acked.

### 8-bit: Messages only

The 8-bit version does not implement Net and QSO modes while talking APRS, due to memory constraints. Instead, it shows all APRS messages in one scrolling window with your station highlighted with inverted text. You can set the addressee (or CQ broadcast) with the `/tx` command. See [README-ATARI.md](README-ATARI.md#aprs-mode) for more details.

## Terminal Usage notes

The 8-bit version also implements a raw serial terminal. See [README-ATARI.md](README-ATARI.md#terminal-mode) for more details.

## Why I built this

This started as a project to build a terminal/aprs/rtty app for 8-bit computers. Mainly as a way for me to have conversations with my dad over packet radio because we're at a weird distance from each other for having voice conversations without tying up a repeater.

Plus, I love writing 6502 assembly. Yeah, I'm weird.

But I realized this might be useful for other people who want to have ragchews with other folks but maybe are shy to use the mic. Most of those people probably aren't into retro computers like I am. But I wanted a dead simple application that just did this specific thing. So I built a terminal-based app using rust, too. Partly because I also wanted to learn rust.

## Target platforms and status

* Atari 800. Pretty much complete as a usable basic standard terminal and APRS app.
* Linux and Windows. Pretty much complete as an APRS app.
* Apple II. At the "hello world" stage. We'll see if I have the energy.
* Commodore 64. See previous bullet.

## Docs

* [README-ATARI.md](README-ATARI.md) - the Atari 800 build.
* [README-RUST.md](README-RUST.md) - the Linux/Windows build.
* [tests/README.md](tests/README.md) - an app that can be used to help test kisstty by manually piping messages through a real direwolf instance and listening for responses. Unlike the rest of kisstty, this one was vibe-coded and I take no responsibility for the code, lol.

## Use of open source

Special thanks to:

* [fredlcore](https://github.com/fredlcore) for [AtariWozmon](https://github.com/fredlcore/AtariWozMon). Also, all the people he thanked in his repo.
* Andrew Jacobs for the [binary to BCD code](https://6502.org/source/integers/hex2dec-more.htm) 
* Bruce Clark for [mem move](https://6502.org/source/general/memory_move.html)
* Paul Guertin for [CRC-16 CCITT version](https://6502.org/source/integers/crc.htm)
* Leo Nechaev for [Fast Multiply by 10](https://6502.org/source/integers/fastx10.htm)

## Use of AI (and not!)

I'm old school-ish and I wanted to learn the way I used to learn and to code the way I used to code: by reading a ton of books, copying code and tweaking it, getting my hands dirty. Just building until I understood things reasonably deeply.

That's how I approached this project. However, I'm also aware of the advantages of AI, so I used it in a few ways as indicated below.

Here's what I did myself:

* I wrote *almost all* the 6502 assembly code.
* I wrote *most (like 80% if I were to guess)* of the rust code myself, very much as a learning exercise.
* I did all the architecture myself.
* I designed the user experience and UIs myself.
* I bought and read several books, read tons of online content, etc.

Here's where I used AI:

* OCR. Specifically, I wrote code that dumped memory to my screen and I took a photo with my phone. I had Claude convert that to text for a file on my PC.
* I copied and pasted the keycode to ATASCII lookup table from the Atari OS User's manual and had Claude turn that into a lookup table for me.
* I used it to update some of the instructions in the readme files.
* I used it to write some of the helper scripts like `run-atari.sh` and most of the rust unit tests.
* I vibe-coded the manual scenario runner.
* I used it for some *non-logic-changing* refactors, like bulk renaming things or moving functionality from one file to another. I kept the prompts very narrow on these.

## License

kisstty is licensed under the MIT License — see [LICENSE](LICENSE).

Third-party code incorporated into this project is credited in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
