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

RX_BATCH_MAX           = 32

TERM_CHAR_PRINT        = 0
TERM_CHAR_EOL          = 1
TERM_CHAR_DROP         = 2

BAR_TX_LABEL_COL       = 1
BAR_TX_COL             = 4
BAR_RPT_LABEL_COL      = 13
BAR_RPT_COL            = 17
BAR_ACK_LABEL_COL      = 20
BAR_ACK_COL            = 24
BAR_STATUS_LABEL_COL   = 32
BAR_STATUS_COL         = 35
BAR_ROW_OFFSET         = SCREEN_WIDTH*22

ACK_ICON_PENDING       = '_'
ACK_ICON_ACKED         = '+'

PROMPT_OFFSET          = SCREEN_WIDTH*23
INPUT_OFFSET           = PROMPT_OFFSET+1
APRS_INPUT_MAX_LEN     = 67
TERM_INPUT_MAX_LEN     = 80
INPUT_BUF_LEN          = TERM_INPUT_MAX_LEN

trm_init:
  lda #PORT_STATUS_OK
  sta port_status
  lda #0
  sta last_eol
  jsr int_update_terminal_mode
  jsr int_update_terminal_eol

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

  jsr int_set_cmd_line_context
  jsr int_update_input_len
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

  lda pk_have_sent
  beq @ack

  lda #<str_rpt_label
  sta CMDDATA0
  lda #>str_rpt_label
  sta CMDDATA1
  lda #BAR_RPT_LABEL_COL
  sta CMDDATA2
  jsr int_bar_draw_str

  jsr int_repeats_to_text
  lda #<repeats_text
  sta CMDDATA0
  lda #>repeats_text
  sta CMDDATA1
  lda #BAR_RPT_COL
  sta CMDDATA2
  jsr int_bar_draw_str
@ack:
  lda pk_ack_state
  beq @status_label

  lda #<str_ack_label
  sta CMDDATA0
  lda #>str_ack_label
  sta CMDDATA1
  lda #BAR_ACK_LABEL_COL
  sta CMDDATA2
  jsr int_bar_draw_str

  jsr int_ack_state_to_text
  lda #<ack_state_text
  sta CMDDATA0
  lda #>ack_state_text
  sta CMDDATA1
  lda #BAR_ACK_COL
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

; draws the port status into the status bar.
;
; modifies:
;   a,x,y
int_draw_status:
  lda pk_ack_state
  sta last_ack_state
  lda pk_repeats
  sta last_repeats
  lda pk_have_sent
  sta last_have_sent
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
  sta ut_input+0
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

; renders the ack state into ack_state_text
;
; modifies:
;   a
int_ack_state_to_text:
  lda pk_ack_state
  cmp #KISS_ACK_STATE_ACKED
  beq @acked
  lda #ACK_ICON_PENDING
  jmp @store
@acked:
  lda #ACK_ICON_ACKED
@store:
  sta ack_state_text
  rts

; renders pk_repeats into repeats_text
;
; modifies:
;   a,x,y
int_repeats_to_text:
  lda pk_repeats
  sta ut_input+0
  jsr ut_bin_to_bcd

  lda ut_result
  lsr
  lsr
  lsr
  lsr
  tay
  lda ut_hex_table_atascii,y
  sta repeats_text+0

  lda ut_result
  and #%00001111
  tay
  lda ut_hex_table_atascii,y
  sta repeats_text+1
  rts

; outputs a null terminated string to the terminal output (basically a println)
;
; inputs:
;   CMDDATA0/1 - ptr to the string to print
; modifies:
;   A,X,Y
;   CMDDATA0-3
;   see to_append_lines
int_print_str:
  ldy #0
@loop:
  lda (CMDDATA0),y
  beq @loop_done
  sta g_copy_buffer40,y
  iny
  bne @loop
