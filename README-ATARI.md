This readme has two sections. The top is a user's guide if you just want to use kisstty on a physical Atari 800. The bottom of the document is for folks who want to build and test it, or who want to run it in an emulator instead.

# User's guide

kisstty is a terminal program for Atari 8-bits that speaks KISS to a TNC, for APRS messaging over packet radio. It also works as a plain raw terminal program.

## Requirements

* Hardware: An Atari 850 is currently required, though I may add support for other setups later.
* RAM: The built binary is around 16kB and loads at $4000.

## Running

You can save the atr file to a floppy or load it with something like fujinet. Either way, once you boot up it will autorun. The atr image is a DOS 2.5 image.

## The config screen

kisstty starts on a config screen with five tabs: File, Session, Serial, Term, and APRS. TAB and Shift+TAB move focus between fields, ctrl+up/down cycles through a selected field's value, and START launches the terminal. ESC cancels back out of the screen, but only once you've started successfully at least once.

The tabs:

* File covers loading and saving your config.
* Session picks the app mode, either Terminal or APRS for now. RTTY and others may come later.
* Serial covers the usual RS-232 settings, like baud, stop bits, and parity.
* Term and APRS represent two different protocols when you start. More below.

The defaults get you a basic 9600 baud terminal in Terminal mode.

## Terminal mode

This is a plain raw terminal. Whatever you type goes out, whatever comes in gets printed.

You can choose between Line Mode or Char Mode. In Line Mode, nothing gets sent until you press `return`, at which time the whole line is sent. In Char mode, each character is sent as you type it.

Outgoing lines are capped at 80 characters plus the line ending. You can also change the line ending (CR, LF, CR+LF, or ATASCII) that gets sent when you hit `return` (in either mode).

Incoming lines are read leniently, i.e. any line ending is accepted regardless of what you have configured.

You can use Terminal mode as a standard terminal program for any purpose. However, it might also be necessary to use terminal mode to configure your TNC. For example, some require you to send native commands like `KISS ON` to even turn on KISS mode. In that case, you probably want to start in terminal mode, send your commands, and then switch to APRS mode. Note: if you're doing that, you might want to save a file per mode.

## APRS mode

APRS mode is meant to be used as an APRS messaging app. It only handles the APRS `message` type.

APRS mode is line mode only. Type a line and hit `return` to send it as an APRS message to the addressee noted in the status bar, which defaults to a `CQ` broadcast.

* `/TX CALLSIGN` sets the addressee
* `/TX` with no arguments switches back to broadcast. Lines cap at 67 characters, the APRS limit.
* Note: commands are not case sensitive.

Messages you send get a 4-character ID shown as `#XXXX`. Broadcasts don't get an ID since they are not acked. Message IDs start at `0001` and count upwards (in hexadecimal) until they wrap. When your messages are acked, kisstty shows an ack indicator on the status bar. It currently does not retry any messages.

When your messages are repeated, kisstty shows a repeat count. See 'Reading the status bar' below. Repeated copies of the same packet (e.g. from a digipeater hop) are deduped so you only see them once.

kisstty acks anything addressed to your configured station (matching on CALLSIGN and SSID). It will not re-send acks for repeated messages unless >30 seconds have passed since the last ack it sent for that message. It identifies duplicate messages using a crc of the source, the dest, and the message contents.

## Connecting to a TNC

