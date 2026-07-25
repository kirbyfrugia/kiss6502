.setcpu "6502"

.include "atari.inc" ; /usr/share/cc65/asminc/atari.inc
.include "boot850.inc"
.include "config.inc"
.include "globals.inc"
.include "macros.inc"
.include "main.inc"
.include "line_input.inc"
.include "term_line_input.inc"
.include "term_multi_input.inc"
.include "term_output.inc"
.include "protocol_kiss.inc"
.include "rs232.inc"
.include "screen.inc"
.include "term.inc"
.include "text_area.inc"
.include "utils.inc"

.segment "CODE"

RS232_CHANNEL     = 32 ; channel 2 (2 * 16)

PORT_STATUS_OK    = %00000000
PORT_STATUS_ERROR = %10000000

trm_init:
  lda #PORT_STATUS_OK
  sta port_status
  lda #TERM_MODE::NONE
  sta current_mode

  jsr to_init
  jsr tmi_init
  jsr tli_init
@done:
  rts

.macro draw_divider line_offset
  lda SCR_PTR_LO
  clc
  adc #<line_offset
  sta ZPB0
  lda SCR_PTR_HI
  adc #>line_offset
  sta ZPB1

  lda #$52 ; horizontal bar
  ldy #(SCREEN_WIDTH-1)
@loop:
  sta (ZPB0),y
  dey
  bpl @loop
.endmacro


; draws the line mode specific part of the ui
int_draw_ui_multi_line_input:
  jsr int_draw_ui_base
  draw_divider (SCREEN_WIDTH*19)
  rts

; draws the char mode specific part of the ui
int_draw_ui_single_line_input:
  jsr int_draw_ui_base
  draw_divider (SCREEN_WIDTH*22)

  CURSOR_POS .set (SCREEN_WIDTH*23)
  lda SCR_PTR_LO
  clc
  adc #<CURSOR_POS
  sta ZPB0
  lda SCR_PTR_HI
  adc #>CURSOR_POS
  sta ZPB1
  ldy #0
  lda #'>'
  jsr ut_atascii_to_icode
  sta (ZPB0),y

  rts

int_draw_ui_base:
  lda SCR_PTR_LO
  sta ZPB0
  lda SCR_PTR_HI
  sta ZPB1

  ldy #(SCREEN_WIDTH-1)
  lda #' '
  eor #$80
  jsr ut_atascii_to_icode
@top_banner_clear_loop:
  sta (ZPB0),y
  dey
  bpl @top_banner_clear_loop

  ldy #0
@top_banner_loop:
  lda top_banner,y
  beq @top_banner_done
  eor #$80
  jsr ut_atascii_to_icode
  sta (ZPB0),y
  iny
  jmp @top_banner_loop
@top_banner_done:
@done:
  rts

int_repaint_char_mode:
  jsr to_repaint
  jsr int_draw_ui_single_line_input

  CURSOR_POS .set (SCREEN_WIDTH*23)+1
  lda SCR_PTR_LO
  clc
  adc #<CURSOR_POS
  sta ZPB0
  lda SCR_PTR_HI
  adc #>CURSOR_POS
  sta ZPB1
  ldy #0
  lda (ZPB0),y
  ora #%10000000
  sta (ZPB0),y

  rts

int_reset_char_mode:
  lda #TO_HEIGHT_SINGLE_LINE_INPUT
  jsr to_resize
  jsr int_draw_ui_single_line_input
  rts

int_repaint_line_mode:
  jsr to_repaint
  jsr tli_hide_cursor
  jsr tli_repaint
  jsr tli_show_cursor
  jsr int_draw_ui_single_line_input
  rts

int_reset_line_mode:
  lda #TO_HEIGHT_SINGLE_LINE_INPUT
  jsr to_resize
  jsr tli_reset
  jsr int_draw_ui_single_line_input
  rts