@loop_done:
  tya
  tax
  ut_pad_x g_copy_buffer40, TERMINAL_WIDTH
  lda #<g_copy_buffer40
  sta CMDDATA0
  lda #>g_copy_buffer40
  sta CMDDATA1
  lda #1
  sta CMDDATA2
  lda #0
  sta CMDDATA3
  jsr to_append_lines
  rts

; same as int_print_str except that it also writes ":<code>" to the end.
;
; inputs:
;   same as above, but A should have the code
; modifies:
;   same as above, but also ZPB0
int_print_str_with_code:
  pha
  ldy #0
@str_loop:
  lda (CMDDATA0),y
  beq @str_loop_done
  sta g_copy_buffer40,y
  iny
  bne @str_loop
@str_loop_done:
  lda #':'
  sta g_copy_buffer40,y
  iny

  tya
  tax
  pla
  ut_byte_to_bcd_str_x g_copy_buffer40
  ut_pad_x g_copy_buffer40, TERMINAL_WIDTH

  lda #<g_copy_buffer40
  sta CMDDATA0
  lda #>g_copy_buffer40
  sta CMDDATA1
  lda #1
  sta CMDDATA2
  lda #0
  sta CMDDATA3
  jsr to_append_lines
  rts

; prints the port error to the terminal. called when the status
; changes, so the user only sees it once per failure.
;
; modifies:
;   a,x,y
int_report_status:
  lda port_status
  cmp #PORT_STATUS_OK
  beq @no_error
  cmp #PORT_STATUS_OPENING
  beq @no_error
  cmp #PORT_STATUS_NO_HANDLER
  beq @no_handler
  cmp #NONDEV
  beq @no_850
  cmp #TIMOUT
  beq @timeout
  prep_print_str str_error_port
  lda port_status
  jsr int_print_str_with_code
  jmp @done
@no_error:
  jmp @done
@no_handler:
  prep_print_str str_no_r
  lda port_status
  jsr int_print_str_with_code
  jmp @done
@no_850:
  prep_print_str str_no_850
  lda port_status
  jsr int_print_str_with_code
  jmp @done
@timeout:
  prep_print_str str_timeout
  lda port_status
  jsr int_print_str_with_code
@done:
  rts

; redraws the status bar if anything it shows has changed.
;
; modifies:
;   a,x,y
int_update_status:
  lda port_status
  cmp last_status
  beq @check_ack
  jsr int_report_status
  jmp @redraw
@check_ack:
  lda pk_ack_state
  cmp last_ack_state
  bne @redraw
  lda pk_repeats
  cmp last_repeats
  bne @redraw
  lda pk_have_sent
  cmp last_have_sent
  beq @done
@redraw:
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

; outputs:
;   terminal_mode - a TERMINAL_MODE value
; modifies:
;   a
int_update_terminal_mode:
  lda cfg_saved_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::TERM
  beq @configured
  lda #TERMINAL_MODE::LINE
  jmp @done
@configured:
  lda cfg_saved_config+Cfg::term+CfgTerm::terminal_mode
@done:
  sta terminal_mode
  rts

; outputs:
;   eol_first  - the byte that ends a line
;   eol_second - the second byte, zero when the ending is one byte
; modifies:
;   a,x
int_update_terminal_eol:
  ldx cfg_saved_config+Cfg::term+CfgTerm::line_ending
  lda eol_table_first,x
  sta eol_first
  lda eol_table_second,x
  sta eol_second
  rts

; outputs:
;   cmd_line data_size - the protocol's line length limit
; modifies:
;   a,CMDDATA0
int_update_input_len:
  lda cfg_saved_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::TERM
  beq @term
  lda #APRS_INPUT_MAX_LEN
  jmp @done
@term:
  lda #TERM_INPUT_MAX_LEN
@done:
  sta cmd_line+LineInput::data_size
  sta CMDDATA0
  jsr li_set_data_size
  rts

