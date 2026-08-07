# =============================================================================
# kisstty - cross-platform 6502 KISS TNC client
# Tools:   ca65 + ld65 from cc65 package
#
# pre-req on CachyOS/Arch:
#   paru -S cc65-git vice applecommander dir2atr
#
# =============================================================================

CA65           = ca65
LD65           = ld65
AC             = applecommander-ac
ACX            = applecommander-acx
SRCDIR         = platform
BLDDIR         = build
3RDPARTYDIR    = 3rdparty
CC65_SHARE    ?= /usr/share/cc65
CA65INC        = $(CC65_SHARE)/asminc
CA65FLAGS      = -g
CA65FLAGS_DBG  = -D DEBUG -g

# =============================================================================
# ATARI
# =============================================================================
ATARI_DIR       = $(SRCDIR)/atari
ATARI_3RDPARTY  = $(3RDPARTYDIR)/atari
ATARI_DOS_DIR  ?= $(ATARI_3RDPARTY)/dos25
ATARI_CFG       = $(SRCDIR)/atari/config/atari-asm-xex-release.cfg
ATARI_CFG_DBG   = $(SRCDIR)/atari/config/atari-asm-xex-debug.cfg
ATARI_SRCS      = main.s \
		  boot850.s \
		  config.s \
		  crc.s \
		  file.s \
		  form.s \
		  globals.s \
		  kbd.s \
		  line_input.s \
		  memmove.s \
		  protocol_kiss.s \
		  screen.s \
		  term.s \
		  term_output.s \
		  rs232.s \
		  utils.s \
		  version.s \
		  wozmon.s

