.setcpu "6502"
.include "config.inc"
.include "globals.inc"
.include "macros.inc"
.include "memmove.inc"
.include "screen.inc"
.include "text_area.inc"
.include "utils.inc"

.segment "ZEROPAGE"

ta_metadata:           .tag TextArea
context_ptr_lo:        .res 1
context_ptr_hi:        .res 1

.segment "CODE"

ta_init_context:
  lda #0
  sta context_ptr_lo
  sta context_ptr_hi
  rts

; sets the context for the text area to the TextArea
; pointed to by CMDDATA0/1. Make sure that you called
; ta_init_context first or you might get some garbage.
;
; inputs:
;   CMDDATA0/1 - pointer to a text area
ta_set_context:
  ; exit early if context already matches
  lda CMDDATA0
  cmp context_ptr_lo
  bne do_switch
  lda CMDDATA1
  cmp context_ptr_hi
  beq set_context_done
do_switch:
  lda context_ptr_hi
  bne cache_exists
  lda context_ptr_lo
  beq no_cache
cache_exists:
  ; copy our local cache to the existing source TextArea
  copy_struct_abs_to_zp ta_metadata, context_ptr_lo, TextArea
no_cache:
  ; now point to the new text area
  lda CMDDATA0
  sta context_ptr_lo
  lda CMDDATA1
  sta context_ptr_hi

  ; copy data from the new TextArea to the local cache in
  ; the zero page.
  copy_struct_zp_to_abs context_ptr_lo, ta_metadata, TextArea
set_context_done:
  rts

; subtracts one line from the scr_line and data_line
; ptrs
int_prev_line:
  lda g_temp_data_ptr_lo
  sec
  sbc ta_metadata+TextArea::width
  sta g_temp_data_ptr_lo
  lda g_temp_data_ptr_hi
  sbc #0
  sta g_temp_data_ptr_hi

  lda g_temp_scr_ptr_lo
  sec
  sbc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  lda g_temp_scr_ptr_hi
  sbc #0
  sta g_temp_scr_ptr_hi
  rts

; sets g_temp_data_ptr_lo/hi and g_temp_scr_ptr_lo/hi
; to the start of the last line
ta_find_last_line:
  ; note: use cursory because it'll always be faster
  ;       given it's >= first_line. And last line always
  ;       has to be >= cursor_line
  lda cursor_line_data_ptr_lo
  sta g_temp_data_ptr_lo
  lda cursor_line_data_ptr_hi
  sta g_temp_data_ptr_hi

  lda cursor_line_scr_ptr_lo
  sta g_temp_scr_ptr_lo
  lda cursor_line_scr_ptr_hi
  sta g_temp_scr_ptr_hi

  ldy ta_metadata+TextArea::cursory
@loop:
  cpy ta_metadata+TextArea::cursor_maxy
  beq @done
  
  lda g_temp_data_ptr_lo
  clc
  adc ta_metadata+TextArea::width
  sta g_temp_data_ptr_lo
  bcc @nowrap_data
  inc g_temp_data_ptr_hi
@nowrap_data:
  lda g_temp_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  bcc @nowrap_scr
  inc g_temp_scr_ptr_hi
@nowrap_scr:
  iny
  bne @loop
@done:
  rts

; flush cursor to backing store
int_flush_cursor:
  ldy #TextArea::cursorx
  lda ta_metadata+TextArea::cursorx
  sta (context_ptr_lo),y

  ldy #TextArea::cursory
  lda ta_metadata+TextArea::cursory
  sta (context_ptr_lo),y

  ldy #TextArea::cursor_line_scr_ptr
  lda cursor_line_scr_ptr_lo
  sta (context_ptr_lo),y
  iny
  lda cursor_line_scr_ptr_hi
  sta (context_ptr_lo),y

  ldy #TextArea::cursor_line_data_ptr
  lda cursor_line_data_ptr_lo
  sta (context_ptr_lo),y
  iny
  lda cursor_line_data_ptr_hi
  sta (context_ptr_lo),y

  rts

