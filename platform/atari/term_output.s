.setcpu "6502"
.include "term_output.inc"
.include "globals.inc"
.include "memmove.inc"
.include "screen.inc"
.include "utils.inc"

.segment "ZEROPAGE"
cursor_line_scr_ptr_lo:  .res 1
cursor_line_scr_ptr_hi:  .res 1
cursor_line_data_ptr_lo: .res 1
cursor_line_data_ptr_hi: .res 1

.segment "CODE"
TO_MARGIN_LEFT = 1
TO_MARGIN_TOP  = 1
TO_SIZE        = TERMINAL_WIDTH*TO_HEIGHT

to_init:
  lda #0
  sta cursorx
  sta cursory
  sta cursor_line_scr_ptr_lo
  sta cursor_line_scr_ptr_hi

  lda #<(TO_MARGIN_TOP*SCREEN_WIDTH+TO_MARGIN_LEFT)
  clc
  adc SCR_PTR_LO
  sta first_line_scr_ptr_lo
  lda #>(TO_MARGIN_TOP*SCREEN_WIDTH+TO_MARGIN_LEFT)
  adc SCR_PTR_HI
  sta first_line_scr_ptr_hi

  lda #<to_data
  sta first_line_data_ptr_lo
  lda #>to_data
  sta first_line_data_ptr_hi

  jsr to_clear_and_home
  rts

to_clear_and_home:
  jsr int_cursor_home
  jsr int_clear_and_repaint
  rts

int_prev_line:
  lda g_temp_data_ptr_lo
  sec
  sbc #TERMINAL_WIDTH
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
@line_loop:
  cpy cursory
  beq @done

  lda cursor_line_data_ptr_lo
  clc
  adc #TERMINAL_WIDTH
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
  bne @line_loop
@done:
  rts

int_cursor_home:
  lda #0
  sta cursorx
  sta cursory
  sta pending_newline
  jsr int_update_cursor_line
  rts

int_clear_and_repaint:
  lda first_line_scr_ptr_lo
  sta g_temp_scr_ptr_lo
  lda first_line_scr_ptr_hi
  sta g_temp_scr_ptr_hi

  lda first_line_data_ptr_lo
  sta g_temp_data_ptr_lo
  lda first_line_data_ptr_hi
  sta g_temp_data_ptr_hi

  ldx #TO_HEIGHT
@line_loop:
  ldy #TERMINAL_WIDTH
  dey
@col_loop:
  lda #' '
  sta (g_temp_data_ptr_lo),y
  lda #ICODE_SPACE
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
  adc #TERMINAL_WIDTH
  sta g_temp_data_ptr_lo
  bcc @data_nowrap
  inc g_temp_data_ptr_hi
@data_nowrap:
  jmp @line_loop
@done:
  rts

; repaints the entire area. Useful when data changes.
; Not so efficient, but I'll worry about that later.
to_repaint:
  lda first_line_scr_ptr_lo
  sta g_temp_scr_ptr_lo
  lda first_line_scr_ptr_hi
  sta g_temp_scr_ptr_hi

  lda first_line_data_ptr_lo
  sta g_temp_data_ptr_lo
  lda first_line_data_ptr_hi
  sta g_temp_data_ptr_hi

  ldx #TO_HEIGHT
@line_loop:
  ldy #TERMINAL_WIDTH
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
  adc #TERMINAL_WIDTH
  sta g_temp_data_ptr_lo
  bcc @data_nowrap
  inc g_temp_data_ptr_hi
@data_nowrap:
  jmp @line_loop
@done:
  rts

int_update_char:
  ldy cursorx
  sta (cursor_line_data_ptr_lo),y
  jsr ut_atascii_to_icode
  sta (cursor_line_scr_ptr_lo),y
  rts

int_clear_cursor_line:
  ldy #TERMINAL_WIDTH
  dey
@col_loop:
  lda #' '
  sta (cursor_line_data_ptr_lo),y
  jsr ut_atascii_to_icode
  sta (cursor_line_scr_ptr_lo),y
  dey
  bpl @col_loop
  rts

int_clear_line:
  ldy #TERMINAL_WIDTH
  dey
@col_loop:
  lda #' '
  sta (g_temp_data_ptr_lo),y
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  dey
  bpl @col_loop
  rts

int_lines_to_bytes:
  tax
  lda #0
  sta MM_SIZEL
  sta MM_SIZEH
  cpx #0
  beq @done
@lines_loop:
  lda MM_SIZEL
  clc
  adc #TERMINAL_WIDTH
  sta MM_SIZEL
  bcc @nowrap
  inc MM_SIZEH
