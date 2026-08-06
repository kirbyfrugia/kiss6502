.setcpu "6502"
.include "atari.inc"
.include "boot850.inc"
.include "utils.inc"

.segment "CODE"

POLL_DDEVIC    = $50       ; Device ID for 850 RS232 port
POLL_DUNIT     = $01       ; Device number 1
POLL_DCOMND    = $3f       ; Poll command to see if devices have handlers to load
POLL_DSTATS    = %01000000 ; Bit 6 - receive data
POLL_DBUF      = $0664     ; Poll response from 850 to retrieve loader (known safe location)
POLL_DTIMLO    = $02       ; Time to wait for the 850 to respond in seconds
POLL_DBYT      = 12        ; Num bytes in 850 response
POLL_DAUX1     = $01       ; Forces the device to always respond
POLL_DAUX2     = $00       ; Unused

BOOTSTRAP      = $0506     ; loader entry ($0500 load address plus a 6-byte boot header)
INSTALL_OFFSET = $03b3     ; offset from MEMLO to the handler's "add R: to HATABS" routine
BOOT_HANDOFF   = $03e9     ; the loader jumps here once it's done relocating the handler

; 38 bytes at $031a: 12 three byte entries then a two byte terminator.
HATABS_ENTRIES = 12
HATABS_SIZE    = HATABS_ENTRIES * 3

; Boot the 850. Bootstraps and loads the 850's R: handler
; outputs:
;   carry - clear if succeeded, set if not.
boot850_bootstrap:
  lda #POLL_DDEVIC
  sta DDEVIC
  lda #POLL_DUNIT
  sta DUNIT
  lda #POLL_DCOMND
  sta DCOMND
  lda #POLL_DSTATS
  sta DSTATS
  lda #<POLL_DBUF
  sta DBUFLO
  lda #>POLL_DBUF
  sta DBUFHI
  lda #<POLL_DBYT
  sta DBYTLO
  lda #>POLL_DBYT
  sta DBYTHI
  lda #POLL_DTIMLO
  sta DTIMLO
  lda #POLL_DAUX1
  sta DAUX1
  lda #POLL_DAUX2
  sta DAUX2

  ; Send poll command and wait for 850 to respond with
  ; the command needed to retrieve the booter/relocator.
  jsr SIOV
  bmi @error

@poll_succeeded:
  ; Copy the 12 bytes from the 850 poll response
  ; into the HW Device Control Block (DCB). This
  ; is the command to load the booter. It is command $21.
  ldx #POLL_DBYT-1
@copy:
  lda POLL_DBUF,x
  sta DDEVIC,x
  dex
  bpl @copy

  jsr SIOV
  bmi @error
@bootstrap:
  ; $0506 loads the handler into MEMLO and relocates it, then jumps to the boot
  ; handoff instead of returning. The OS sets that up during a normal boot, but
  ; I'm driving the loader myself, so stub the handoff with clc/rts to get
  ; control back. Success comes back carry clear; if the loader's own SIO fetch
  ; fails it exits early with carry set.
  lda #$18           ; clc opcode
  sta BOOT_HANDOFF
  lda #$60           ; rts opcode
  sta BOOT_HANDOFF+1
  jsr BOOTSTRAP
  bcs @error

  ; The handler is relocatable, so its "add R: to HATABS" routine sits at
  ; MEMLO+INSTALL_OFFSET. Call it to install R: (with the relocated handler
  ; vector) and bump MEMLO past the handler.
  clc
  lda MEMLO
  adc #<INSTALL_OFFSET
  sta install_vec
  lda MEMLO+1
  adc #>INSTALL_OFFSET
  sta install_vec+1
  jsr @install
  clc
  rts
@install:
  jmp (install_vec)
@error:
  sec
  rts

; Checks to see if there is an R: device in HATABS
; outputs:
;   carry - clear if in HATABS, set if not.
boot850_check:
  ; There are up to 8 devices, each one takes up 3 bytes
  ldx #0
@check_installed:
  lda HATABS,x
  cmp #'R'
  beq @installed
  inx
  inx
  inx
  cpx #HATABS_SIZE
  bcc @check_installed
  sec ; failure
  rts
@installed:
  clc
  rts
@error:
  sec
  rts

install_vec: .byte 0, 0