ATARI_INCS     = $(wildcard $(ATARI_DIR)/*.inc)

ATARI_BLDDIR   = $(BLDDIR)/atari/release
ATARI_ATR_DIR  = $(ATARI_BLDDIR)/atr
ATARI_XEX      = $(ATARI_BLDDIR)/kisstty.xex
ATARI_MAP      = $(ATARI_BLDDIR)/kisstty.map
ATARI_VICE_SYM = $(ATARI_BLDDIR)/kisstty-vice-symbols.txt
ATARI_ATR      = $(ATARI_BLDDIR)/kisstty.atr
ATARI_OBJS     = $(patsubst %.s,$(ATARI_BLDDIR)/%.o,$(ATARI_SRCS))

ATARI_BLDDIR_DBG   = $(BLDDIR)/atari/debug
ATARI_ATR_DIR_DBG  = $(ATARI_BLDDIR_DBG)/atr
ATARI_XEX_DBG      = $(ATARI_BLDDIR_DBG)/kisstty.xex
ATARI_MAP_DBG      = $(ATARI_BLDDIR_DBG)/kisstty.map
ATARI_VICE_SYM_DBG = $(ATARI_BLDDIR_DBG)/kisstty-vice-symbols.txt
ATARI_ATR_DBG      = $(ATARI_BLDDIR_DBG)/kisstty.atr
ATARI_OBJS_DBG     = $(patsubst %.s,$(ATARI_BLDDIR_DBG)/%.o,$(ATARI_SRCS))

#PORT ?= /dev/ttyUSB0

atari: $(ATARI_ATR)
atari-debug: $(ATARI_ATR_DBG)

$(ATARI_BLDDIR) $(ATARI_ATR_DIR) $(ATARI_BLDDIR_DBG) $(ATARI_ATR_DIR_DBG):
	mkdir -p $@

$(ATARI_BLDDIR)/%.o: $(ATARI_DIR)/%.s $(ATARI_INCS) | $(ATARI_BLDDIR)
	$(CA65) --target atari -I $(CA65INC) $(CA65FLAGS) \
	    --listing $(ATARI_BLDDIR)/$*.lst -o $@ $<

$(ATARI_BLDDIR_DBG)/%.o: $(ATARI_DIR)/%.s $(ATARI_INCS) | $(ATARI_BLDDIR_DBG)
	$(CA65) --target atari -I $(CA65INC) $(CA65FLAGS_DBG) \
	    --listing $(ATARI_BLDDIR_DBG)/$*.lst -o $@ $<

$(ATARI_XEX): $(ATARI_OBJS)
	$(LD65) -vm -Ln $(ATARI_VICE_SYM) -C $(ATARI_CFG) -m $(ATARI_MAP) -o $@ $^

$(ATARI_XEX_DBG): $(ATARI_OBJS_DBG)
	$(LD65) -vm -Ln $(ATARI_VICE_SYM_DBG) -C $(ATARI_CFG_DBG) -m $(ATARI_MAP_DBG) -o $@ $^

$(ATARI_ATR): $(ATARI_XEX) | $(ATARI_ATR_DIR)
	@test -f "$(ATARI_DOS_DIR)/DOS.SYS" || { echo "Set ATARI_DOS_DIR to a dir with DOS 2.5 DOS.SYS and DUP.SYS (see $(ATARI_3RDPARTY)/dos25/README.md)"; exit 1; }
	cp $(ATARI_XEX) $(ATARI_ATR_DIR)/autorun.sys
	cp $(ATARI_DOS_DIR)/*.SYS $(ATARI_ATR_DIR)/
	dir2atr -S -b Dos25 $@ $(ATARI_ATR_DIR)

$(ATARI_ATR_DBG): $(ATARI_XEX_DBG) | $(ATARI_ATR_DIR_DBG)
	@test -f "$(ATARI_DOS_DIR)/DOS.SYS" || { echo "Set ATARI_DOS_DIR to a dir with DOS 2.5 DOS.SYS and DUP.SYS (see $(ATARI_3RDPARTY)/dos25/README.md)"; exit 1; }
	cp $(ATARI_XEX_DBG) $(ATARI_ATR_DIR_DBG)/autorun.sys
	cp $(ATARI_DOS_DIR)/*.SYS $(ATARI_ATR_DIR_DBG)/
	dir2atr -S -b Dos25 $@ $(ATARI_ATR_DIR_DBG)

# =============================================================================
# C64
# =============================================================================
C64_DIR  = $(SRCDIR)/c64
C64_CFG  = $(CC65_SHARE)/cfg/c64-asm.cfg
C64_SRCS = c64-main.s

C64_BLDDIR = $(BLDDIR)/c64/release
C64_PRG    = $(C64_BLDDIR)/kisstty.prg
C64_OBJS   = $(patsubst %.s,$(C64_BLDDIR)/%.o,$(C64_SRCS))

C64_BLDDIR_DBG = $(BLDDIR)/c64/debug
C64_PRG_DBG    = $(C64_BLDDIR_DBG)/kisstty.prg
C64_OBJS_DBG   = $(patsubst %.s,$(C64_BLDDIR_DBG)/%.o,$(C64_SRCS))

c64: $(C64_PRG)
c64-debug: $(C64_PRG_DBG)

$(C64_BLDDIR) $(C64_BLDDIR_DBG):
	mkdir -p $@

$(C64_BLDDIR)/%.o: $(C64_DIR)/%.s | $(C64_BLDDIR)
	$(CA65) --target c64 -I $(CA65INC) $(CA65FLAGS) \
	    --listing $(C64_BLDDIR)/$*.lst -o $@ $<

$(C64_BLDDIR_DBG)/%.o: $(C64_DIR)/%.s | $(C64_BLDDIR_DBG)
	$(CA65) --target c64 -I $(CA65INC) $(CA65FLAGS_DBG) \
	    --listing $(C64_BLDDIR_DBG)/$*.lst -o $@ $<

$(C64_PRG): $(C64_OBJS)
	$(LD65) -C $(C64_CFG) -o $@ $^

$(C64_PRG_DBG): $(C64_OBJS_DBG)
	$(LD65) -C $(C64_CFG) -o $@ $^

run-c64: $(C64_PRG)
	x64sc -autostartprgmode 1 -autostart $(C64_PRG)

debug-c64: $(C64_PRG_DBG)
	x64sc -autostartprgmode 1 -autostart $(C64_PRG_DBG)

# =============================================================================
# Apple II
# =============================================================================
APPLE2_DIR        = $(SRCDIR)/apple2
APPLE2_CFG        = $(CC65_SHARE)/cfg/apple2-asm.cfg
APPLE2_MASTER_DSK = /usr/local/share/linapple/Master.dsk
APPLE2_SRCS       = apple2-main.s

APPLE2_BLDDIR = $(BLDDIR)/apple2/release
APPLE2_BIN    = $(APPLE2_BLDDIR)/kisstty.bin
APPLE2_DSK    = $(APPLE2_BLDDIR)/kisstty.dsk
APPLE2_OBJS   = $(patsubst %.s,$(APPLE2_BLDDIR)/%.o,$(APPLE2_SRCS))

APPLE2_BLDDIR_DBG = $(BLDDIR)/apple2/debug
APPLE2_BIN_DBG    = $(APPLE2_BLDDIR_DBG)/kisstty.bin
APPLE2_DSK_DBG    = $(APPLE2_BLDDIR_DBG)/kisstty.dsk
APPLE2_OBJS_DBG   = $(patsubst %.s,$(APPLE2_BLDDIR_DBG)/%.o,$(APPLE2_SRCS))

apple2: $(APPLE2_DSK)
apple2-debug: $(APPLE2_DSK_DBG)

$(APPLE2_BLDDIR) $(APPLE2_BLDDIR_DBG):
	mkdir -p $@

$(APPLE2_BLDDIR)/%.o: $(APPLE2_DIR)/%.s | $(APPLE2_BLDDIR)
	$(CA65) --target apple2 -I $(CA65INC) $(CA65FLAGS) \
	    --listing $(APPLE2_BLDDIR)/$*.lst -o $@ $<

$(APPLE2_BLDDIR_DBG)/%.o: $(APPLE2_DIR)/%.s | $(APPLE2_BLDDIR_DBG)
	$(CA65) --target apple2 -I $(CA65INC) $(CA65FLAGS_DBG) \
	    --listing $(APPLE2_BLDDIR_DBG)/$*.lst -o $@ $<

$(APPLE2_BIN): $(APPLE2_OBJS)
	$(LD65) -C $(APPLE2_CFG) -o $@ $^

$(APPLE2_BIN_DBG): $(APPLE2_OBJS_DBG)
	$(LD65) -C $(APPLE2_CFG) -o $@ $^

$(APPLE2_DSK): $(APPLE2_BIN)
	cp $(APPLE2_MASTER_DSK) $@
	chmod 644 $@
	$(AC) -d $@ HELLO
	$(AC) -p $@ KISSTTY B 0x0803 < $(APPLE2_BIN)
	printf '10 PRINT CHR$$(4);"BRUN KISSTTY"\r' | $(ACX) import --basic --stdin --name=HELLO -d $@

$(APPLE2_DSK_DBG): $(APPLE2_BIN_DBG)
	cp $(APPLE2_MASTER_DSK) $@
	chmod 644 $@
	$(AC) -d $@ HELLO
	$(AC) -p $@ KISSTTY B 0x0803 < $(APPLE2_BIN_DBG)
	printf '10 PRINT CHR$$(4);"BRUN KISSTTY"\r' | $(ACX) import --basic --stdin --name=HELLO -d $@

run-apple2: $(APPLE2_DSK)
	linapple --d1 $(APPLE2_DSK) --autoboot

debug-apple2: $(APPLE2_DSK_DBG)
	linapple --d1 $(APPLE2_DSK_DBG) --autoboot

all: atari c64 apple2
all-debug: atari-debug c64-debug apple2-debug

clean:
	rm -rf $(BLDDIR)

.PHONY: all all-debug \
	atari atari-debug run-atari debug-atari \
	c64 c64-debug run-c64 debug-c64 \
	apple2 apple2-debug run-apple2 debug-apple2 \
	clean