; updates the cursor line given based on
; the current cursorx/cursory
int_update_cursor_line:
  lda first_line_data_ptr_lo
  sta cursor_line_data_ptr_lo
  lda first_line_data_ptr_hi
  sta cursor_line_data_ptr_hi

  lda first_line_scr_ptr_lo
  sta cursor_line_scr_ptr_lo
  lda first_line_scr_ptr_hi
  sta cursor_line_scr_ptr_hi

  ldy #0
@loop:
  cpy ta_metadata+TextArea::cursory
  beq @done
  
  lda cursor_line_data_ptr_lo
  clc
  adc ta_metadata+TextArea::width
  sta cursor_line_data_ptr_lo
  bcc @nowrap_data
  inc cursor_line_data_ptr_hi
@nowrap_data:
  lda cursor_line_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta cursor_line_scr_ptr_lo
  bcc @nowrap_scr
  inc cursor_line_scr_ptr_hi
@nowrap_scr:
  iny
  bne @loop
@done:
  rts

ta_hide_cursor:
  lda ta_metadata+TextArea::type
  cmp #TA_TYPE_OUTPUT
  beq @done

  ldy ta_metadata+TextArea::cursorx
  lda (cursor_line_scr_ptr_lo),y
  and #%01111111
  sta (cursor_line_scr_ptr_lo),y
@done:
  rts

ta_show_cursor:
  lda ta_metadata+TextArea::type
  cmp #TA_TYPE_OUTPUT
  beq @done

  ldy ta_metadata+TextArea::cursorx
  lda (cursor_line_scr_ptr_lo),y
  ora #%10000000
  sta (cursor_line_scr_ptr_lo),y
@done:
  rts

int_cursor_home:
  lda #0
  sta ta_metadata+TextArea::cursorx
  sta ta_metadata+TextArea::cursory
  sta ta_metadata+TextArea::pending_newline
  jsr int_update_cursor_line
  rts

ta_clear_and_repaint:
  lda first_line_scr_ptr_lo
  sta g_temp_scr_ptr_lo
  lda first_line_scr_ptr_hi
  sta g_temp_scr_ptr_hi

  lda first_line_data_ptr_lo
  sta g_temp_data_ptr_lo
  lda first_line_data_ptr_hi
  sta g_temp_data_ptr_hi

  ldx ta_metadata+TextArea::height
@line_loop:
  ldy ta_metadata+TextArea::width
  dey
@col_loop:
  lda #' '
  sta (g_temp_data_ptr_lo),y
  lda #$00 ; space icode
  sta (g_temp_scr_ptr_lo),y
  dey
  bpl @col_loop
  dex
  beq @done

  lda g_temp_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  bcc @scr_nowrap
  inc g_temp_scr_ptr_hi
@scr_nowrap: 
  lda g_temp_data_ptr_lo
  clc
  adc ta_metadata+TextArea::width
  sta g_temp_data_ptr_lo
  bcc @data_nowrap
  inc g_temp_data_ptr_hi
@data_nowrap:
  jmp @line_loop
@done:
  rts

; repaints the entire text area. Useful when data changes.
; Not so efficient, but I'll worry about that later.
ta_repaint:
  lda first_line_scr_ptr_lo
  sta g_temp_scr_ptr_lo
  lda first_line_scr_ptr_hi
  sta g_temp_scr_ptr_hi

  lda first_line_data_ptr_lo
  sta g_temp_data_ptr_lo
  lda first_line_data_ptr_hi
  sta g_temp_data_ptr_hi

  ldx ta_metadata+TextArea::height
@line_loop:
  ldy ta_metadata+TextArea::width
  dey
@col_loop:
  lda (g_temp_data_ptr_lo),y
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  dey
  bpl @col_loop
  dex
  beq @done

  lda g_temp_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  bcc @scr_nowrap
  inc g_temp_scr_ptr_hi
@scr_nowrap: 
  lda g_temp_data_ptr_lo
  clc
  adc ta_metadata+TextArea::width
  sta g_temp_data_ptr_lo
  bcc @data_nowrap
  inc g_temp_data_ptr_hi
