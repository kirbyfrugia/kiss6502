.setcpu "6502"

.include "atari.inc" ; /usr/share/cc65/asminc/atari.inc
.include "boot850.inc"
.include "config.inc"
.include "globals.inc"
.include "main.inc"
.include "line_input.inc"
.include "term_output.inc"
.include "protocol_kiss.inc"
.include "rs232.inc"
.include "screen.inc"
.include "term.inc"
.include "utils.inc"

.segment "CODE"

RS232_CHANNEL          = 32 ; channel 2 (2 * 16)

PORT_STATUS_OK         = 0
PORT_STATUS_OPENING    = 1
PORT_STATUS_NO_HANDLER = 2

BAR_TX_LABEL_COL       = 1
BAR_TX_COL             = 5
BAR_STATUS_LABEL_COL   = 24
BAR_STATUS_COL         = 32
BAR_ROW_OFFSET         = SCREEN_WIDTH*22

PROMPT_OFFSET          = SCREEN_WIDTH*23
INPUT_OFFSET           = PROMPT_OFFSET+1
INPUT_MAX_LEN          = 67

trm_init:
  lda #PORT_STATUS_OK
  sta port_status
  lda #TERM_MODE::NONE
  sta current_mode

  jsr to_init
  jsr int_init_cmd_line
@done:
  rts

int_init_cmd_line:
  lda #0
  sta cmd_line+LineInput::scr_cursor
  sta cmd_line+LineInput::data_cursor
  sta cmd_line+LineInput::first_visible

  lda #<INPUT_OFFSET
  clc
  adc SCR_PTR_LO
  sta cmd_line+LineInput::scr_ptr
  lda #>INPUT_OFFSET
  adc SCR_PTR_HI
  sta cmd_line+LineInput::scr_ptr+1

  lda #<cmd_line_data
  sta cmd_line+LineInput::data_ptr
  lda #>cmd_line_data
  sta cmd_line+LineInput::data_ptr+1
  lda #TERMINAL_WIDTH
  sta cmd_line+LineInput::num_visible
  lda #INPUT_MAX_LEN
  sta cmd_line+LineInput::data_size

  jsr int_set_cmd_line_context
  jsr li_shift_clear
  rts

; points the line input context at the command line. config leaves it
; on one of its own fields, so this runs on the way back.
int_set_cmd_line_context:
  lda CMDDATA0
  pha
  lda CMDDATA1
  pha
  lda #<cmd_line
  sta CMDDATA0
  lda #>cmd_line
  sta CMDDATA1
  jsr li_set_context
  pla
  sta CMDDATA1
  pla
  sta CMDDATA0
  rts

int_draw_ui:
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
  jsr int_draw_status_bar

  lda SCR_PTR_LO
  clc
  adc #<PROMPT_OFFSET
  sta ZPB0
  lda SCR_PTR_HI
  adc #>PROMPT_OFFSET
  sta ZPB1
  ldy #0
  lda #'>'
  jsr ut_atascii_to_icode
  sta (ZPB0),y
  rts

; draws a null terminated string into the bar in reverse text
;
; inputs:
;   CMDDATA0/1 - ptr to the string
;   CMDDATA2   - column in the bar
; modifies:
;   a,y
;   CMDDATA2/3/4
int_bar_draw_str:
  lda CMDDATA2
  clc
  adc #<BAR_ROW_OFFSET
  sta CMDDATA2
  lda #>BAR_ROW_OFFSET
  adc #0
  sta CMDDATA3
  lda #ICODE_SPACE_INVERTED
  sta CMDDATA4
  jsr scr_draw_str
  rts

; redraws the full status bar.
;
; modifies:
;   a,x,y
int_draw_status_bar:
  lda #<BAR_ROW_OFFSET
  clc
  adc SCR_PTR_LO
  sta ZPB0
  lda #>BAR_ROW_OFFSET
  adc SCR_PTR_HI
  sta ZPB1

  lda #ICODE_HORIZONTAL_BAR
  ldy #(SCREEN_WIDTH-1)
