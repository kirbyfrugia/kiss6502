.setcpu "6502"
.include "line_input.inc"
.include "globals.inc"
.include "macros.inc"
.include "memmove.inc"
.include "utils.inc"

.segment "ZEROPAGE"
li_metadata:    .tag LineInput
context_ptr_lo: .res 1
context_ptr_hi: .res 1

.segment "CODE"

li_init_context:
  lda #0
  sta context_ptr_lo
  sta context_ptr_hi
  rts

; sets the context for the line input to the LineInput
; pointed to by CMDDATA0/1. Make sure that you called
; li_init_context first or you might get some garbage.
;
; inputs:
;   CMDDATA0/1 - pointer to a line input
li_set_context:
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
  ; copy our local cache to the existing source LineInput
  copy_struct_abs_to_zp li_metadata, context_ptr_lo, LineInput
no_cache:
  ; now point to the new line input
  lda CMDDATA0
  sta context_ptr_lo
  lda CMDDATA1
  sta context_ptr_hi

  ; copy data from the new LineInput to the local cache in
  ; the zero page.
  copy_struct_zp_to_abs context_ptr_lo, li_metadata, LineInput
set_context_done:
  rts

li_repaint:
  ldx li_metadata+LineInput::first_visible
  ldy #0
@loop:
  sty tempy
  cpx li_metadata+LineInput::data_len
  bcs @fill_char ; past end of data 
  txa
  tay
  lda (data_ptr_lo),y
  jmp @draw_char
@fill_char:
  lda #' '
@draw_char:
  jsr ut_atascii_to_icode
  ldy tempy
  sta (scr_ptr_lo),y
  inx
  iny
  cpy li_metadata+LineInput::num_visible
  bne @loop
  rts

li_hide_cursor:
  ldy li_metadata+LineInput::scr_cursor
  lda (scr_ptr_lo),y
  and #%01111111
  sta (scr_ptr_lo),y
@done:
  rts

li_show_cursor:
  ldy li_metadata+LineInput::scr_cursor
  lda (scr_ptr_lo),y
  ora #%10000000
  sta (scr_ptr_lo),y
@done:
  rts

li_move_cursor_left:
  jsr li_hide_cursor
  jsr int_move_cursor_left
  jsr li_show_cursor
  rts

li_move_cursor_right:
  jsr li_hide_cursor
  jsr int_move_cursor_right
  jsr li_show_cursor
  rts

; erases the char under the cursor by moving all
; the chars to the right one space left
li_char_delete:
  ; MM_FROM = data_cursor + 1 + data_ptr
  lda li_metadata+LineInput::data_cursor
  clc
  adc #1
  bcs @done ; data cursor wrapped

  adc data_ptr_lo
  sta MM_FROM
  lda data_ptr_hi
  adc #0
  sta MM_FROM+1

  ; MM_TO = MM_FROM - 1
  lda MM_FROM
  sec 
  sbc #1
  sta MM_TO
  lda MM_FROM+1
  sbc #0
  sta MM_TO+1

  ; MM_SIZE = data_len - data_cursor - 1
  lda li_metadata+LineInput::data_len
  sec
  sbc li_metadata+LineInput::data_cursor
  sta MM_SIZEL
  dec MM_SIZEL
  lda #0
  sta MM_SIZEH

  jsr li_hide_cursor
  jsr MM_MOVEDOWN
  ; fill last char with a blank
  ldy li_metadata+LineInput::data_len
  dey
  lda #' '
  sta (data_ptr_lo),y
  jsr li_repaint
  jsr li_show_cursor
@done:
  rts