@data_nowrap:
  jmp @line_loop
@done:
  rts

; clears all data in the area, repaints, and returns the cursor home
ta_shift_clear:
  jsr ta_hide_cursor
  jsr int_cursor_home
  jsr ta_clear_and_repaint
  jsr ta_show_cursor
  rts

; shifts all lines from the cursor line downwards
; down by one.
int_shift_lines_down:
  jsr ta_find_last_line
  lda cursor_line_data_ptr_lo
  sta MM_FROM
  clc
  adc ta_metadata+TextArea::width
  sta MM_TO
  lda cursor_line_data_ptr_hi
  sta MM_FROM+1
  adc #0
  sta MM_TO+1

  lda g_temp_data_ptr_lo
  sec
  sbc cursor_line_data_ptr_lo
  sta MM_SIZEL
  lda g_temp_data_ptr_hi
  sbc cursor_line_data_ptr_hi
  sta MM_SIZEH

  jsr MM_MOVEUP_SS
  rts

; calculates the bytes remaining from the cursor
; position to the end of the buffer
; outputs:
;   MM_SIZEL/MM_SIZEH
ta_bytes_remaining:
  ; calculate the number of bytes to move, formula:
  ;   end of buffer = start of buffer + size
  ;   num bytes = end of buffer - cursor line start - cursorx - 1
  ;   * note: end of buffer is actually one past end of buffer
  ;   * note: the "-1" is because the last char drops off 

  ; end of buffer
  lda first_line_data_ptr_lo
  clc
  adc ta_metadata+TextArea::size
  sta MM_SIZEL
  lda first_line_data_ptr_hi
  adc ta_metadata+TextArea::size+1
  sta MM_SIZEH

  ; end - cursor start of line
  lda MM_SIZEL
  sec
  sbc cursor_line_data_ptr_lo
  sta MM_SIZEL
  lda MM_SIZEH
  sbc cursor_line_data_ptr_hi
  sta MM_SIZEH

  ; - cursorx
  lda MM_SIZEL
  sec
  sbc ta_metadata+TextArea::cursorx
  sta MM_SIZEL
  lda MM_SIZEH
  sbc #0
  sta MM_SIZEH

  ; - 1
  lda MM_SIZEL
  bne @nowrap
  dec MM_SIZEH
@nowrap:
  dec MM_SIZEL
  rts

ta_move_cursor_to_start_of_last_line:
  jsr ta_hide_cursor
  lda ta_metadata+TextArea::cursor_maxy
  sta ta_metadata+TextArea::cursory
  lda #0
  sta ta_metadata+TextArea::cursorx
  jsr int_update_cursor_line
  jsr ta_show_cursor
  rts

ta_edit_move_cursor_up:
  jsr ta_hide_cursor
  jsr int_move_cursor_up
  jsr ta_show_cursor
  rts

; moves the cursor up one line (wrapping to the bottom).
; does not touch the cursor highlight; callers own hide/show.
int_move_cursor_up:
  lda ta_metadata+TextArea::cursory
  beq @wrapped
  dec ta_metadata+TextArea::cursory
  jmp @updated
@wrapped:
  lda ta_metadata+TextArea::cursor_maxy
  sta ta_metadata+TextArea::cursory
@updated:
  jsr int_update_cursor_line
  rts

ta_edit_move_cursor_down:
  jsr ta_hide_cursor
  jsr int_move_cursor_down
  jsr ta_show_cursor
  rts

; moves the cursor down one line (wrapping to the top).
; does not touch the cursor highlight; callers own hide/show.
int_move_cursor_down:
  lda ta_metadata+TextArea::cursory
  cmp ta_metadata+TextArea::cursor_maxy
  beq @wrapped

  inc ta_metadata+TextArea::cursory
  bne @updated
@wrapped:
  lda #0
  sta ta_metadata+TextArea::cursory
@updated:
  jsr int_update_cursor_line
  rts

