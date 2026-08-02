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
* kisstty is designed around the APRS `message` data type. Other message types are ignored, but logged to the logfile for the rust version.
* Related to the previous bullet, the 8-bit version will ONLY be for message (and status) types.

## Protocol / Usage notes

kisstty has the concept of "net mode" (broadcast) and "qso mode" (conversations)
for APRS `message` types.

In net mode, it addresses all messages to `CQ`. Receiving stations read messages
addressed to `ALL`, `QST` or `CQ` as a general call, and none of the three are
ever acked. I considered APRS bulletins (`BLN1`, `BLN2`, ...) instead, but other
software gives those special handling. They get sorted onto a separate bulletins
page rather than showing up in the normal message flow.

You switch modes by entering:
```
# for net mode:
/net

# for qso mode:
/qso <callsign>

```

## Background

This started as a project to build a terminal/aprs/rtty app for 8-bit computers.
Also as a way for me to have conversations with my dad over packet radio because we're
at a weird distance from each other for having voice conversations.

This program is still that, and I almost have that part fully working for the Atari 800.

But what I realized was that what I really wanted was a way have real conversations. With people.
Ok, not voice conversations, but text conversations at least. I think some software exists out there,
but I want this to be as dead simple as possible. No realtime maps, not fancy features. Just a simple
text interface that will work in a broadcast/monitor mode and a QSO mode.

Basically, a purpose-built app to trade messages with people and a community.
Kinda like IRC or discord, but over the air and even simpler.

Target platforms in order:
* Atari 800 (in active development). Can be used already as a standard terminal and with basic KISS message mode (rx).
* Linux and Windows (next). Will be built in rust.
* Apple II
* Commodore 64

## Status

The Atari version is far enough along that you can use it as a standard terminal. KISS/APRS in progress.

The rust version is fairly functional now. You can send and receive messages. It still has some
ugly UI stuff that isn't functional yet like the sidebar.

## Docs

Each platform-specific version has its own readme that tells you how to build, run, and debug it.

## Use of open source

Special thanks to:
* [fredlcore](https://github.com/fredlcore) for [AtariWozmon](https://github.com/fredlcore/AtariWozMon). Also, all the people he thanked in his repo.
* Andrew Jacobs for the [binary to BCD code](https://6502.org/source/integers/hex2dec-more.htm) 
* Bruce Clark for [mem move](https://6502.org/source/general/memory_move.html)

## Use of AI (and not!)

I'm old school-ish and I wanted to learn the way I used to learn and code the way I used to code: by reading a ton of books, copying code and tweaking it, getting my hands dirty. Just building until I understood things reasonably deeply.

That's how I approached this project. However, I'm also aware of the advantages of AI, so I used it in a few ways as indicated below.

Here's what I did:
* I wrote *all* the 6502 assembly code.
* I wrote *most* of the rust code myself, very much as a learning exercise.
* I did all the architecture myself.
* I designed the user experience and UIs myself.
* I bought and read several books, read tons of online content, etc.

Here's where I used AI:
* OCR. Specifically, I wrote code that dumped memory to my screen and I took a photo with my phone. I had Claude convert that to text for a file on my PC.
* I copied and pasted the keycode to ATASCII lookup table from the Atari OS User's manual and had Claude turn that into a lookup table for me.
* I used it to tweak some of the instructions in my readme files, though I mostly wrote them. It's just a pain in the butt and I don't care if AI does it.
* It wrote some of the helper scripts like `run-atari.sh` since I wanted to focus on the actual program code.
* It did some non-logic-changing refactors, like renaming things. Boring toil work vs thinking work. I directed it in exactly what to do.
* I asked it questions sometimes whent I banged my head on the wall a dozen times first.
* I had claude write some unit tests and some docs for my rust app.

## License

kisstty is licensed under the MIT License — see [LICENSE](LICENSE).

Third-party code incorporated into this project is credited in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