@col_loop:
  sta (ZPB0),y
  dey
  bpl @col_loop

  lda cfg_saved_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::APRS
  bne @status_label

  lda #<str_tx_label
  sta CMDDATA0
  lda #>str_tx_label
  sta CMDDATA1
  lda #BAR_TX_LABEL_COL
  sta CMDDATA2
  jsr int_bar_draw_str

  lda #<tx_addressee
  sta CMDDATA0
  lda #>tx_addressee
  sta CMDDATA1
  lda #BAR_TX_COL
  sta CMDDATA2
  jsr int_bar_draw_str
@status_label:
  lda #<str_status_label
  sta CMDDATA0
  lda #>str_status_label
  sta CMDDATA1
  lda #BAR_STATUS_LABEL_COL
  sta CMDDATA2
  jsr int_bar_draw_str
  jsr int_draw_status
  rts

; draws the port status into the status bar
;
; modifies:
;   a,x,y
int_draw_status:
  lda port_status
  sta last_status
  cmp #PORT_STATUS_OK
  beq @ok
  cmp #PORT_STATUS_OPENING
  beq @opening
  cmp #PORT_STATUS_NO_HANDLER
  beq @no_handler
  cmp #NONDEV
  beq @no_850
  cmp #TIMOUT
  beq @timeout
@code:
  jsr int_status_code_to_text
  lda #<status_code_text
  ldx #>status_code_text
  jmp @draw
@ok:
  lda #<str_status_ok
  ldx #>str_status_ok
  jmp @draw
@opening:
  lda #<str_status_opening
  ldx #>str_status_opening
  jmp @draw
@no_handler:
  lda #<str_status_no_handler
  ldx #>str_status_no_handler
  jmp @draw
@no_850:
  lda #<str_status_no_850
  ldx #>str_status_no_850
  jmp @draw
@timeout:
  lda #<str_status_timeout
  ldx #>str_status_timeout
@draw:
  sta CMDDATA0
  stx CMDDATA1
  lda #BAR_STATUS_COL
  sta CMDDATA2
  jsr int_bar_draw_str
  rts

; renders port_status into status_code_text
;
; modifies:
;   a,x,y
int_status_code_to_text:
  lda port_status
  jsr ut_bin_to_bcd

  ldy ut_result+1
  lda ut_hex_table_atascii,y
  sta status_code_text+0

  lda ut_result
  lsr
  lsr
  lsr
  lsr
  tay
  lda ut_hex_table_atascii,y
  sta status_code_text+1

  lda ut_result
  and #%00001111
  tay
  lda ut_hex_table_atascii,y
  sta status_code_text+2
  rts

; redraws the status bar if the status has changed.
;
; modifies:
;   a,x,y
int_update_status:
  lda port_status
  cmp last_status
  beq @done
  jsr int_draw_status_bar
@done:
  rts


int_repaint_char_mode:
  jsr to_repaint
  jsr int_draw_ui

  lda SCR_PTR_LO
  clc
  adc #<INPUT_OFFSET
  sta ZPB0
  lda SCR_PTR_HI
  adc #>INPUT_OFFSET
  sta ZPB1
  ldy #0
  lda (ZPB0),y
  ora #%10000000
  sta (ZPB0),y

  rts

int_reset_char_mode:
  jsr to_clear_and_home
  jsr int_draw_ui
  rts

int_repaint_line_mode:
  jsr to_repaint
  jsr li_hide_cursor
  jsr li_repaint
  jsr li_show_cursor
  jsr int_draw_ui
  rts

int_reset_line_mode:
  jsr to_clear_and_home
  jsr li_shift_clear
  jsr int_draw_ui
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
  jsr int_set_source_addr
  jsr int_set_digi_addrs
  jsr int_set_tx_broadcast
  jmp @done
