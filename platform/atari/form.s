.setcpu "6502"

.include "form.inc"
.include "atari.inc"
.include "config.inc"
.include "globals.inc"
.include "screen.inc"
.include "utils.inc"

.segment "ZEROPAGE"
context_ptr_lo: .res 1
context_ptr_hi: .res 1
field_ptr_lo:   .res 1
field_ptr_hi:   .res 1

.segment "CODE"

; sets the context for the form to the Form pointed to by CMDDATA0/1,
; keeping a local copy of it. the copy is written back to the previous
; Form on the next switch.
;
; inputs:
;   CMDDATA0/1 - pointer to a Form
; modifies:
;   a,y
fm_set_context:
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
  ut_copy_struct_abs_to_zp metadata, context_ptr_lo, Form
no_cache:
  lda CMDDATA0
  sta context_ptr_lo
  lda CMDDATA1
  sta context_ptr_hi

  ut_copy_struct_zp_to_abs context_ptr_lo, metadata, Form
set_context_done:
  rts

; draws every field on the current form, inverting the focused one
;
; modifies:
;   a,x,y
fm_draw_all:
  lda #0
  sta form_item
@fields_loop:
  jsr int_set_focused_flag
  jsr int_draw_field
  inc form_item
  lda metadata+Form::count
  cmp form_item
  bne @fields_loop
  rts

; sets focused flag based on whether form_item is the focused field.
;
; inputs:
;   form_item - position within the form
; modifies:
;   a
int_set_focused_flag:
  lda #0
  sta focused_flag
  lda metadata+Form::focus
  cmp form_item
  bne @done
  lda #FIELD_FOCUSED
  sta focused_flag
@done:
  rts

; draws one field of the form, highlighting it if focused 
;
; inputs:
;   form_item    - position within the form
;   focused_flag - $80 to draw it focused, $00 otherwise
; modifies:
;   a,x,y
int_draw_field:
  lda metadata+Form::first
  clc
  adc form_item
  sta field_table_index
  tax
  lda cfg_field_kind,x
  cmp #FIELD_SELECT
  beq @select
  jmp @done
@select:
  jsr int_draw_select
@done:
  rts

; handles keyboard inputs used by the form
;
; inputs:
;   g_kbdcode_raw - the key
; outputs:
;   carry - set if the key was handled, clear otherwise
; modifies:
;   a,x,y
fm_handle_key:
  lda g_kbdcode_raw
  cmp #KEY_TAB
  beq @focus_next
  cmp #KEY_SHIFT_TAB
  beq @focus_prev
  clc
  jmp @done
@focus_next:
  jsr int_focus_next
  sec
  jmp @done
@focus_prev:
  jsr int_focus_prev
  sec
@done:
  rts

; moves focus to the next field, wrapping to the first.
;
; modifies:
;   a,x,y
int_focus_next:
  ldx metadata+Form::focus
  inx
  cpx metadata+Form::count
  bne @store
  ldx #0
@store:
  stx new_focus
  jsr int_move_focus
  rts

; moves focus to the previous field, wrapping to the last.
;
; modifies:
;   a,x,y
int_focus_prev:
  ldx metadata+Form::focus
  dex
  bpl @store
  ldx metadata+Form::count
  dex
@store:
  stx new_focus
  jsr int_move_focus
  rts

; moves focus to new_focus, redrawing the field that loses focus and
; the one that gets it.
;
; inputs:
;   new_focus - position within the form of the field that gets focus
; modifies:
;   a,x,y
int_move_focus:
  lda metadata+Form::focus
  sta form_item
  lda #0
  sta focused_flag
  jsr int_draw_field

  lda new_focus
  sta metadata+Form::focus
  sta form_item
  lda #FIELD_FOCUSED
  sta focused_flag
  jsr int_draw_field
  rts

; draws the label matching the field's current config byte into its
; value cell, padded with spaces out to the field width.
;
; inputs:
;   field_table_index - index into the field table
;   focused_flag      - $80 to draw it focused, $00 otherwise
; modifies:
;   a,x,y
int_draw_select:
  ldx field_table_index
  lda cfg_field_width,x
  sta width

  lda cfg_field_scr_lo,x
  clc
  adc SCR_PTR_LO
  sta g_temp_scr_ptr_lo
  lda cfg_field_scr_hi,x
  adc SCR_PTR_HI
  sta g_temp_scr_ptr_hi

  lda cfg_field_data_lo,x
  sta field_ptr_lo
  lda cfg_field_data_hi,x
  sta field_ptr_hi
  ldy #0
  lda (field_ptr_lo),y
  sta value

  lda cfg_field_extra,x
  sta select_num_items
  lda cfg_field_values_lo,x
  sta g_temp_data_ptr_lo
  lda cfg_field_values_hi,x
  sta g_temp_data_ptr_hi

  ldy #0
@value_loop:
  lda (g_temp_data_ptr_lo),y
  cmp value
  beq @value_found
  iny
  cpy select_num_items
  bne @value_loop
@value_found:
  ; the label pointers are ALL the lo bytes followed by ALL the hi bytes
  lda cfg_field_labels_lo,x
  sta field_ptr_lo
  lda cfg_field_labels_hi,x
  sta field_ptr_hi
  lda (field_ptr_lo),y
  sta g_temp_data_ptr_lo
  tya
  clc
  adc select_num_items
  tay
  lda (field_ptr_lo),y
  sta g_temp_data_ptr_hi

  ldy #0
@label_loop:
  cpy width
  beq @done
  lda (g_temp_data_ptr_lo),y
  beq @pad
  jsr ut_atascii_to_icode
  ora focused_flag
  sta (g_temp_scr_ptr_lo),y
  iny
  bne @label_loop
@pad:
  lda #ICODE_SPACE
  ora focused_flag
@pad_loop:
  cpy width
  beq @done
  sta (g_temp_scr_ptr_lo),y
  iny
  bne @pad_loop
@done:
  rts

metadata:          .tag Form
form_item:         .res 1
field_table_index: .res 1
focused_flag:      .res 1
new_focus:         .res 1

width:             .res 1
value:             .res 1
select_num_items:  .res 1