int_repaint_multi_mode:
  jsr to_repaint
  jsr tmi_hide_cursor
  jsr tmi_repaint
  jsr tmi_show_cursor
  jsr int_draw_ui_multi_line_input
  rts

int_reset_multi_mode:
  lda #TO_HEIGHT_MULTI_LINE_INPUT
  jsr to_resize
  jsr tmi_reset
  jsr int_draw_ui_multi_line_input
  rts

int_reset_protocol:
  lda cfg_saved_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::TERM
  beq @term
  cmp #TERM_PROTOCOL::APRS
  beq @aprs
  bne @done
@term:
  jmp @done
@aprs:
  jsr pk_reset
  jmp @done
@done:
  rts

int_repaint:
  lda cfg_saved_config+Cfg::serial+CfgSerial::mode
  cmp #TERM_MODE::CHAR
  beq @char_mode
  cmp #TERM_MODE::MULTI
  beq @multi_mode
  jsr int_repaint_line_mode
  jmp @done
@char_mode:
  jsr int_repaint_char_mode
  jmp @done
@multi_mode:
  jsr int_repaint_multi_mode
@done:
  rts


int_reset:
  jsr int_reset_protocol
  lda cfg_saved_config+Cfg::serial+CfgSerial::mode
  cmp #TERM_MODE::CHAR
  beq @char_mode
  cmp #TERM_MODE::MULTI
  beq @multi_mode
  jsr int_reset_line_mode
  jmp @welcome
@char_mode:
  jsr int_reset_char_mode
  jmp @welcome
@multi_mode:
  jsr int_reset_multi_mode
@welcome:
  print_str str_welcome
@done:
  rts

trm_activate:
  lda #PORT_STATUS_OK
  sta port_status
  lda #CONFIG_FLAG_CANCELED
  bit cfg_config_flag
  bvc @just_repaint ; canceled
  jsr int_reset
  jsr int_repaint
  jsr int_cmd_boot850
  jsr int_cmd_open_rs232
  jmp @done
@just_repaint:
  jsr int_repaint
@done:
  rts

trm_tick:
  lda cfg_saved_config+Cfg::serial+CfgSerial::mode
  cmp #TERM_MODE::CHAR
  beq @char_mode
  cmp #TERM_MODE::MULTI
  beq @multi_mode
  jsr int_handle_kbd_line_mode
  jmp @rs232
@char_mode:
  jsr int_handle_kbd_char_mode
  jmp @rs232
@multi_mode:
  jsr int_handle_kbd_multi_mode
@rs232:
  lda port_status
  cmp #PORT_STATUS_OK
  bne @done
  jsr int_cmd_get_rs232
@done:
  rts

int_cmd_line_mode_move_cursor_left:
  jsr tli_move_cursor_left
  rts

int_cmd_line_mode_move_cursor_right:
  jsr tli_move_cursor_right
  rts

int_cmd_line_mode_handle_char:
  lda g_kbdcode_atascii
  beq @done
  sta CMDDATA0
  jsr tli_type_char
@done:
  rts

int_cmd_line_mode_backspace:
  jsr tli_backspace
  rts

int_cmd_line_mode_shift_clear:
  jsr tli_shift_clear
  rts

int_cmd_line_mode_char_insert:
  jsr tli_char_insert
  rts

int_cmd_line_mode_char_delete:
  jsr tli_char_delete
  rts

int_cmd_line_mode_return:
;  lda #<tli_data
;  sta CMDDATA0
;  lda #>tli_data
;  sta CMDDATA1
;  lda #1
;  sta CMDDATA2
;  lda #0
;  sta CMDDATA3
;  jsr to_append_lines

  lda #<tli_data
  sta CMDDATA0
  lda #>tli_data
  sta CMDDATA1
  lda #<pk_broadcast_addressee
  sta CMDDATA2
  lda #>pk_broadcast_addressee
  sta CMDDATA3
  lda tli_metadata+LineInput::data_len
  sta CMDDATA4
  lda #KISS_SEND_FLAG_TRIM_END
  sta CMDDATA5
  jsr pk_send_message
  bcc iclmr_success
  print_str_with_code str_error_rs232_putchr, g_copy_buffer40, pk_error