; moves the cursor left if possible.
;
; pass CMDDATA0 to define behavior when we wrap to the left.
; Zero will stay on the same line. Non-zero will move up a line.
; Used when we move the cursor based on arrow keys vs text changes.
;
; inputs:
;   CMDDATA0 - cursor behavior on wrap
ta_edit_move_cursor_left:
  jsr ta_hide_cursor
  jsr int_move_cursor_left
  jsr ta_show_cursor
  rts

; moves the cursor left one column. see CMDDATA0 docs above for
; wrap behavior. does not touch the cursor highlight; callers
; own hide/show.
;
; inputs:
;   CMDDATA0 - cursor behavior on wrap
int_move_cursor_left:
  lda ta_metadata+TextArea::cursorx
  beq @wrapped
  dec ta_metadata+TextArea::cursorx
  jmp @updated
@wrapped:
  lda #CURSOR_BEHAVIOR_WRAP_CHANGE_LINES
  bit CMDDATA0
  bmi @wrapped_change_lines

  ; if here, just wrap around on the same line
  lda ta_metadata+TextArea::cursor_maxx
  sta ta_metadata+TextArea::cursorx
  bne @updated
@wrapped_change_lines:
  lda ta_metadata+TextArea::cursory
  beq @done ; already at top, just ignore movement

  ; move up a line
  dec ta_metadata+TextArea::cursory
  ; and move to the end of it
  lda ta_metadata+TextArea::cursor_maxx
  sta ta_metadata+TextArea::cursorx
@updated:
  jsr int_update_cursor_line
@done:
  rts

ta_edit_move_cursor_right:
  jsr ta_hide_cursor
  jsr int_move_cursor_right
  jsr ta_show_cursor
  rts

; moves the cursor right one column. see CMDDATA0 docs above for
; wrap behavior. does not touch the cursor highlight; callers
; own hide/show.
;
; inputs:
;   CMDDATA0 - cursor behavior on wrap
int_move_cursor_right:
  lda ta_metadata+TextArea::cursorx
  cmp ta_metadata+TextArea::cursor_maxx
  beq @wrapped

  inc ta_metadata+TextArea::cursorx
  bne @updated
@wrapped:
  lda #CURSOR_BEHAVIOR_WRAP_CHANGE_LINES
  bit CMDDATA0
  bmi @wrapped_change_lines

  ; if here, just wrap around on the same line
  lda #0
  sta ta_metadata+TextArea::cursorx
  beq @updated
@wrapped_change_lines:
  lda ta_metadata+TextArea::cursory
  cmp ta_metadata+TextArea::cursor_maxy
  beq @done; already at bottom

  ; move down a line
  inc ta_metadata+TextArea::cursory
  ; and move to the start of it
  lda #0
  sta ta_metadata+TextArea::cursorx
@updated:
  jsr int_update_cursor_line
@done:
  rts

; updates the char at the current cursor position
; to A.
; modifies:
;   A
int_update_char:
  ldy ta_metadata+TextArea::cursorx
  sta (cursor_line_data_ptr_lo),y
  jsr ut_atascii_to_icode
  sta (cursor_line_scr_ptr_lo),y
  rts

; sets the character at the current cursor location to the
; char in CMDDATA0. moves the cursor to the right.
;
; inputs
;   CMDDATA0 - the character
ta_edit_type_char:
  jsr ta_hide_cursor
  lda CMDDATA0
  jsr int_update_char
  lda #CURSOR_BEHAVIOR_WRAP_CHANGE_LINES
  sta CMDDATA0
  jsr int_move_cursor_right
  jsr ta_show_cursor
  rts

; moves cursor left, erases character under cursor
; atari style doesn't shift data left.
ta_edit_backspace:
  jsr ta_hide_cursor
  lda #CURSOR_BEHAVIOR_WRAP_CHANGE_LINES
  sta CMDDATA0
  jsr int_move_cursor_left
  lda #' '
  jsr int_update_char
  jsr ta_show_cursor
  rts

