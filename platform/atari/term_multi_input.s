.setcpu "6502"
.include "term_multi_input.inc"
.include "config.inc"
.include "globals.inc"
.include "screen.inc"
.include "text_area.inc"

.segment "CODE"

MARGIN_LEFT = 1
MARGIN_TOP  = 20
HEIGHT      = 4
SIZE        = TERMINAL_WIDTH * HEIGHT

; initializes the text input area
;
; inputs:
;   CMDDATA0/1 - pointer to the upper left of the real screen
tmi_init:
  lda #0
  sta tmi_metadata+TextArea::cursorx
  sta tmi_metadata+TextArea::cursory

  lda #<(MARGIN_TOP*SCREEN_WIDTH+MARGIN_LEFT)
  clc
  adc SCR_PTR_LO
  sta tmi_metadata+TextArea::first_line_scr_ptr
  lda #>(MARGIN_TOP*SCREEN_WIDTH+MARGIN_LEFT)
  adc SCR_PTR_HI
  sta tmi_metadata+TextArea::first_line_scr_ptr+1

  lda #TA_TYPE_INPUT
  sta tmi_metadata+TextArea::type

  lda #<tmi_data
  sta tmi_metadata+TextArea::first_line_data_ptr
  lda #>tmi_data
  sta tmi_metadata+TextArea::first_line_data_ptr+1
  lda #TERMINAL_WIDTH
  sta tmi_metadata+TextArea::width
  lda #HEIGHT
  sta tmi_metadata+TextArea::height
  lda #SIZE
  sta tmi_metadata+TextArea::size
  lda #0
  sta tmi_metadata+TextArea::size+1
  lda #(TERMINAL_WIDTH-1)
  sta tmi_metadata+TextArea::cursor_maxx
  lda #(HEIGHT-1)
  sta tmi_metadata+TextArea::cursor_maxy

  jsr int_set_context
  jsr ta_shift_clear
  rts

int_set_context:
  lda CMDDATA0
  pha
  lda CMDDATA1
  pha
  lda #<tmi_metadata
  sta CMDDATA0
  lda #>tmi_metadata
  sta CMDDATA1
  jsr ta_set_context
  pla
  sta CMDDATA1
  pla
  sta CMDDATA0
  rts


tmi_hide_cursor:
  jsr int_set_context
  jsr ta_show_cursor
  rts

tmi_show_cursor:
  jsr int_set_context
  jsr ta_show_cursor
  rts

tmi_repaint:
  jsr int_set_context
  jsr ta_repaint
  rts

tmi_reset:
  jsr int_set_context
  jsr ta_shift_clear
  rts

tmi_edit_move_cursor_up:
  jsr int_set_context
  jsr ta_edit_move_cursor_up
  rts

tmi_edit_move_cursor_down:
  jsr int_set_context
  jsr ta_edit_move_cursor_down
  rts

; inputs:
;   CMDDATA0 - cursor behavior on wrap
tmi_edit_move_cursor_left:
  jsr int_set_context
  jsr ta_edit_move_cursor_left
  rts

; inputs:
;   CMDDATA0 - cursor behavior on wrap
tmi_edit_move_cursor_right:
  jsr int_set_context
  jsr ta_edit_move_cursor_right
  rts

; inputs:
;   CMDDATA0 - the char to type
tmi_edit_type_char:
  jsr int_set_context
  jsr ta_edit_type_char
  rts

tmi_edit_backspace:
  jsr int_set_context
  jsr ta_edit_backspace
  rts

tmi_shift_clear:
  jsr int_set_context
  jsr ta_shift_clear
  rts

tmi_edit_line_insert:
  jsr int_set_context
  jsr ta_edit_line_insert
  rts

tmi_edit_char_insert:
  jsr int_set_context
  jsr ta_edit_char_insert
  rts

tmi_edit_line_delete:
  jsr int_set_context
  jsr ta_edit_line_delete
  rts

tmi_edit_char_delete:
  jsr int_set_context
  jsr ta_edit_char_delete
  rts

tmi_metadata:              .tag TextArea
tmi_data:                  .res SIZE
