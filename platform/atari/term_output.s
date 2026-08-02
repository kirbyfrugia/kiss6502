.setcpu "6502"
.include "config.inc"
.include "globals.inc"
.include "screen.inc"
.include "term_output.inc"
.include "term.inc"
.include "text_area.inc"

.segment "CODE"
TO_MARGIN_LEFT = 1
TO_MAX_SIZE    = TERMINAL_WIDTH*TO_MAX_HEIGHT

to_init:
  lda #0
  sta to_metadata+TextArea::cursorx
  sta to_metadata+TextArea::cursory
  sta to_metadata+TextArea::cursor_line_scr_ptr
  sta to_metadata+TextArea::cursor_line_scr_ptr+1

  lda #TA_TYPE_OUTPUT
  sta to_metadata+TextArea::type

  MARGIN_TOP .set 1
  lda #<(MARGIN_TOP*SCREEN_WIDTH+TO_MARGIN_LEFT)
  clc
  adc SCR_PTR_LO
  sta to_metadata+TextArea::first_line_scr_ptr
  lda #>(MARGIN_TOP*SCREEN_WIDTH+TO_MARGIN_LEFT)
  adc SCR_PTR_HI
  sta to_metadata+TextArea::first_line_scr_ptr+1

  lda #TERMINAL_WIDTH
  sta to_metadata+TextArea::width
  lda #(TERMINAL_WIDTH-1)
  sta to_metadata+TextArea::cursor_maxx

  lda #<to_data
  sta to_metadata+TextArea::first_line_data_ptr
  lda #>to_data
  sta to_metadata+TextArea::first_line_data_ptr+1

  lda #TO_HEIGHT_SINGLE_LINE_INPUT
  jsr to_resize

  rts

int_set_context:
  lda CMDDATA0
  pha
  lda CMDDATA1
  pha
  lda #<to_metadata
  sta CMDDATA0
  lda #>to_metadata
  sta CMDDATA1
  jsr ta_set_context
  pla
  sta CMDDATA1
  pla
  sta CMDDATA0
  rts

to_repaint:
  jsr int_set_context
  jsr ta_repaint
  rts

; resizes the output area to a new height
; inputs:
;   a - the new height in rows
to_resize:
  pha
  jsr int_set_context
  pla

  sta ta_metadata+TextArea::height
  sec
  sbc #1
  sta ta_metadata+TextArea::cursor_maxy

  lda #0
  sta ta_metadata+TextArea::size
  sta ta_metadata+TextArea::size+1
  ldx ta_metadata+TextArea::height
@size_loop:
  lda ta_metadata+TextArea::size
  clc
  adc #TERMINAL_WIDTH
  sta ta_metadata+TextArea::size
  bcc @size_nowrap
  inc ta_metadata+TextArea::size+1
@size_nowrap:
  dex
  bne @size_loop

  jsr ta_shift_clear
  rts

; see ta_out_println for what this does. Not super
; efficient, but fine for short strings like "welcome"
to_println:
  jsr int_set_context
  jsr ta_out_println
  rts

; appends the char to the output area, scrolling
; if needed.
; inputs:
;   CMDDATA0 - the char
to_append_char:
  jsr int_set_context
  jsr ta_out_append_char
  rts

; appends N lines to the current row if blank
; or the next blank row, scrolling if necessary
; inputs:
;   CMDDATA0/1 - pointer to the data to append
;   CMDDATA2   - number of lines to append
;   CMDDATA3   - number of trailing blank lines (0 for none)
to_append_lines:
  jsr int_set_context
  jsr ta_out_append_lines
  rts

to_metadata: .tag TextArea
to_data:     .res TO_MAX_SIZE

new_line: .repeat SCREEN_WIDTH, I
             .byte ' '
           .endrepeat