; moves all lines down from current cursor
; including current line and clears current line
; cursor stays where it is.
ta_edit_line_insert:
  lda ta_metadata+TextArea::cursory
  cmp ta_metadata+TextArea::cursor_maxy
  beq @done

  jsr ta_hide_cursor

  jsr int_shift_lines_down
  jsr int_clear_cursor_line

  jsr ta_repaint
  jsr ta_show_cursor
@done:
  rts

ta_edit_char_insert:
  jsr ta_hide_cursor
  jsr int_shift_chars_right
  jsr ta_repaint
  jsr ta_show_cursor
  rts

ta_edit_line_delete:
  jsr ta_hide_cursor
  lda ta_metadata+TextArea::cursory
  cmp ta_metadata+TextArea::cursor_maxy
  beq @last_line ; on last line

  jsr int_shift_lines_up_from_cursor
@last_line:
  jsr int_clear_last_line
  jsr ta_repaint
  jsr ta_show_cursor
  rts

; erases the char under the cursor by moving all
; the chars to the right one space left
ta_edit_char_delete:
  ldy ta_metadata+TextArea::cursory
  cpy ta_metadata+TextArea::cursor_maxy
  bcc @not_at_end
  ldy ta_metadata+TextArea::cursorx
  cpy ta_metadata+TextArea::cursor_maxx
  bcc @not_at_end
  bcs @done
@not_at_end:
  jsr ta_hide_cursor
  jsr int_shift_chars_left
  jsr int_clear_last_char
  jsr ta_repaint
  jsr ta_show_cursor
@done:
  rts

; clears the data in the current line
int_clear_cursor_line:
  ldy ta_metadata+TextArea::width
  dey
@loop:
  lda #' '
  sta (cursor_line_data_ptr_lo),y
  jsr ut_atascii_to_icode
  sta (cursor_line_scr_ptr_lo),y
  dey
  bpl @loop
  rts

int_clear_last_char:
  jsr ta_find_last_line
  ldy ta_metadata+TextArea::width
  dey
  lda #' '
  sta (g_temp_data_ptr_lo),y
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  rts

int_clear_last_line:
  jsr ta_find_last_line
  jsr int_clear_line
  rts

; inputs:
;   g_temp_data_ptr_lo/hi
int_clear_line:
  ldy ta_metadata+TextArea::width
  dey
@loop:
  lda #' '
  sta (g_temp_data_ptr_lo),y
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  dey
  bpl @loop
  rts

; shifts all characters from cursor position to the
; right by one. Last char is lost. Blanks the cursor
; position with a space.
; modifies:
;   ZPB0/1/2/3/4/5
int_shift_chars_right:
  jsr ta_bytes_remaining
  lda cursor_line_data_ptr_lo
  clc
  adc ta_metadata+TextArea::cursorx
  sta MM_FROM
  sta MM_TO
  lda cursor_line_data_ptr_hi
  adc #0
  sta MM_FROM+1
  sta MM_TO+1

  inc MM_TO
  bne @nowrap_dest
  inc MM_TO+1
@nowrap_dest:
  jsr MM_MOVEUP_SS

  lda #' '
  jsr int_update_char

  rts

; shifts all characters to the right of the cursor
; to the left one space, leaving last space garbage.
int_shift_chars_left:
  jsr ta_bytes_remaining
  lda cursor_line_data_ptr_lo
  clc
  adc ta_metadata+TextArea::cursorx
  sta MM_TO
  lda cursor_line_data_ptr_hi
  adc #0
  sta MM_TO+1

  lda MM_TO
  clc
  adc #1
  sta MM_FROM
  lda MM_TO+1
  adc #0
  sta MM_FROM+1

  jsr MM_MOVEDOWN
  rts

; shifts all lines up from below the cursor line
; to the cursor line, leaving last line garbage
int_shift_lines_up_from_cursor:
  lda cursor_line_data_ptr_lo
  sta MM_TO
  lda cursor_line_data_ptr_hi
  sta MM_TO+1

  lda MM_TO
  clc
  adc ta_metadata+TextArea::width
  sta MM_FROM
  lda MM_TO+1
  adc #0
  sta MM_FROM+1

  jsr ta_find_last_line
  lda g_temp_data_ptr_lo
  sec
  sbc MM_TO
  sta MM_SIZEL
  lda g_temp_data_ptr_hi
  sbc MM_TO+1
  sta MM_SIZEH

  jsr MM_MOVEDOWN
  rts

