.setcpu "6502"

.include "form.inc"
.include "atari.inc"
.include "config.inc"
.include "globals.inc"
.include "line_input.inc"
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
  jsr int_set_current_field
  lda cfg_field_kind,x
  cmp #FIELD_SELECT
  beq @select
  cmp #FIELD_TEXT
  beq @text
  cmp #FIELD_BUTTON
  beq @button
  jmp @done
@select:
  jsr int_draw_select
  jmp @done
@text:
  jsr int_draw_text
  jmp @done
@button:
  jsr int_draw_button
@done:
  jsr int_draw_hint
  rts

; repaints the field's line input, showing its cursor only while the
; field has focus.
;
; inputs:
;   current_field_idx - index into the field table
;   focused_flag      - $80 if the field is focused, $00 otherwise
; modifies:
;   a,x,y
int_draw_text:
  jsr int_draw_brackets
  jsr int_text_set_context
  jsr li_repaint
  lda focused_flag
  beq @hide
  jsr li_show_cursor
  jmp @done
@hide:
  jsr li_hide_cursor
@done:
  rts

; draws brackets around a field.
;
; inputs:
;   current_field_idx - index into the field table
; modifies:
;   a,x,y
int_draw_brackets:
  ldx current_field_idx
  lda cfg_field_scr_lo,x
  clc
  adc SCR_PTR_LO
  sta g_temp_scr_ptr_lo
  lda cfg_field_scr_hi,x
  adc SCR_PTR_HI
  sta g_temp_scr_ptr_hi

  lda g_temp_scr_ptr_lo
  bne @no_borrow
  dec g_temp_scr_ptr_hi
@no_borrow:
  dec g_temp_scr_ptr_lo

  ldy #0
  lda #ICODE_BRACKET_OPEN
  sta (g_temp_scr_ptr_lo),y
  ldy cfg_field_width,x
  iny
  lda #ICODE_BRACKET_CLOSE
  sta (g_temp_scr_ptr_lo),y
  rts

; sets the context for the selected line input
;
; inputs:
;   current_field_idx - index into the field table
; modifies:
;   a,x,y
int_text_set_context:
  ldx current_field_idx
  lda cfg_field_data_lo,x
  sta CMDDATA0
  lda cfg_field_data_hi,x
  sta CMDDATA1
  jsr li_set_context
  rts

; draws the button's label, inverted while the field has focus.
;
; inputs:
;   current_field_idx - index into the field table
;   focused_flag      - $80 if the field is focused, $00 otherwise
; modifies:
;   a,x,y
int_draw_button:
  ldx current_field_idx
  lda cfg_field_data_lo,x
  sta CMDDATA0
  lda cfg_field_data_hi,x
  sta CMDDATA1
  lda cfg_field_scr_lo,x
  sta CMDDATA2
  lda cfg_field_scr_hi,x
  sta CMDDATA3
  lda focused_flag
  sta CMDDATA4
  jsr scr_draw_str
  rts

; draws the hint to the right of the cell if the field type
; has a hint and the field is focused
;
; inputs:
;   current_field_idx - index into the field table
;   focused_flag      - $80 if the field is focused, $00 otherwise
; modifies:
;   a,x,y
int_draw_hint:
  ldx current_field_idx
  lda cfg_field_kind,x
  cmp #FIELD_SELECT
  bne @done

  lda #<hint_blank
  sta CMDDATA0
  lda #>hint_blank
  sta CMDDATA1

  lda focused_flag
  beq @position
  lda #<hint_select
  sta CMDDATA0
  lda #>hint_select
  sta CMDDATA1
@position:
  lda cfg_field_width,x
  clc
  adc #HINT_GAP
  adc cfg_field_scr_lo,x
  sta CMDDATA2
  lda cfg_field_scr_hi,x
  adc #0
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str
@done:
  rts

; sets current_field_idx based on the given form_item
;
; inputs:
;   form_item         - position within the form
; outputs:
;   current_field_idx - index into the field table
;   x                 - the same index
; modifies:
;   a,x
int_set_current_field:
  lda metadata+Form::first
  clc
  adc form_item
  sta current_field_idx
  tax
  rts