iclmr_success:
  jsr tli_shift_clear
  rts

int_cmd_multi_mode_move_cursor_up:
  jsr tmi_edit_move_cursor_up
  rts

int_cmd_multi_mode_move_cursor_down:
  jsr tmi_edit_move_cursor_down
  rts

int_cmd_multi_mode_move_cursor_left:
  lda #CURSOR_BEHAVIOR_WRAP_SAME_LINE
  sta CMDDATA0
  jsr tmi_edit_move_cursor_left
  rts

int_cmd_multi_mode_move_cursor_right:
  lda #CURSOR_BEHAVIOR_WRAP_SAME_LINE
  sta CMDDATA0
  jsr tmi_edit_move_cursor_right
  rts

int_cmd_multi_mode_handle_char:
  lda g_kbdcode_atascii
  beq @done
  sta CMDDATA0
  jsr tmi_edit_type_char
@done:
  rts

int_cmd_multi_mode_backspace:
  jsr tmi_edit_backspace
  rts

int_cmd_multi_mode_shift_clear:
  jsr tmi_shift_clear
  rts

int_cmd_multi_mode_line_insert:
  jsr tmi_edit_line_insert
  rts

int_cmd_multi_mode_char_insert:
  jsr tmi_edit_char_insert
  rts

int_cmd_multi_mode_line_delete:
  jsr tmi_edit_line_delete
  rts

int_cmd_multi_mode_char_delete:
  jsr tmi_edit_char_delete
  rts

int_cmd_multi_mode_return:
  lda #<tmi_data
  sta CMDDATA0
  lda #>tmi_data
  sta CMDDATA1
  lda tmi_metadata+TextArea::size
  sta CMDDATA2
  jsr ut_str_trim_end_find

  lda ut_result
  beq @done; was an empty string
  sta CMDDATA2
  jsr rs232_putchrs
  bcc @done
  print_str_with_code str_error_rs232_putchr, g_copy_buffer40, pk_error
;  lda #<tmi_data
;  sta CMDDATA0
;  lda #>tmi_data
;  sta CMDDATA1
;  lda tmi_metadata+TextArea::height
;  sta CMDDATA2
;  lda #0
;  sta CMDDATA3
;  jsr to_append_lines
@done:
  jsr tmi_shift_clear
  rts

int_handle_kbd_char_mode:
  lda g_kbd_key_pressed
  beq @done
  lda g_kbdcode_atascii
  beq @done
  jsr int_cmd_put_rs232

;  lda g_kbdcode_atascii
;  sta CMDDATA0
;  jsr to_append_char
@done:
  rts

int_handle_kbd_line_mode:
  lda g_kbd_key_pressed
  beq @done
  lda g_kbdcode_raw 
  cmp #$86
  beq @left_arrow
  cmp #$87
  beq @right_arrow
  cmp #$0c
  beq @return
  cmp #$34
  beq @backspace
  cmp #$76 ; shift+clear ($b4 on atari 800 emulator)
  beq @shift_clear
  cmp #$b6 ; ctrl+clear
  beq @shift_clear
  cmp #$74 ; shift+delete bs
  beq @shift_clear
  cmp #$b7 ; ctrl+insert
  beq @char_insert
  cmp #$b4 ; ctrl+delete bs
  beq @char_delete
@output:
  jsr int_cmd_line_mode_handle_char
  jmp @done
@left_arrow:
  jmp int_cmd_line_mode_move_cursor_left
  jmp @done
@right_arrow:
  jmp int_cmd_line_mode_move_cursor_right
  jmp @done
@backspace:
  jsr int_cmd_line_mode_backspace
  jmp @done