@done:
  rts

int_set_source_addr:
  lda #<(cfg_saved_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::callsign)
  sta CMDDATA0
  lda #>(cfg_saved_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::callsign)
  sta CMDDATA1
  lda #<pk_source_addr
  sta CMDDATA2
  lda #>pk_source_addr
  sta CMDDATA3
  lda cfg_saved_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::ssid
  sta CMDDATA4
  lda #KISS_ADDR_RESERVED
  ldx cfg_saved_config+Cfg::aprs+CfgAprs::num_digi
  bne @store_flags
  ora #KISS_ADDR_LAST
@store_flags:
  sta CMDDATA5
  jsr pk_encode_addr
  jsr pk_set_tx_header
  rts

; encodes the configured digipeaters into pk_digi_addrs, marking
; the last one as the end of the address field.
int_set_digi_addrs:
  lda #0
  sta pk_digi_len
  sta digi_idx
  sta digi_offset
  lda cfg_saved_config+Cfg::aprs+CfgAprs::num_digi
  beq @done
@addr_loop:
  lda #<(cfg_saved_config+Cfg::aprs+CfgAprs::digi)
  clc
  adc digi_offset
  sta CMDDATA0
  lda #>(cfg_saved_config+Cfg::aprs+CfgAprs::digi)
  adc #0
  sta CMDDATA1

  lda #<pk_digi_addrs
  clc
  adc digi_offset
  sta CMDDATA2
  lda #>pk_digi_addrs
  adc #0
  sta CMDDATA3

  ldy digi_offset
  lda cfg_saved_config+Cfg::aprs+CfgAprs::digi+CfgAprsAddr::ssid,y
  sta CMDDATA4

  lda #KISS_ADDR_RESERVED
  ldx digi_idx
  inx
  cpx cfg_saved_config+Cfg::aprs+CfgAprs::num_digi
  bne @store_flags
  ora #KISS_ADDR_LAST
@store_flags:
  sta CMDDATA5
  jsr pk_encode_addr

  lda digi_offset
  clc
  adc #.sizeof(CfgAprsAddr)
  sta digi_offset
  inc digi_idx
  lda digi_idx
  cmp cfg_saved_config+Cfg::aprs+CfgAprs::num_digi
  bne @addr_loop
  lda digi_offset
  sta pk_digi_len
@done:
  rts

int_repaint:
  lda cfg_saved_config+Cfg::term+CfgTerm::mode
  cmp #TERM_MODE::CHAR
  beq @char_mode
  jsr int_repaint_line_mode
  jmp @done
@char_mode:
  jsr int_repaint_char_mode
@done:
  rts

int_reset:
  jsr int_reset_protocol
  lda cfg_saved_config+Cfg::term+CfgTerm::mode
  cmp #TERM_MODE::CHAR
  beq @char_mode
  jsr int_reset_line_mode
  jmp @done
@char_mode:
  jsr int_reset_char_mode
@done:
  rts

trm_activate:
  jsr int_set_cmd_line_context
  lda #CONFIG_FLAG_CANCELED
  bit cfg_config_flag
  bvc @just_repaint
  lda #PORT_STATUS_OPENING
  sta port_status
  jsr int_reset
  jsr int_repaint
  jsr int_cmd_boot850
  lda port_status
  cmp #PORT_STATUS_OPENING
  bne @port_error
  jsr int_cmd_open_rs232
  lda port_status
  cmp #PORT_STATUS_OPENING
  bne @port_error
  lda #PORT_STATUS_OK
  sta port_status
  jsr int_update_status
  jmp @done
@port_error:
  jsr int_update_status
  jmp @done
@just_repaint:
  jsr int_repaint
@done:
  rts

trm_tick:
  lda cfg_saved_config+Cfg::term+CfgTerm::mode
  cmp #TERM_MODE::CHAR
  beq @char_mode
  jsr int_handle_kbd_line_mode
  jmp @rs232