; handles the keyboard input
;
; inputs:
;   g_kbdcode_raw - the key
; outputs:
;   c             - set if the key was handled, clear otherwise
; modifies:
;   a,x,y
fm_handle_key:
  lda #FM_ACTION_NONE
  sta fm_action

  lda g_kbdcode_raw
  cmp #KEY_TAB
  beq @focus_next
  cmp #KEY_SHIFT_TAB
  beq @focus_prev

  jsr int_set_current_to_focused
  lda cfg_field_kind,x
  cmp #FIELD_SELECT
  beq @select_key
  cmp #FIELD_TEXT
  beq @text_key
  cmp #FIELD_BUTTON
  beq @button_key
  clc
  jmp @done
@focus_next:
  jsr int_focus_next
  sec
  jmp @done
@focus_prev:
  jsr int_focus_prev
  sec
  jmp @done
@select_key:
  jsr int_select_handle_key
  jmp @done
@text_key:
  jsr int_edit_text_field
  jmp @done
@button_key:
  jsr int_button_handle_key
@done:
  rts

; up and down arrows scroll a select's values
;
; inputs:
;   current_field_idx - index into the field table
;   g_kbdcode_raw     - the key
; outputs:
;   c                 - set if the key was used, clear otherwise
; modifies:
;   a,x,y
int_select_handle_key:
  lda g_kbdcode_raw
  cmp #KEY_CTRL_UP
  beq @prev
  cmp #KEY_CTRL_DOWN
  beq @next
  clc
  jmp @done
@prev:
  jsr int_select_prev_value
  sec
  jmp @done
@next:
  jsr int_select_next_value
  sec
@done:
  rts

; handles button presses. If return or space were pressed, it
; sets the action to be taken based on the field table.
;
; inputs:
;   current_field_idx - index into the field table
;   g_kbdcode_raw     - the key
; outputs:
;   fm_action         - the button's action when carry is set
;   c                 - set if the key was activated, clear otherwise
; modifies:
;   a,x
int_button_handle_key:
  lda g_kbdcode_raw
  cmp #KEY_RETURN
  beq @activate
  cmp #KEY_SPACE
  beq @activate
  clc
  jmp @done
@activate:
  ldx current_field_idx
  lda cfg_field_arg0,x
  sta fm_action
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

; handles a key press on a text field. Can filter keys but doesn't
; do any validation.
;
; inputs:
;   current_field_idx - index into the field table
;   g_kbdcode_raw     - the key
; outputs:
;   c                 - set if the key was accepted, clear if rejected
; modifies:
;   a,x,y
int_edit_text_field:
  lda g_kbdcode_raw
  cmp #KEY_CTRL_LEFT
  beq @cursor_left
  cmp #KEY_CTRL_RIGHT
  beq @cursor_right
  cmp #KEY_DELETE
  beq @backspace
  cmp #KEY_CTRL_DELETE
  beq @char_delete
  cmp #KEY_CTRL_INSERT
  beq @char_insert
  jmp @typechar
@cursor_left:
  jsr int_text_set_context
  jsr li_move_cursor_left
  jmp @handled
@cursor_right:
  jsr int_text_set_context
  jsr li_move_cursor_right
  jmp @handled
@backspace:
  jsr int_text_set_context
  jsr li_backspace
  jmp @handled
@char_delete:
  jsr int_text_set_context
  jsr li_char_delete
  jmp @handled
@char_insert:
  jsr int_text_set_context
  jsr li_char_insert
  jmp @handled
@typechar:
  jsr int_filter_char
  bcs @unused
  sta typed_char
  jsr int_text_set_context
  lda typed_char
  sta CMDDATA0
  jsr li_type_char
@handled:
  sec
  rts
@unused:
  clc
  rts

; tests the typed character against the set of characters the field
; allows and optionally modifies the typed char if any mods are set.
; arg0 in the field table indicates the filter. arg1 is the mods.
;
; inputs:
;   current_field_idx - index into the field table
;   g_kbdcode_atascii - the character
; outputs:
;   a                 - the character to type, when carry is clear
;   c                 - set if the field does not take the character
; modifies:
;   a,x
int_filter_char:
  ldx current_field_idx
  lda cfg_field_arg0,x
  sta char_classes
  and #CHAR_ALL
  bne @accept

  lda g_kbdcode_atascii
  cmp #' '
  beq @space
  cmp #'-'
  beq @dash
  cmp #','
  beq @comma
  jsr ut_is_alphanumeric
  bcc @alnum
  jmp @reject