@shift_clear:
  jsr int_cmd_line_mode_shift_clear
  jmp @done
@char_insert:
  jsr int_cmd_line_mode_char_insert
  jmp @done
@char_delete:
  jsr int_cmd_line_mode_char_delete
  jmp @done
@return:
  jsr int_cmd_line_mode_return
@done:
  rts
  
int_handle_kbd_multi_mode:
  lda g_kbd_key_pressed
  beq @done
  lda g_kbdcode_raw 
  cmp #$8e
  beq @up_arrow
  cmp #$8f
  beq @down_arrow
  cmp #$86
  beq @left_arrow
  cmp #$87
  beq @right_arrow
  cmp #$0c
  beq @return
  cmp #$34
  beq @backspace
  cmp #$76 ; shift+clear ($b4 on atari 800 emulator)
  beq @shift_clear
  cmp #$b6 ; ctrl+clear
  beq @shift_clear
  cmp #$77 ; shift+insert on atari ($7c on atari800 emulator)
  beq @line_insert
  cmp #$b7 ; ctrl+insert
  beq @char_insert
  cmp #$74 ; shift+delete bs
  beq @line_delete
  cmp #$b4 ; ctrl+delete bs
  beq @char_delete
@output:
  jsr int_cmd_multi_mode_handle_char
  jmp @done
@up_arrow:
  jmp int_cmd_multi_mode_move_cursor_up
  jmp @done
@down_arrow:
  jmp int_cmd_multi_mode_move_cursor_down
  jmp @done
@left_arrow:
  jmp int_cmd_multi_mode_move_cursor_left
  jmp @done
@right_arrow:
  jmp int_cmd_multi_mode_move_cursor_right
  jmp @done
@backspace:
  jsr int_cmd_multi_mode_backspace
  jmp @done
@shift_clear:
  jsr int_cmd_multi_mode_shift_clear
  jmp @done
@line_insert:
  jsr int_cmd_multi_mode_line_insert
  jmp @done
@char_insert:
  jsr int_cmd_multi_mode_char_insert
  jmp @done
@line_delete:
  jsr int_cmd_multi_mode_line_delete
  jmp @done
@char_delete:
  jsr int_cmd_multi_mode_char_delete
  jmp @done
@return:
  jsr int_cmd_multi_mode_return
@done:
  rts


int_cmd_boot850:
  jsr boot850_check
  bcc @rhandler_loaded
  print_str str_loading_850
  jsr boot850_bootstrap
  bcc @rhandler_bootstrapped
  print_str str_error_loading_850
  jmp @error
@rhandler_bootstrapped:
  jsr boot850_check
  bcc @rhandler_loaded
  print_str str_error_missing_850
  jmp @error
@rhandler_loaded:
  print_str str_loaded_850
  jmp @done
@error:
  lda #PORT_STATUS_ERROR 
  sta port_status
@done:
  rts

int_cmd_open_rs232:
  print_str str_opening_rs232
  ldx #RS232_CHANNEL
  jsr rs232_open
  bcs @error
  print_str str_opened_rs232
  jmp @done
@error:
  sty command_error
  sty port_status
  print_str_with_code str_error_rs232_open, g_copy_buffer40, command_error
  jsr int_print_status
@done:
  rts

int_handle_byte_read:
  lda cfg_saved_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::TERM
  beq @term
  cmp #TERM_PROTOCOL::APRS
  beq @aprs
  bne @done
@term:
  lda rs232_byte_read
  sta CMDDATA0
  jsr to_append_char
  jmp @done
@aprs:
  lda rs232_byte_read
  sta CMDDATA0
  jsr pk_new_byte
  lda pk_state
  and #KISS_FRAME_READY
  beq @done
@aprs_frame_ready:
  jsr int_handle_kiss_frame
  jsr pk_next_frame
@done:
  rts