; makes space for a new character by moving the char
; under the cursor to the right along with all following chars
li_char_insert:
  ; check if at far right. In that case just blank last char
  ldy li_metadata+LineInput::data_cursor
  iny
  cpy li_metadata+LineInput::data_len
  beq @blank; already at end

  ; MM_FROM = data_ptr + cursor
  lda data_ptr_lo
  clc
  adc li_metadata+LineInput::data_cursor
  sta MM_FROM
  lda data_ptr_hi
  adc #0
  sta MM_FROM+1

  ; MM_TO = MM_FROM+1
  lda MM_FROM
  clc
  adc #1
  sta MM_TO
  lda MM_FROM+1
  adc #0
  sta MM_TO+1

  ; MM_SIZE = data_len - data_cursor +1
  lda li_metadata+LineInput::data_len
  sec
  sbc li_metadata+LineInput::data_cursor
  clc
  adc #1
  sta MM_SIZEL
  lda #0
  sta MM_SIZEH

  jsr li_hide_cursor
  jsr MM_MOVEUP_SS
@blank:
  ; fill last cursor char with a blank
  lda #' '
  ldy li_metadata+LineInput::data_cursor
  sta (data_ptr_lo),y
  jsr li_repaint
  jsr li_show_cursor
  rts

; sets the character at the current cursor location to the
; char in CMDDATA0. moves the cursor to the right.
;
; inputs
;   CMDDATA0 - the character
li_type_char:
  jsr li_hide_cursor
  lda CMDDATA0 
  jsr int_update_char
  jsr int_move_cursor_right
  jsr li_show_cursor
  rts

; moves cursor left, erases character under cursor
; atari style doesn't shift data left.
li_backspace:
  jsr li_hide_cursor
  jsr int_move_cursor_left
  lda #' '
  jsr int_update_char
  jsr li_show_cursor
  rts

li_shift_clear:
  jsr li_hide_cursor
  jsr int_cursor_home
  jsr int_clear
  jsr li_repaint
  jsr li_show_cursor

  rts

; updates the char at the current cursor position
; to A.
; modifies:
;   A
int_update_char:
  ldy li_metadata+LineInput::data_cursor
  sta (data_ptr_lo),y
  jsr ut_atascii_to_icode
  ldy li_metadata+LineInput::scr_cursor
  sta (scr_ptr_lo),y
  rts

; clears the data
; modifies:
;   a,y
int_clear:
  ldy li_metadata+LineInput::data_len
  dey
  lda #' '
@loop:
  sta (data_ptr_lo),y
  dey
  bne @loop
  sta (data_ptr_lo),y
  rts

int_move_cursor_left:
  lda li_metadata+LineInput::data_cursor
  beq @done

  lda li_metadata+LineInput::scr_cursor
  beq @at_scr_beg; cursor at far left
  dec li_metadata+LineInput::scr_cursor
  dec li_metadata+LineInput::data_cursor
  jmp @done
@at_scr_beg:
  ; can scroll if first_visible > 0
  lda li_metadata+LineInput::first_visible
  beq @done; at beginning of data
  dec li_metadata+LineInput::data_cursor
  dec li_metadata+LineInput::first_visible
  jsr li_repaint
@done:
  rts

int_move_cursor_right:
  ldy li_metadata+LineInput::data_cursor
  iny
  cpy li_metadata+LineInput::data_len
  bcc @move_allowed
  bcs @done
@move_allowed:
  ldy li_metadata+LineInput::scr_cursor
  iny
  cpy li_metadata+LineInput::num_visible
  beq @at_scr_end; at end on right

  inc li_metadata+LineInput::scr_cursor
  inc li_metadata+LineInput::data_cursor
  jmp @done
@at_scr_end:
  ; can scroll if:
  ;   first_visible + num_visible < data_len
  lda li_metadata+LineInput::first_visible
  clc
  adc li_metadata+LineInput::num_visible
  cmp li_metadata+LineInput::data_len
  bcs @done; can't scroll
  inc li_metadata+LineInput::first_visible
  inc li_metadata+LineInput::data_cursor
  jsr li_repaint
@done:
  rts

int_cursor_home:
  lda #0
  sta li_metadata+LineInput::scr_cursor
  sta li_metadata+LineInput::data_cursor
  sta li_metadata+LineInput::first_visible
  rts

tempy: .res 1
