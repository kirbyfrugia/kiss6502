# kisstty - Atari

## Building kisstty

```
# to build the release
make atari

# to build the debug mode with wozmon built in
make atari-debug
```
This will create an xex file and an atr file in `build/atari/<dist>`.

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

## Running kisstty

You can run kisstty on a real Atari or in Altirra.

### On a real Atari

```
# Just boot the atr and it will run automatically. I load it in fujinet.
# Note: turn on your Atari 850 first. You don't have to do that
#       since I added bootstrapping code, but if you don't
#       you'll need to turn it off and back on again and reconnect.
```

### Altirra (under Bottles/Wine)

```
# One-time setup:
# 1. Install Bottles, create a bottle named "altirra" (or set ALTIRRA_BOTTLE)
# 2. Install Altirra into the bottle
# 3. Allow the sandbox to read your home dir:
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
regenerate (e.g. after moving the checkout).

#### Talking to the emulated 850 over TCP

```
# Altirra's networked serial port (on the 850) must be set to "Listen for an incoming connection" on port 9000
#
# Start kisstty in Altirra and open the connection first. Altirra only
# starts listening on 9000 once the 850 serial port is opened, so socat
# has nothing to connect to otherwise.
socat -d -d PTY,link=/tmp/altirra-tty,raw,echo=0 TCP:127.0.0.1:9000
minicom -D /tmp/altirra-tty
# Make sure your minicom settings match your kisstty settings
```

## Debugging

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

## Connecting to direwolf

kisstty talks KISS to direwolf over a serial link. The use cases below differ
only in where the Atari/Altirra and direwolf live, and how the serial link
between them is made.

To test without a radio, the scenario runner starts its own direwolf, injects real
packets, and walks you through what should show up on screen (use case 2). See
[tests/README.md](tests/README.md). For the cross-machine cases (1 and 3), `kissutil`
(ships with direwolf) can be used, too.

### Use case 1: Physical Atari, direwolf on a separate box

```
# Atari 800 + 850, serial cable from the 850 to a serial port on the
# box running direwolf.

# Note: my main serial port is configured as /dev/COM1, but replace
#       it with whatever yours is in all the instructions below.

# Put this in ~/.config/direwolf/direwolf.conf:
KISSPORT 8001
SERIALKISS /dev/COM1 9600    # the box's serial port wired to the 850

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

### Use case 2: Altirra and direwolf on the same machine

The scenario runner handles the direwolf side: it fills SERIALKISS in
`tests/direwolf.conf.template` with the PTY from the scenario's `serial` field
(default `/tmp/altirra-tty`), runs direwolf for the length of the run, and injects
packets over that serial KISS link. They flow PTY -> socat -> TCP 9000 -> Altirra's
850 -> kisstty.

```
# Run kisstty in Altirra and start APRS mode. This opens the 850 serial
# port so Altirra starts listening on TCP 9000. Do this BEFORE socat
# or it has nothing to connect to.

# Bridge Altirra's TCP serial to the PTY direwolf writes to (the default
# serial device in the atari scenarios):
socat -d -d PTY,link=/tmp/altirra-tty,raw,echo=0 TCP:127.0.0.1:9000

# Run a scenario:
cargo run -p scenario-runner -- tests/scenarios/atari/rendering.toml
```

The runner starts and stops direwolf itself, so don't have one already running. It
refuses to start if anything is already listening on port 8001.

For ongoing two-way APRS rather than a scenario, run a persistent direwolf against the
same PTY, with a config containing `KISSPORT 8001` and
`SERIALKISS /tmp/altirra-tty 9600`:

```
direwolf -c ~/.config/direwolf/direwolf.conf -t 0
```

### Use case 3: Altirra connected by serial to a separate direwolf box

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

## Resources:
* [Mapping the Atari](https://www.atariarchives.org/mapping/) - amazing book documenting every memory location in the Atari.
* [Altirra Hardware Reference Manual](https://www.virtualdub.org/downloads/Altirra%20Hardware%20Reference%20Manual.pdf) - very helpful regarding the Atari 850 bootstrapping process and serial comms.
* [Assembly Language Programming for the Atari Computers](https://www.atariarchives.org/alp/index.php)
* [De Re Atari](https://www.atariarchives.org/dere/index.php)
* [Atari Wiki CIOV Tutorial](https://atariwiki.org/wiki/Wiki.jsp?page=CIOV%20Tutorial)

# Use of open source

Special thanks to:
* [fredlcore](https://github.com/fredlcore) for [AtariWozmon](https://github.com/fredlcore/AtariWozMon). Also, all the people he thanked in his repo.