If you're using kisstty for packet radio, you'll need a TNC. Some TNCs like [direwolf](https://github.com/wb2osz/direwolf) run on a modern computer and are configured through a text-based config file. For direwolf, you'll need to point its `SERIALKISS` setting at whatever serial port your 850 is connected to.

kisstty only speaks KISS rather than any TNC's native protocol, so your TNC has to support KISS mode. Most modern ones do. You could use Terminal mode for your native protocol if it's raw text, or you could make a PR to add another mode to kisstty.

Older hardware TNCs, like an AEA PK-232 (which I have), need to be put into KISS mode from their own command mode first. You can do this in Terminal mode if needed.

`/TNC` sends the TX delay, persistence, slot time, TX tail and duplex settings from the APRS tab to the TNC. It was an intentional choice to have you send these as a command rather than having kisstty own the settings since you may have a different source of truth for these settings (e.g. config files).

## Reading the status bar

The bar along the bottom shows your current addressee (`tx:`), the repeat count on the last sent frame (`rpt:`), whether your last message (if it was a directed QSO-type message) has been acked (`ack:`, `_` pending and `+` acked), and the port status (`st:`) on the right:

| Status   | Meaning                               |
| -------- | ------------------------------------- |
| `OK`     | port open and working                 |
| `...`    | opening                               |
| `!850`   | no 850 found                          |
| `!-R:`   | the R: handler isn't in HATABS        |
| `!TO`    | timeout                               |
| a number | anything else, the raw CIO error code |

If you encounter errors, hit `SELECT` to go to the config menu, then `START`. This will close and reopen the port again. If you encounter errors, please report them since I put a lot of work into getting the 850 code to work reliably.

## Known limitations

* An Atari 850 is the only supported serial device for now.
* There's no scrollback. Shift+Clear wipes the text area if it gets cluttered.

------

Everything below here is for developer's wanting to work on kisstty to make it better.

------

# Building kisstty

## Pre-reqs

Requires a current cc65. Old distro packages (e.g. Ubuntu's cc65 2.18) fail with
`No such scope: 'TextArea'`, so build from source and install with `PREFIX=/usr`:

```
git clone https://github.com/cc65/cc65
cd cc65 && make && sudo make install PREFIX=/usr
```

You also need `dir2atr` on your PATH to package the xex into a bootable atr:

```
git clone https://github.com/HiassofT/AtariSIO
cd AtariSIO/tools && make dir2atr && sudo cp dir2atr /usr/local/bin/
```

You will need to find copies of DOS 2.5's `DOS.SYS`/`DUP.SYS` and copy them
to `3rdparty/atari/dos25`.

## Building

```
# to build the release
make atari

# to build the debug mode with wozmon built in
make atari-debug
```
This will create an xex file and an atr file in `build/atari/<dist>`.


# Running kisstty

You can run kisstty on a real Atari or in the Altirra emulator.

## On a real Atari

```
# Just boot the atr and it will run automatically. I load it in fujinet or from a floppy.
#
# Typically, you need to turn on your Atari 850 first. That's recommended. However, since
# I added bootstrapping code to kisstty, you don't have to. You can turn it off and on again
# and reconnect. But you may need to go to the config screen and start again to reopen the port.
```

## Altirra (under Bottles/Wine)

```
# One-time setup:
# 1. Install Bottles, create a bottle named "altirra" (or set ALTIRRA_BOTTLE)
# 2. Install Altirra into the bottle
# 3. Allow the sandbox to read your home dir (do this at your own risk since this isn't recommended!):
flatpak override --user com.usebottles.bottles --filesystem=home

# 4. Get the 850 firmware and save it two directories up from Altirra64.exe:
#    https://github.com/ascrnet/FW-Altirra/raw/refs/heads/main/Automatic/850.rom
#    -> .altirra-firmware/850.rom
#     (or edit the firmware path in platform/atari/altirra/Altirra.ini.template if you'd rather put it elsewhere)

# 5. Point at Altirra inside the bottle, e.g.:
export ALTIRRA_EXE="$HOME/Applications/Altirra-4.40/Altirra64.exe"

# Usage:
./run-atari.sh debug      # build/atari/debug/kisstty.atr
./run-atari.sh release    # build/atari/release/kisstty.atr
```

run-atari.sh generates `platform/atari/altirra/Altirra.ini` from
`Altirra.ini.template` on first run, resolving the checkout path. Delete it to
regenerate.

### Talking to the emulated 850 over TCP

```
# Altirra's networked serial port (on the 850) must be set to "Listen for an incoming connection" on port 9000
#
# Start kisstty in Altirra first, otherwise socat has nothing to connect to.
socat -d -d PTY,link=/tmp/altirra-tty,raw,echo=0 TCP:127.0.0.1:9000
minicom -D /tmp/altirra-tty
# Make sure your minicom settings match your kisstty settings
```

# Debugging

I ported [AtariWozmon](https://github.com/fredlcore/AtariWozMon) to ca65 syntax. To use:
```
# Make a debug release that will run either on your Atari or in an emulator
make clean && make atari-debug

# Running on a real atari
Just load the atr and boot

# Running in Altirra
./run-atari.sh debug

# You'll land in wozmon. You can execute the main app by:
4000R

# To re-enter wozmon on brk, simply add brk to your code, e.g.
lda #42
...
brk     ; re-enters wozmon

```

# Connecting to direwolf

kisstty talks KISS to direwolf over a serial link. The use cases below differ
only in where the Atari/Altirra and direwolf live, and how the serial link
between them is made.

For the cross-machine cases (1 and 3), `kissutil` (ships with direwolf) can be
used to test without a radio.

## Use case 1: Physical Atari, direwolf on a separate box

```
# Atari 800 + 850, serial cable from the 850 to a serial port on the
# box running direwolf.

# Note: my main serial port is configured as /dev/COM1, but replace
#       it with whatever yours is in all the instructions below.

# Put this in ~/.config/direwolf/direwolf.conf:
KISSPORT 8001
SERIALKISS /dev/COM1 9600    # the box's serial port connected to the 850

# Launch direwolf:
direwolf -c ~/.config/direwolf/direwolf.conf -t 0

# Boot the Atari (kisstty runs automatically) and start APRS mode.

# (optional) test receive using kissutil.
# Stop direwolf first so it isn't holding the port. Then:
kissutil -v -p /dev/COM1 -s 9600

# Then type this. kisstty only renders the APRS message data type, so it has to
# be a message, and the addressee is padded to 9 chars and must match the
# callsign you configured:
NOCALL-7>APKTY1::NOCALL   :this is a test
```

## Use case 2: Altirra and direwolf on the same machine

```
# Run kisstty in Altirra and start APRS mode. This opens the 850 serial
# port so Altirra starts listening on TCP 9000. Do this BEFORE socat
# or it has nothing to connect to.

# Bridge Altirra's TCP serial to a PTY:
socat -d -d PTY,link=/tmp/altirra-tty,raw,echo=0 TCP:127.0.0.1:9000

# Put this in ~/.config/direwolf/direwolf.conf:
KISSPORT 8001
SERIALKISS /tmp/altirra-tty 9600

# Launch direwolf:
direwolf -c ~/.config/direwolf/direwolf.conf -t 0

# (optional) test receive using kissutil.
# Stop direwolf first so it isn't holding the PTY. Then:
kissutil -v -p /tmp/altirra-tty -s 9600
# Then type this. See the note in use case 1 about the message format:
NOCALL-7>APKTY1::NOCALL   :this is a test
```

## Use case 3: Altirra connected by serial to a separate direwolf box

Altirra's emulated 850 serial (TCP 9000) goes out a physical serial port
on the host machine and over a cable to the direwolf box.

```
# --- on the Altirra machine ---

# Run kisstty in Altirra and start APRS mode. This opens the 850 serial
# port so Altirra starts listening on TCP 9000. Do this BEFORE socat
# or it has nothing to connect to.

# Bridge TCP 9000 to the physical serial port wired to the other box.
# Replace /dev/COM2 with your serial port:
# Note: my secondary port is configured as /dev/COM2
socat -d -d TCP:127.0.0.1:9000 /dev/COM2,raw,echo=0,b9600,cs8,parenb=0,cstopb=0,crtscts=0,clocal=1

# --- on the direwolf box ---

# Put this in ~/.config/direwolf/direwolf.conf:
KISSPORT 8001
SERIALKISS /dev/COM1 9600  # this box's end of the serial cable

# Launch direwolf:
direwolf -c ~/.config/direwolf/direwolf.conf -t 0

# (optional) test receive.
# On the Altirra machine, stop socat, leave kisstty running, and inject
# straight at Altirra's serial:
kissutil -v -p 9000

# Then type this. See the note in use case 1 about the message format:
NOCALL-7>APKTY1::NOCALL   :this is a test
```

Note: the Altirra use cases assume Linux under Bottles/Wine. A native PC
should work but I haven't tested it, so you'll have to figure out the
serial bridging yourself. If you do, make a PR with instructions and
I'll merge it.

# Interesting Atari notes.

## Atari 850 bootstrapping

I had to figure out how to boot the Atari 850 from my code, which was hard and interesting. So I'm documenting it here.

My implementation was based off of what is described in the Altirra Hardware Reference Manual (pages 251 to 252). It basically works like this:

1. Send poll command ($3f) to Atari 850 ($50)
2. Grab the response and shove it into the DCB. Call SIOV.
3. Call $0506 to load, relocate, and intialize the handler at MEMLO.

But it wasn't working for me. At least, I wasn't seeing the R: handler loaded in HATABS. So I did a dump of both the relocator and the handler, which you can find in the 3rdparty/atari/atari850 directory.

I was getting valid responses to each of the commands. I could see that Step 2 was sending command $21 (load) then $26 (load peripheral handler) then $53 (status) which seemed to map nicely to what was supposed to happen according to the Altirra docs. However, the R: handler was not showing up in HATABS.

I searched the code for any pointers to `$031a` (HATABS). There was a loop in the code that looked for an empty slot in HATABS. Nothing else in the loader or handler seemed to be calling it. So I just made a call directly to that routine at `$0ab3` after the bootstrapping sequence, and the R: device showed up in HATABS!

That worked, but only because of where MEMLO happened to be at the time. The `$0506` loader relocates the handler to MEMLO, and that HATABS-install routine relocates right along with it. On the DOS I was using, MEMLO sat at `$0700`, so the routine landed at `$0ab3`. Switch to a different DOS and MEMLO moves, so `$0ab3` points into the middle of something else and you crash. The routine actually lives at MEMLO + `$03b3`, so instead of hard-coding the address I now compute it from the current MEMLO and call that. It works wherever MEMLO ends up.

Where it still might fail:

* This was built to work with a rom dump from my actual 850. According to the Altirra manual, there are different ROM revisions. I think mine is the common one. My code should work on all revisions for the most part, with the exception that I hard-coded the offset to the HATABS-install routine (MEMLO + `$03b3`). Computing it from MEMLO means it survives a different DOS, but the offset itself is still a known location in my ROM revision. Yours *might* differ but I have no way of knowing.
* I have two SIO2PCs. One of them seems to have a conflict with the Atari 850 when trying to bootstrap the R: handler. I never figured out why, but maybe one of them was driving the bus weirdly. If you hit this issue, try booting with your SIO2PC and then unplugging it before trying to load the R: handler. i.e. before opening the terminal.

# Resources:
* [Mapping the Atari](https://www.atariarchives.org/mapping/) - amazing book documenting every memory location in the Atari.
* [Altirra Hardware Reference Manual](https://www.virtualdub.org/downloads/Altirra%20Hardware%20Reference%20Manual.pdf) - very helpful regarding the Atari 850 bootstrapping process and serial comms.
* [Assembly Language Programming for the Atari Computers](https://www.atariarchives.org/alp/index.php)
* [De Re Atari](https://www.atariarchives.org/dere/index.php)
* [Atari Wiki CIOV Tutorial](https://atariwiki.org/wiki/Wiki.jsp?page=CIOV%20Tutorial)
