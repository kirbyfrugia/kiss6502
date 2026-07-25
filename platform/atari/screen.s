.setcpu "6502"

.include "globals.inc"
.include "screen.inc"
.include "utils.inc"

.segment "ZEROPAGE"
SCR_PTR_LO:         .res 1
SCR_PTR_HI:         .res 1

.segment "CODE"

scr_cls:
  lda SCR_PTR_LO
  sta ZPB0
  lda SCR_PTR_LO+1
  sta ZPB1

  ldx #(SCREEN_HEIGHT-1)
@row_loop:
  ldy #(SCREEN_WIDTH-1)
  lda #' '
  jsr ut_atascii_to_icode
@col_loop:
  sta (ZPB0),y
  dey
  bpl @col_loop
  dex
  bmi @done
  lda ZPB0
  clc
  adc #(SCREEN_WIDTH)
  sta ZPB0
  bcc @nowrap
  inc ZPB1
@nowrap:
  jmp @row_loop
@done:
  rts

