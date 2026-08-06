.ifndef LINE_INPUT_INC
LINE_INPUT_INC = 1

.struct LineInput
  scr_ptr         .res 2 ; ptr to the mem location of leftmost char
  data_ptr        .res 2 ; ptr to the start of the data
  num_visible     .res 1 ; max number of chars visible on screen
  data_size       .res 1 ; size of the data buffer
  scr_cursor      .res 1 ; idx to cursor in screen
  data_cursor     .res 1 ; idx to cursor in data array
  first_visible   .res 1 ; first char idx visible on screen
.endstruct

.globalzp li_metadata
.global   li_init_context
.global   li_set_context
.global   li_set_data_size
.global   li_repaint
.global   li_hide_cursor
.global   li_show_cursor
.global   li_move_cursor_left
.global   li_move_cursor_right
.global   li_char_delete
.global   li_char_insert
.global   li_type_char
.global   li_backspace
.global   li_shift_clear

scr_ptr_lo      = li_metadata+LineInput::scr_ptr
scr_ptr_hi      = li_metadata+LineInput::scr_ptr+1
data_ptr_lo     = li_metadata+LineInput::data_ptr
data_ptr_hi     = li_metadata+LineInput::data_ptr+1

LI_MAX_LINE_LEN = 255


.endif