@char_mode:
  jsr int_handle_kbd_char_mode
@rs232:
  lda port_status
  cmp #PORT_STATUS_OK
  bne @status
  jsr int_cmd_get_rs232
@status:
  jsr int_update_status
  rts

int_cmd_line_mode_handle_char:
  lda g_kbdcode_atascii
  beq @done
  sta CMDDATA0
  jsr li_type_char
@done:
  rts

int_send_message:
  lda port_status
  cmp #PORT_STATUS_OK
  bne ism_port_closed

  lda #<cmd_line_data
  sta CMDDATA0
  lda #>cmd_line_data
  sta CMDDATA1
  lda #<tx_addressee
  sta CMDDATA2
  lda #>tx_addressee
  sta CMDDATA3
  lda cmd_line+LineInput::data_size
  sta CMDDATA4
  lda tx_send_flags
  ora #KISS_SEND_FLAG_TRIM_END
  sta CMDDATA5
  jsr pk_send_message
  bcc ism_success
  print_str_with_code str_error_rs232_putchr, g_copy_buffer40, pk_error
  jmp ism_done
ism_port_closed:
  print_str str_port_not_open
  jmp ism_done
ism_success:
  lda g_disp_buf_num_lines
  beq ism_done
  lda #<g_disp_buf
  sta CMDDATA0
  lda #>g_disp_buf
  sta CMDDATA1
  lda g_disp_buf_num_lines
  sta CMDDATA2
  lda #1
  sta CMDDATA3
  jsr to_append_lines
ism_done:
  rts

int_cmd_line_mode_return:
  lda cmd_line_data
  cmp #'/'
  bne @not_slash
  jsr int_run_command
  jmp @done
@not_slash:
  jsr int_send_message
@done:
  jsr li_shift_clear
  rts

int_run_command:
  lda #<str_cmd_tx
  sta CMDDATA0
  lda #>str_cmd_tx
  sta CMDDATA1
  jsr int_cmd_name_matches
  bcc @tx
  print_str str_unknown_command
  jmp @done
@tx:
  jsr int_cmd_tx
@done:
  rts

; matches what was typed against the given command name. the
; typed name has to end at a space, so /txfoo is not a match
; for /tx.
;
; inputs:
;   CMDDATA0/1 - ptr to the null terminated name, in uppercase
; outputs:
;   carry      - clear on a match, set otherwise
;   y          - index into cmd_line_data just past the name
int_cmd_name_matches:
  ldy #0
@name_loop:
  lda (CMDDATA0),y
  beq @name_end
  sta cmd_char
  lda cmd_line_data,y
  jsr ut_to_upper
  cmp cmd_char
  bne @no_match
  iny
  bne @name_loop
@name_end:
  lda cmd_line_data,y
  cmp #' '
  bne @no_match
  clc
  rts
@no_match:
  sec
  rts

; points the tx addressee at the callsign given.
; empty argument goes back to the broadcast addressee.
;
; inputs:
;   y - index into cmd_line_data just past the command name
int_cmd_tx:
@skip_loop:
  cpy cmd_line+LineInput::data_size
  beq @no_arg
  lda cmd_line_data,y
  cmp #' '
  bne @have_arg
  iny
  bne @skip_loop
@no_arg:
  jsr int_set_tx_broadcast
  jmp @show
@have_arg:
  sty cmd_arg_idx
  tya
  clc
  adc #<cmd_line_data
  sta CMDDATA0
  lda #>cmd_line_data
  adc #0
  sta CMDDATA1
  lda cmd_line+LineInput::data_size
  sec
  sbc cmd_arg_idx
  sta CMDDATA2
  jsr pk_parse_callsign
  bcs @invalid
  jsr int_build_tx_addressee
@show:
  jsr int_draw_status_bar
  rts
@invalid:
  print_str str_invalid_callsign
  rts

