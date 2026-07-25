.setcpu "6502"
.include "term_line_input.inc"
.include "config.inc"
.include "globals.inc"
.include "line_input.inc"
.include "screen.inc"

.segment "CODE"

MARGIN_LEFT  = 1
MARGIN_TOP   = 23
MAX_LINE_LEN = 128

; initializes the line input area
;
; inputs:
;   CMDDATA0/1 - pointer to the upper left of the real screen
tli_init:
  lda #0
  sta tli_metadata+LineInput::scr_cursor
  sta tli_metadata+LineInput::data_cursor
  sta tli_metadata+LineInput::first_visible

  lda #<(MARGIN_TOP*SCREEN_WIDTH+MARGIN_LEFT)
  clc
  adc SCR_PTR_LO
  sta tli_metadata+LineInput::scr_ptr
  lda #>(MARGIN_TOP*SCREEN_WIDTH+MARGIN_LEFT)
  adc SCR_PTR_HI
  sta tli_metadata+LineInput::scr_ptr+1

  lda #<tli_data
  sta tli_metadata+LineInput::data_ptr
  lda #>tli_data
  sta tli_metadata+LineInput::data_ptr+1
  lda #TERMINAL_WIDTH
  sta tli_metadata+LineInput::num_visible
  lda #MAX_LINE_LEN
  sta tli_metadata+LineInput::data_len

  jsr int_set_context
  jsr li_shift_clear
  rts

int_set_context:
  lda CMDDATA0
  pha
  lda CMDDATA1
  pha
  lda #<tli_metadata
  sta CMDDATA0
  lda #>tli_metadata
  sta CMDDATA1
  jsr li_set_context
  pla
  sta CMDDATA1
  pla
  sta CMDDATA0
  rts


tli_hide_cursor:
  jsr int_set_context
  jsr li_show_cursor
  rts

tli_show_cursor:
  jsr int_set_context
  jsr li_show_cursor
  rts

tli_repaint:
  jsr int_set_context
  jsr li_repaint
  rts

tli_reset:
  jsr int_set_context
  jsr li_shift_clear
  rts

tli_move_cursor_left:
  jsr int_set_context
  jsr li_move_cursor_left
  rts

tli_move_cursor_right:
  jsr int_set_context
  jsr li_move_cursor_right
  rts

tli_char_insert:
  jsr int_set_context
  jsr li_char_insert
  rts

tli_char_delete:
  jsr int_set_context
  jsr li_char_delete
  rts

; inputs:
;   CMDDATA0 - the char to type
tli_type_char:
  jsr int_set_context
  jsr li_type_char
  rts

tli_backspace:
  jsr int_set_context
  jsr li_backspace
  rts

tli_shift_clear:
  jsr int_set_context
  jsr li_shift_clear
  rts

tli_metadata: .tag LineInput
tli_data:     .res MAX_LINE_LEN