int_handle_kiss_frame:
  jsr pk_process_frame

  lda g_disp_buf_num_lines
  beq @done

  lda #<g_disp_buf
  sta CMDDATA0
  lda #>g_disp_buf
  sta CMDDATA1
  lda g_disp_buf_num_lines
  sta CMDDATA2
  lda #1
  sta CMDDATA3
  jsr to_append_lines

;  ; for now, I'm testing a 4 line message.
;  ; it's just a hack for now, get over it.
;  
;  ; clear out the first 4 lines of the display buf
;
;  ldy #0
;  lda #' '
;@clear_loop:
;  sta g_disp_buf, y
;  iny
;  cpy #(38*4)
;  bne @clear_loop
;
;  ldy #0
;  lda #KissFrameHeader::source
;  jsr int_addr_to_disp_buf
;  
;  iny
;  lda #'>'
;  sta g_disp_buf,y
;
;  iny
;  lda #KissFrameHeader::dest
;  jsr int_addr_to_disp_buf
;
;  iny
;  lda #':'
;  sta g_disp_buf,y
;
;  lda #<g_disp_buf
;  sta CMDDATA0
;  lda #>g_disp_buf
;  sta CMDDATA1
;  lda #4
;  sta CMDDATA2
;  jsr to_append_lines
;
@done:
  rts

int_print_status:
  jsr rs232_status
  print_str_with_code str_last_status, g_copy_buffer40, rs232_last_status
@done:
  rts

int_cmd_get_rs232:
  jsr rs232_status
  bcs @error_status
  lda rs232_input_buffer_size+1
  bne @read
  lda rs232_input_buffer_size
  bne @read
  jmp @done
@read:
  jsr rs232_getchr
  bcc @read_success
  jmp @error_getchr
@read_success:
  sta rs232_byte_read

  jsr int_handle_byte_read

  jmp @done
@error_status:
  sty command_error
  sty port_status
  print_str_with_code str_error_rs232_status, g_copy_buffer40, command_error
  jsr int_print_status
  jmp @done
@error_getchr:
  sty command_error
  sty port_status
  print_str_with_code str_error_rs232_getchr, g_copy_buffer40, command_error
  jsr int_print_status
@done:
  rts


; writes a single char from kbd to rs232
int_cmd_put_rs232:
  lda port_status
  cmp #PORT_STATUS_OK
  bne @done
  lda g_kbdcode_atascii
  beq @done
  jsr rs232_putchr
  bcs @error_putchr
  jmp @done
@error_putchr:
  sty command_error
  sty port_status
  print_str_with_code str_error_rs232_putchr, g_copy_buffer40, command_error
  jsr int_print_status
@done:
  rts

top_banner:                  .byte ' ','S'|$80,'E'|$80,'L'|$80,"config "
                             .byte $00
current_mode:                .res 1
str_welcome:                 .byte "Welcome!",$00

str_loading_850:             .byte "Loading 850...",$00
str_loaded_850:              .byte "850 handler loaded",$00
str_error_missing_850:       .byte "850 not in HATABS",$00
str_error_loading_850:       .byte "850 load error",$00
str_error:                   .byte "Error",$00
str_last_status:             .byte "Last status",$00
str_opening_rs232:           .byte "Opening RS232 port...",$00
str_opened_rs232:            .byte "RS232 port opened",$00
str_error_rs232_open:        .byte "Error opening RS232 port",$00
str_error_rs232_open_code:   ; used as index to print error code for above str
str_error_rs232_status:      .byte "Error on RS232 status",$00
str_error_rs232_status_code: ; used as index to print error code for above str
str_error_rs232_getchr:      .byte "Error on RS232 getchr",$00
str_error_rs232_getchr_code: ; used as index to print error code for above str
str_error_rs232_putchr:      .byte "Error on RS232 putchr",$00
str_error_rs232_putchr_code: ; used as index to print error code for above str
command_error:               .byte 0

rs232_byte_read:             .byte 0
port_status:                 .byte 0
tempy_delete_later:          .byte 0