int_set_tx_broadcast:
  lda #KISS_SEND_FLAG_NO_MSG_ID
  sta tx_send_flags
  ldy #0
@copy_loop:
  lda pk_broadcast_addressee,y
  sta tx_addressee,y
  beq @done
  iny
  bne @copy_loop
@done:
  rts

int_build_tx_addressee:
  lda #0
  sta tx_send_flags
  ldx #0
  ldy #0
@call_loop:
  lda pk_callsign,x
  cmp #' '
  beq @call_done
  sta tx_addressee,y
  inx
  iny
  cpx #APRS_CALLSIGN_LEN
  bne @call_loop
@call_done:
  lda pk_ssid
  beq @done
  sta cmd_ssid
  lda #'-'
  sta tx_addressee,y
  iny
  lda cmd_ssid
  cmp #10
  bcc @ones
  sec
  sbc #10
  sta cmd_ssid
  lda #'1'
  sta tx_addressee,y
  iny
  lda cmd_ssid
@ones:
  clc
  adc #'0'
  sta tx_addressee,y
  iny
@done:
  lda #0
  sta tx_addressee,y
  rts

int_handle_kbd_char_mode:
  lda g_kbd_key_pressed
  beq @done
  lda g_kbdcode_atascii
  beq @done
  jsr int_cmd_put_rs232
;  todo: implement echo
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
  jsr li_move_cursor_left
  jmp @done
@right_arrow:
  jsr li_move_cursor_right
  jmp @done
@backspace:
  jsr li_backspace
  jmp @done
@shift_clear:
  jsr li_shift_clear
  jmp @done
@char_insert:
  jsr li_char_insert
  jmp @done
@char_delete:
  jsr li_char_delete
  jmp @done
@return:
  jsr int_cmd_line_mode_return
@done:
  rts
  
int_cmd_boot850:
  jsr boot850_check
  bcc @done
  jsr boot850_bootstrap
  bcs @error
  jsr boot850_check
  bcc @done
@error:
  lda #PORT_STATUS_NO_HANDLER
  sta port_status
@done:
  rts

int_cmd_open_rs232:
  ldx #RS232_CHANNEL
  jsr rs232_open
  bcs @error
  jmp @done
@error:
  sty command_error
  sty port_status
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
  jmp @done
@error_getchr:
  sty command_error
  sty port_status
  print_str_with_code str_error_rs232_getchr, g_copy_buffer40, command_error
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
@done:
  rts

top_banner:             .byte ' ','S'|$80,'E'|$80,'L'|$80,"config "
                        .byte $00
current_mode:           .res 1

str_error_rs232_status: .byte "Error on RS232 status",$00
str_error_rs232_getchr: .byte "Error on RS232 getchr",$00
str_error_rs232_putchr: .byte "Error on RS232 putchr",$00

str_cmd_tx:             .byte "/TX",$00
str_tx_label:           .byte "tx: ",$00
str_invalid_callsign:   .byte "invalid callsign",$00
str_unknown_command:    .byte "unknown command",$00
str_port_not_open:      .byte "port not open",$00

str_status_label:       .byte "status: ",$00
str_status_ok:          .byte "ok",$00
str_status_opening:     .byte "opening",$00
str_status_no_850:      .byte "no 850",$00
str_status_no_handler:  .byte "no r:",$00
str_status_timeout:     .byte "timeout",$00

status_code_text:       .res 3
                        .byte $00
last_status:            .res 1

tx_addressee:           .res KISS_ADDRESSEE_LEN+1
tx_send_flags:          .res 1
cmd_char:               .res 1
cmd_arg_idx:            .res 1
cmd_ssid:               .res 1
digi_idx:               .res 1
digi_offset:            .res 1

cmd_line:               .tag LineInput
cmd_line_data:          .res INPUT_MAX_LEN

command_error:          .byte 0

rs232_byte_read:        .byte 0
port_status:            .byte 0