; calculates number of bytes for N lines.
;
; inputs:
;   A - the number of lines
; outputs:
;   MM_SIZEL/MM_SIZEH - A * width
; modifies:
;   a,x,ZPB4-5
int_lines_to_bytes:
  tax
  lda #0
  sta MM_SIZEL
  sta MM_SIZEH
  cpx #0
  beq @done
@loop:
  lda MM_SIZEL
  clc
  adc ta_metadata+TextArea::width
  sta MM_SIZEL
  bcc @nowrap
  inc MM_SIZEH
@nowrap:
  dex
  bne @loop
@done:
  rts

; scrolls the entire text area up N lines, discarding
; the top N lines.
;
; only moves data. the bottom N lines will now have
; garbage and the screen will need to be repainted. that
; is up to the caller.
;
; also doesn't protect against N >= height. do that yourself.
; inputs:
;   a - the number of lines to scroll up (N)
; modifies:
;   a,x,ZPB0-5
int_out_scroll_up_lines:
  jsr int_lines_to_bytes

  ; move everything below the top N lines up to the
  ; start of the buffer.
  lda first_line_data_ptr_lo
  sta MM_TO
  clc
  adc MM_SIZEL
  sta MM_FROM
  lda first_line_data_ptr_hi
  sta MM_TO+1
  adc MM_SIZEH
  sta MM_FROM+1

  lda ta_metadata+TextArea::size
  sec
  sbc MM_SIZEL
  sta MM_SIZEL
  lda ta_metadata+TextArea::size+1
  sbc MM_SIZEH
  sta MM_SIZEH
  jsr MM_MOVEDOWN
  rts

; if pending_newline is set, advance to the start of the next line,
; scrolling the output up if we're already on the last line,
; and clear the flag.
;
; purpose is to not scroll until we actually need the space.
;
; modifies:
;   a,x,y,ZPB0-5
int_flush_pending_newline:
  lda ta_metadata+TextArea::pending_newline
  beq @done
  lda #0
  sta ta_metadata+TextArea::pending_newline

  ldx ta_metadata+TextArea::cursory
  cpx ta_metadata+TextArea::cursor_maxy
  beq @scroll
  inc ta_metadata+TextArea::cursory
  lda #0
  sta ta_metadata+TextArea::cursorx
  jsr int_update_cursor_line
  rts
@scroll:
  ; already on last line
  lda #1
  jsr int_out_scroll_up_lines
  jsr int_clear_cursor_line
  jsr ta_repaint
  lda #0
  sta ta_metadata+TextArea::cursorx
@done:
  rts

; ends the current line and flags that there is now a new
; line pending.
;
; if a new line was previously pending, flush that first.
;
; modifies:
;   a,x,y,ZPB0-5
ta_out_next_line:
  jsr int_flush_pending_newline
  lda #1
  sta ta_metadata+TextArea::pending_newline
  rts

; appends the char. If it's an eol or we reach
; the end of the line, it moves to the next line,
; scrolling the viewport up if needed.
;
; sets the carry flag if it was an eol character
;
; inputs:
;   CMDDATA0 - the char
; modifies:
;   a,x,y,ZPB0-5
ta_out_append_char:
  ; settle any owed newline before placing the char, so it
  ; lands on the right (possibly scrolled) line.
  jsr int_flush_pending_newline

  lda CMDDATA0
  cmp #TA_EOL
  beq @eol
  jsr int_update_char

  ldx ta_metadata+TextArea::cursorx
  cpx ta_metadata+TextArea::cursor_maxx
  beq @eol
  inx
  stx ta_metadata+TextArea::cursorx
  clc
  rts
@eol:
  ; eol char, or we filled the last column. owe a newline
  ; instead of advancing now.
  lda #1
  sta ta_metadata+TextArea::pending_newline
  sec
  rts