; every terminator ends a line, no matter what the configured ending is.
; last_eol drops the tail of a two byte pair without also swallowing a
; deliberate blank line.
;
; inputs:
;   a - the received char
; outputs:
;   a - TERM_CHAR_PRINT, TERM_CHAR_EOL or TERM_CHAR_DROP
; modifies:
;   a,x
int_classify_char:
  cmp #TERM_EOL_CR
  beq @terminator
  cmp #TERM_EOL_LF
  beq @terminator
  cmp #TERM_EOL_ATASCII
  beq @terminator
  ldx #0
  stx last_eol
  lda #TERM_CHAR_PRINT
  jmp @done
@terminator:
  ldx last_eol
  beq @ends_line
  cmp last_eol
  beq @ends_line
  ldx #0
  stx last_eol
  lda #TERM_CHAR_DROP
  jmp @done
@ends_line:
  sta last_eol
  lda #TERM_CHAR_EOL
@done:
  rts

int_repaint:
  lda terminal_mode
  cmp #TERMINAL_MODE::CHAR
  beq @char_mode
  jsr int_repaint_line_mode
  jmp @done
@char_mode:
  jsr int_repaint_char_mode
@done:
  rts

int_reset:
  jsr int_reset_protocol
  lda terminal_mode
  cmp #TERMINAL_MODE::CHAR
  beq @char_mode
  jsr int_reset_line_mode
  jmp @done
@char_mode:
  jsr int_reset_char_mode
@done:
  rts


.macro send_tnc command, value, error_branch
  lda #command
  sta CMDDATA0
  lda value
  sta CMDDATA1
  jsr pk_send_param
  bcs error_branch
.endmacro
; sends params to the TNC
;
; outputs:
;   port_status - the rs232 status on a putchr error
;   c           - set if error, clear otherwise
;
; modifies:
;   a,x,y,CMDDATA0/1
int_send_tnc_params:
  send_tnc KISS_CMD::TX_DELAY, cfg_saved_config+Cfg::tnc+CfgTnc::tx_delay, istp_error
  send_tnc KISS_CMD::PERSISTENCE, cfg_saved_config+Cfg::tnc+CfgTnc::persistence, istp_error
  send_tnc KISS_CMD::SLOT_TIME, cfg_saved_config+Cfg::tnc+CfgTnc::slot_time, istp_error
  send_tnc KISS_CMD::TX_TAIL, cfg_saved_config+Cfg::tnc+CfgTnc::tx_tail, istp_error
  send_tnc KISS_CMD::DUPLEX, cfg_saved_config+Cfg::tnc+CfgTnc::duplex, istp_error
  rts
istp_error:
  lda pk_error
  sta command_error
  sta port_status
  rts

; closes the port on the way out to config. in concurrent mode the 850
; owns the sio bus until the close, and the file tab does disk i/o.
;
; modifies:
;   a,x,y
trm_deactivate:
  jsr rs232_close
  rts

trm_activate:
  jsr int_set_cmd_line_context
  jsr int_update_terminal_mode
  jsr int_update_terminal_eol
  jsr int_update_input_len
  lda #PORT_STATUS_OPENING
  sta port_status
  lda #CONFIG_FLAG_CANCELED
  bit cfg_config_flag
  bvc @just_repaint
  jsr int_reset
  jsr int_repaint
  jmp @open_port
@just_repaint:
  jsr int_repaint
@open_port:
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
@done:
  rts

trm_tick:
  lda terminal_mode
  cmp #TERMINAL_MODE::CHAR
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
  prep_print_str str_error_rs232_putchr
  lda pk_error
  jsr int_print_str_with_code
  jmp ism_done
ism_port_closed:
  prep_print_str str_port_not_open
  jsr int_print_str
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

; sends a raw line vs trying to parse slash commands or process the line
;
; modifies:
;   a,x,y,ZPB0-5,CMDDATA0-5
int_send_raw_line:
  lda port_status
  cmp #PORT_STATUS_OK
  bne @port_closed

  lda #<cmd_line_data
  sta CMDDATA0
  lda #>cmd_line_data
  sta CMDDATA1
  lda cmd_line+LineInput::data_size
  sta CMDDATA2
  jsr ut_str_trim_end_find

  lda ut_result
  sta CMDDATA2
  beq @line_ending
  jsr rs232_putchrs
  bcs @error_putchr