@alnum:
  lda #CHAR_ALNUM
  jmp @test
@space:
  lda #CHAR_SPACE
  jmp @test
@dash:
  lda #CHAR_DASH
  jmp @test
@comma:
  lda #CHAR_COMMA
@test:
  and char_classes
  beq @reject
@accept:
  lda cfg_field_arg1,x
  and #INPUT_UPPER
  beq @as_typed
  lda g_kbdcode_atascii
  jsr ut_to_upper
  clc
  rts
@as_typed:
  lda g_kbdcode_atascii
  clc
  rts
@reject:
  sec
  rts

; moves the focused select field to the next value, wrapping to its first.
;
; inputs:
;   current_field_idx - index into the field table
; modifies:
;   a,x,y
int_select_next_value:
  jsr int_select_find_item
  iny
  cpy select_num_items
  bne @store
  ldy #0
@store:
  sty select_item_index
  jsr int_select_store_item
  rts

; moves the focused select field to the previous value, wrapping to its last.
;
; modifies:
;   a,x,y
int_select_prev_value:
  jsr int_select_find_item
  dey
  bpl @store
  ldy select_num_items
  dey
@store:
  sty select_item_index
  jsr int_select_store_item
  rts

; sets the current field and form_item to the field that is focused.
;
; outputs:
;   form_item         - the focused position
;   current_field_idx - index into the field table
;   x                 - the same index
; modifies:
;   a,x
int_set_current_to_focused:
  lda metadata+Form::focus
  sta form_item
  jsr int_set_current_field
  rts

; writes the item's value into the field's config byte and redraws the
; field with its new label.
;
; inputs:
;   select_item_index - the item's position in the field
;   g_temp_data_ptr   - the field's value table
;   field_ptr_lo/hi   - the field's config byte
; modifies:
;   a,x,y
int_select_store_item:
  ldy select_item_index
  lda (g_temp_data_ptr_lo),y
  ldy #0
  sta (field_ptr_lo),y
  lda #FIELD_FOCUSED
  sta focused_flag
  jsr int_draw_field
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

; reads the field's current config byte and finds which of the field's
; items holds it.
;
; inputs:
;   current_field_idx - index into the field table
; outputs:
;   y                 - the item's position in the field
;   x                 - current_field_idx
;   select_num_items  - how many items the field has
;   field_ptr_lo/hi   - points at the field's config byte
;   g_temp_data_ptr   - points at the field's value table
; modifies:
;   a,x,y
int_select_find_item:
  ldx current_field_idx
  lda cfg_field_data_lo,x
  sta field_ptr_lo
  lda cfg_field_data_hi,x
  sta field_ptr_hi
  ldy #0
  lda (field_ptr_lo),y
  sta select_value

  lda cfg_field_arg0,x
  sta select_num_items
  lda cfg_field_values_lo,x
  sta g_temp_data_ptr_lo
  lda cfg_field_values_hi,x
  sta g_temp_data_ptr_hi

  ldy #0
@value_loop:
  lda (g_temp_data_ptr_lo),y
  cmp select_value
  beq @done
  iny
  cpy select_num_items
  bne @value_loop
@done:
  rts

; draws the label matching the field's current config byte into its
; value cell, padded with spaces out to the field width.
;
; inputs:
;   current_field_idx - index into the field table
;   focused_flag      - $80 to draw it focused, $00 otherwise
; modifies:
;   a,x,y
int_draw_select:
  ldx current_field_idx
  lda cfg_field_width,x
  sta width

  lda cfg_field_scr_lo,x
  clc
  adc SCR_PTR_LO
  sta g_temp_scr_ptr_lo
  lda cfg_field_scr_hi,x
  adc SCR_PTR_HI
  sta g_temp_scr_ptr_hi

  jsr int_select_find_item

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
current_field_idx: .res 1
focused_flag:      .res 1
new_focus:         .res 1

width:             .res 1
select_value:      .res 1
select_num_items:  .res 1
select_item_index: .res 1
typed_char:        .res 1
char_classes:      .res 1
fm_action:         .res 1

hint_select:       .byte $1c|$80,$1d|$80,$00
hint_blank:        .byte "  ",$00