@nowrap:
  dex
  bne @lines_loop
@done:
  rts

; scrolls the entire area up N lines, discarding the top N lines.
;
; only moves data. the bottom N lines will now have garbage and the
; screen will need to be repainted. that is up to the caller.
;
; also doesn't protect against N >= height. do that yourself.
;
; inputs:
;   a - the number of lines to scroll up (N)
; modifies:
;   a,x,ZPB0-5
int_scroll_up_lines:
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

  lda #<TO_SIZE
  sec
  sbc MM_SIZEL
  sta MM_SIZEL
  lda #>TO_SIZE
  sbc MM_SIZEH
  sta MM_SIZEH
  jsr MM_MOVEDOWN
  rts

; advances to the start of the next line, scrolling the output if
; we're already on the last line.
;
; modifies:
;   a,x,y,ZPB0-5
int_advance_line:
  ldx cursory
  cpx #(TO_HEIGHT-1)
  beq @scroll
  inc cursory
  lda #0
  sta cursorx
  jsr int_update_cursor_line
  rts
@scroll:
  ; already on last line
  lda #1
  jsr int_scroll_up_lines
  jsr int_clear_cursor_line
  jsr to_repaint
  lda #0
  sta cursorx
  rts

; advances if a newline is pending, so the next char lands on a fresh
; line.
;
; modifies:
;   a,x,y,ZPB0-5
int_flush_pending_newline:
  lda pending_newline
  beq @done
  lda #0
  sta pending_newline
  jsr int_advance_line
@done:
  rts

; ends the current line and moves to the next one now.
;
; modifies:
;   a,x,y,ZPB0-5
to_end_line:
  lda #0
  sta pending_newline
  jsr int_advance_line
  rts

; appends the char. If we reach the end of the line, it moves to the
; next line, scrolling the viewport up if needed.
;
; inputs:
;   CMDDATA0 - the char
; outputs:
;   c        - set if we filled the last column
; modifies:
;   a,x,y,ZPB0-5
to_append_char:
  ; settle any owed newline before placing the char, so it
  ; lands on the right (possibly scrolled) line.
  jsr int_flush_pending_newline

  lda CMDDATA0
  jsr int_update_char

  ldx cursorx
  cpx #(TERMINAL_WIDTH-1)
  beq @wrap
  inx
  stx cursorx
  clc
  rts
@wrap:
  ; filled the last column. owe a newline instead of advancing now.
  lda #1
  sta pending_newline
  sec
  rts

; prints a null terminated string, ending the line after it.
; Not terribly efficient since it adds chars one by one amongst
; other issues. If you know you have full lines, use other
; routines as well.
;
; inputs:
;   CMDDATA0/1 - the str
; modifies:
;   a,x,y,ZPB0-5
to_println:
  ldy #0
@str_loop:
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
  jsr to_append_char
  pla
  sta CMDDATA1
  pla
  sta CMDDATA0
  pla
  tay
  iny
  bne @str_loop
@done:
  jsr to_end_line
  jsr int_update_cursor_line
  rts

; appends N lines of data into the area, scrolling up to make room as
; needed. the block starts on a blank line, which is the current line
; if cursorx is 0, otherwise the next line.
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
to_append_lines:
  to_append   = CMDDATA2
  extra       = CMDDATA3
  cursor_line = CMDDATA4

  jsr int_flush_pending_newline

  ; start_line = cursory + (cursorx != 0 ? 1 : 0)
  ; last_line  = start_line + to_append + extra - 1
  ; scroll     = max(0, last_line - (TO_HEIGHT-1))
  lda cursory
  ldx cursorx
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
  sbc #(TO_HEIGHT-1)
  bcc @room       ; fits, no scroll
  beq @room       ; fits exactly, no scroll
  pha             ; a = number of lines to scroll up
  lda #(TO_HEIGHT-1)
  sta cursor_line
  pla
  jsr int_scroll_up_lines
@room:
  ; land on the last line with a pending newline
  lda cursor_line
  sta cursory
  lda #0
  sta cursorx
  lda #1
  sta pending_newline
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
@clear_blank_loop:
  jsr int_clear_line
  jsr int_prev_line
  dex
  bne @clear_blank_loop
@done:
  jsr to_repaint
  rts

first_line_scr_ptr_lo:  .res 1
first_line_scr_ptr_hi:  .res 1
first_line_data_ptr_lo: .res 1
first_line_data_ptr_hi: .res 1
cursorx:                .res 1
cursory:                .res 1
pending_newline:        .res 1

to_data:                .res TO_SIZE