@line_ending:
  jsr int_cmd_put_line_ending
  jmp @done
@error_putchr:
  sty command_error
  sty port_status
  prep_print_str str_error_rs232_putchr
  tya
  jsr int_print_str_with_code
  jmp @done
@port_closed:
  prep_print_str str_port_not_open
  jsr int_print_str
@done:
  rts

int_cmd_line_mode_return:
  lda cfg_saved_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::APRS
  beq @aprs
@term:
  jsr int_send_raw_line
  jmp @done
@aprs:
  lda cmd_line_data
  cmp #'/'
  bne @aprs_message
  jsr int_parse_and_run_slash_command_aprs
  jmp @done
@aprs_message:
  jsr int_send_message
@done:
  jsr li_shift_clear
  rts

; parses the command line and runs the relevant command
; assumes first char was a slash
int_parse_and_run_slash_command_aprs:
  ldx #1
  ut_lda_x_to_upper cmd_line_data
  cmp #'T'
  beq ipsc_t
  bne ipsc_unknown
ipsc_t:
  inx
  ut_lda_x_to_upper cmd_line_data
  cmp #'X'
  beq ipsc_tx
  cmp #'N'
  beq ipsc_tn
  bne ipsc_unknown
ipsc_tx:
  inx
  ut_lda_x_to_upper cmd_line_data
  cmp #' '
  bne ipsc_unknown
  inx
  jsr int_cmd_tx
  jmp ipsc_done
ipsc_tn:
  inx
  ut_lda_x_to_upper cmd_line_data
  cmp #'C'
  beq ipsc_tnc
  bne ipsc_unknown
ipsc_tnc:
  inx
  lda cmd_line_data,x
  cmp #' '
  bne ipsc_unknown
  jsr int_send_tnc_params
  jsr int_update_status
  jmp ipsc_done
ipsc_unknown:
  prep_print_str str_unknown_command
  jsr int_print_str
ipsc_done:
  rts

; points the tx addressee at the callsign given.
; empty argument goes back to the broadcast addressee.
;
; inputs:
;   x - index into cmd_line_data just past the command name
int_cmd_tx:
@skip_loop:
  cpx cmd_line+LineInput::data_size
  beq @no_arg
  lda cmd_line_data,x
  cmp #' '
  bne @have_arg
  inx
  bne @skip_loop
@no_arg:
  jsr int_set_tx_broadcast
  jmp @show
@have_arg:
  stx cmd_arg_idx
  txa
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
  prep_print_str str_invalid_callsign
  jsr int_print_str
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
  lda g_kbdcode_raw
  cmp #$0c
  beq @return
  cmp #$76 ; shift+clear ($b4 on atari 800 emulator)
  beq @clear
  cmp #$b6 ; ctrl+clear
  beq @clear
  lda g_kbdcode_atascii
  beq @done
  sta put_char
  jsr int_cmd_put_rs232
  jmp @done
@return:
  jsr int_cmd_put_line_ending
  jmp @done
;  todo: implement echo
;  lda g_kbdcode_atascii
;  sta CMDDATA0
;  jsr to_append_char
@clear:
  jsr to_clear_and_home
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
  beq @clear
  cmp #$b6 ; ctrl+clear
  beq @clear
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
@clear:
  jsr to_clear_and_home
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
  prep_print_str str_open_stage
  lda rs232_open_stage
  jsr int_print_str_with_code
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
  jsr int_classify_char
  cmp #TERM_CHAR_DROP
  beq @done
  cmp #TERM_CHAR_EOL
  beq @term_eol
  lda rs232_byte_read
  sta CMDDATA0
  jsr to_append_char
  jmp @done
@term_eol:
  jsr to_end_line
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
  bcc @have_status
  jmp @error_status