; prints a null terminated string. Handles eol appropriately.
; Not terribly efficient since it adds chars one by one amongst
; other issues. If you know you have full lines, use other
; routines as well.
;
; inputs:
;   CMDDATA0/1 - the str
; modifies:
;   a,x,y,ZPB0-5
ta_out_println:
  ldy #0
@loop:
  lda (CMDDATA0),y
  beq @done
  tya
  pha
  lda CMDDATA0
  pha
  lda CMDDATA1
  pha

  lda (CMDDATA0),y
  sta CMDDATA0
  jsr ta_out_append_char
  pla
  sta CMDDATA1
  pla
  sta CMDDATA0
  pla
  tay
  iny
  bne @loop
@done:
  jsr ta_out_next_line
  jsr int_update_cursor_line
  rts

; appends N lines of data into the text area, scrolling up to make
; room as needed. the block starts on a blank line, which is
; the current line if cursorx is 0, otherwise the next line.
;
; the cursor lands on the last line with 'pending' set, so the next
; write starts on a fresh line below. if CMDDATA3 > 0, the last
; line is the final trailing blank line rather than the last line
; of data.
;
; the caller must ensure the block plus any trailing blank lines
; fits within the area height.
;
; inputs:
;   CMDDATA0/1 - ptr to the block of data to append
;   CMDDATA2   - number of lines to append
;   CMDDATA3   - number of trailing blank lines, 0 for none
; modifies:
;   a,x,y,ZPB0-5,CMDDATA4
ta_out_append_lines:
  to_append  = CMDDATA2
  extra      = CMDDATA3
  cursor_line = CMDDATA4

  jsr int_flush_pending_newline

  ; start_line = cursory + (cursorx != 0 ? 1 : 0)
  ; last_line  = start_line + to_append + extra - 1
  ; scroll     = max(0, last_line - cursor_maxy)
  lda ta_metadata+TextArea::cursory
  ldx ta_metadata+TextArea::cursorx
  beq @start_line_set
  clc
  adc #1
@start_line_set:
  clc
  adc to_append
  adc extra
  sec
  sbc #1
  sta cursor_line

  lda cursor_line
  sec
  sbc ta_metadata+TextArea::cursor_maxy
  bcc @room       ; last_line <= maxy. fits, no scroll.
  beq @room       ; last_line == maxy. fits, no scroll.
  pha             ; a = last_line - maxy, # lines to scroll up
  lda ta_metadata+TextArea::cursor_maxy
  sta cursor_line
  pla
  jsr int_out_scroll_up_lines
@room:
  ; land on the last line with a pending newline
  lda cursor_line
  sta ta_metadata+TextArea::cursory
  lda #0
  sta ta_metadata+TextArea::cursorx
  lda #1
  sta ta_metadata+TextArea::pending_newline
  jsr int_update_cursor_line

  ; MM_TO = block start = cursor line - (to_append + extra - 1) lines.
  lda to_append
  clc
  adc extra
  sec
  sbc #1
  jsr int_lines_to_bytes

  lda cursor_line_data_ptr_lo
  sec
  sbc MM_SIZEL
  sta MM_TO
  lda cursor_line_data_ptr_hi
  sbc MM_SIZEH
  sta MM_TO+1

  lda CMDDATA0
  sta MM_FROM
  lda CMDDATA1
  sta MM_FROM+1
  lda to_append
  jsr int_lines_to_bytes
  jsr MM_MOVEDOWN

  ; blank the trailing lines. the cursor sits on the last of them,
  ; so start there and walk up.
  ldx extra
  beq @done
  lda cursor_line_data_ptr_lo
  sta g_temp_data_ptr_lo
  lda cursor_line_data_ptr_hi
  sta g_temp_data_ptr_hi
  lda cursor_line_scr_ptr_lo
  sta g_temp_scr_ptr_lo
  lda cursor_line_scr_ptr_hi
  sta g_temp_scr_ptr_hi
@clear_blank:
  jsr int_clear_line
  jsr int_prev_line
  dex
  bne @clear_blank

@done:
  jsr ta_repaint
  rts

