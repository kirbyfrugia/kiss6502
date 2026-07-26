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

; draws a null terminated atascii string onto the screen.
;
; inputs:
;   CMDDATA0/1 - ptr to the string
;   CMDDATA2/3 - screen offset from SCR_PTR
;   CMDDATA4   - mask or'd into each char ($80 for inverse)
scr_draw_str:
  str_ptr = CMDDATA0
  scr_ptr = CMDDATA2
  mask    = CMDDATA4

  lda scr_ptr
  clc
  adc SCR_PTR_LO
  sta scr_ptr
  lda scr_ptr+1
  adc SCR_PTR_HI
  sta scr_ptr+1

  ldy #0
@loop:
  lda (str_ptr),y
  beq @done
  jsr ut_atascii_to_icode
  ora mask
  sta (scr_ptr),y
  iny
  bne @loop
@done:
  rts