@have_status:
  lda rs232_input_buffer_size+1
  bne @full_batch
  lda rs232_input_buffer_size
  bne @partial_batch
  jmp @done
@partial_batch:
  cmp #RX_BATCH_MAX
  bcc @batch_ready
@full_batch:
  lda #RX_BATCH_MAX
@batch_ready:
  sta rx_remaining
@read_loop:
  jsr rs232_getchr
  bcc @read_ok
  jmp @error_getchr
@read_ok:
  sta rs232_byte_read
  jsr int_handle_byte_read
  dec rx_remaining
  bne @read_loop
  jmp @done
@error_status:
  sty command_error
  sty port_status
  prep_print_str str_error_rs232_status
  tya
  jsr int_print_str_with_code
  jmp @done
@error_getchr:
  sty command_error
  sty port_status
  prep_print_str str_error_rs232_getchr
  tya
  jsr int_print_str_with_code
@done:
  rts

; inputs:
;   put_char - the char to write
; modifies:
;   a,x,y
int_cmd_put_rs232:
  lda port_status
  cmp #PORT_STATUS_OK
  bne @done
  lda put_char
  jsr rs232_putchr
  bcs @error_putchr
  jmp @done
@error_putchr:
  sty command_error
  sty port_status
  prep_print_str str_error_rs232_putchr
  tya
  jsr int_print_str_with_code
@done:
  rts

; modifies:
;   a,x,y
int_cmd_put_line_ending:
  lda eol_first
  sta put_char
  jsr int_cmd_put_rs232

  lda eol_second
  beq @done
  sta put_char
  jsr int_cmd_put_rs232
@done:
  rts

top_banner:             .byte ' ','S'|$80,'E'|$80,'L'|$80,"config "
                        .byte $00
terminal_mode:          .res 1

str_error_rs232_status: .byte "Error on RS232 status",$00
str_error_rs232_getchr: .byte "Error on RS232 getchr",$00
str_error_rs232_putchr: .byte "Error on RS232 putchr",$00

str_cmd_tx:             .byte "/TX",$00
str_tx_label:           .byte "tx:",$00
str_ack_label:          .byte "ack:",$00
str_rpt_label:          .byte "rpt:",$00
str_invalid_callsign:   .byte "invalid callsign",$00
str_unknown_command:    .byte "unknown command",$00
str_port_not_open:      .byte "port not open",$00
str_no_850:             .byte "850 not found",$00
str_no_r:               .byte "R: handler not found",$00
str_timeout:            .byte "Timeout",$00
str_error_port:         .byte "Port error",$00
str_open_stage:         .byte "Open failed at stage",$00

str_status_label:       .byte "st:",$00
str_status_ok:          .byte "OK",$00
str_status_opening:     .byte "...",$00
str_status_no_850:      .byte "!850",$00
str_status_no_handler:  .byte "!-R:",$00
str_status_timeout:     .byte "! TO",$00

status_code_text:       .res 3
                        .byte $00
ack_state_text:         .res 1
                        .byte $00
repeats_text:           .res 2
                        .byte $00
last_status:            .res 1
last_ack_state:         .res 1
last_repeats:           .res 1
last_have_sent:         .res 1

eol_table_first:        .byte TERM_EOL_CR, TERM_EOL_LF, TERM_EOL_CR, TERM_EOL_ATASCII
eol_table_second:       .byte 0,           0,           TERM_EOL_LF, 0

eol_first:              .res 1
eol_second:             .res 1
last_eol:               .res 1

tx_addressee:           .res KISS_ADDRESSEE_LEN+1
tx_send_flags:          .res 1
put_char:               .res 1
cmd_char:               .res 1
cmd_arg_idx:            .res 1
cmd_ssid:               .res 1
digi_idx:               .res 1
digi_offset:            .res 1

cmd_line:               .tag LineInput
cmd_line_data:          .res INPUT_BUF_LEN

command_error:          .byte 0
rx_remaining:           .byte 0

rs232_byte_read:        .byte 0
port_status:            .byte 0
