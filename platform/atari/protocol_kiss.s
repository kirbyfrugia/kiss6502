.setcpu "6502"
.include "protocol_kiss.inc"
.include "atari.inc"
.include "crc.inc"
.include "globals.inc"
.include "rs232.inc"
.include "utils.inc"

.segment "ZEROPAGE"
buf_counter:  .res 1
addr_counter: .res 1
fmt_hdr_lo:   .res 1
fmt_hdr_hi:   .res 1
fmt_data_lo:  .res 1
fmt_data_hi:  .res 1

; ':' + addressee + ':' + text + '{' + 4 hex digits
PK_TX_BUF_LEN = 1 + KISS_ADDRESSEE_LEN + 1 + APRS_MAX_MSG_LEN + 1 + 4

DEDUP_N = 16            ; must be a power of 2, the write index wraps with an AND
DEDUP_TTL_SECS = 30
DEDUP_TICK_FRAMES = 60  ; number of VBIs before running the dedup ttl expire function

.segment "CODE"

pk_reset:
  lda #KISS_STATE_NEW
  sta pk_state
  lda #0
  sta dedup_next
  ldx #DEDUP_N-1
@ttl_clear_loop:
  sta dedup_ttl,x
  dex
  bpl @ttl_clear_loop
  lda #DEDUP_TICK_FRAMES
  sta dedup_tick
  lda #1
  sta msg_id_lo
  lda #0
  sta msg_id_hi
  jsr pk_next_frame
  rts

; ages out the dedup entries, called from the vbi.
; we do this once per every DEDUP_TICK_FRAMES frames.
;
; modifies:
;   a,x
pk_vbi_tick:
  dec dedup_tick
  bne @done
  lda #DEDUP_TICK_FRAMES
  sta dedup_tick
  ldx #DEDUP_N-1
@ttl_loop:
  lda dedup_ttl,x
  beq @next
  dec dedup_ttl,x
@next:
  dex
  bpl @ttl_loop
@done:
  rts

; encodes a callsign and ssid into the 7 byte ax25 address
; format. each callsign byte is shifted left one bit, then a
; last byte holds the ssid in bits 4-1 with the given flags
; ored in.
;
; inputs:
;   CMDDATA0/1 - ptr to the callsign, space padded to 6
;   CMDDATA2/3 - ptr to the 7 byte output buffer
;   CMDDATA4   - ssid, 0 to 15
;   CMDDATA5   - flags to or into the ssid byte
; modifies:
;   a,y
pk_encode_addr:
  callsign_ptr_lo = CMDDATA0
  out_ptr_lo = CMDDATA2
  ssid = CMDDATA4
  addr_flags = CMDDATA5

  ldy #0
@callsign_loop:
  lda (callsign_ptr_lo),y
  asl
  sta (out_ptr_lo),y
  iny
  cpy #.sizeof(KissFrameAddr::callsign)
  bne @callsign_loop

  lda ssid
  asl
  ora addr_flags
  sta (out_ptr_lo),y
  rts

; unshifts a wire address back into the KissFrameAddr layout
; the display path renders from.
;
; inputs:
;   CMDDATA0/1 - ptr to the 7 byte encoded address
;   CMDDATA2/3 - ptr to the KissFrameAddr to fill
; modifies:
;   a,y
int_decode_addr:
  ldy #0
@callsign_loop:
  lda (CMDDATA0),y
  lsr
  sta (CMDDATA2),y
  iny
  cpy #.sizeof(KissFrameAddr::callsign)
  bne @callsign_loop

  lda (CMDDATA0),y
  lsr
  and #%00001111
  sta (CMDDATA2),y
  rts

; fills the header the display path renders our own frames from.
; should only change when config does.
;
; modifies:
;   a,y
;   CMDDATA0/1/2/3
pk_set_tx_header:
  lda #<pk_dest_addr
  sta CMDDATA0
  lda #>pk_dest_addr
  sta CMDDATA1
  lda #<(pk_tx_header+KissFrameHeader::dest)
  sta CMDDATA2
  lda #>(pk_tx_header+KissFrameHeader::dest)
  sta CMDDATA3
  jsr int_decode_addr

  lda #<pk_source_addr
  sta CMDDATA0
  lda #>pk_source_addr
  sta CMDDATA1
  lda #<(pk_tx_header+KissFrameHeader::source)
  sta CMDDATA2
  lda #>(pk_tx_header+KissFrameHeader::source)
  sta CMDDATA3
  jsr int_decode_addr
  rts

; validates and converts a two character ssid field into a value.
; the field can be left aligned, right aligned, or all spaces
; for a zero ssid.
;
; inputs:
;   CMDDATA0/1 - ptr to the two character field
; outputs:
;   a     - the ssid, 0 to 15
;   carry - set if invalid ssid, clear otherwise
; modifies:
;   a,y
pk_text_to_ssid:
  left_digit = 0
  right_digit = 1

  lda #0
  sta ssid_tmp

  ldy #right_digit
  lda (CMDDATA0),y
  cmp #' '
  bne @right_digit_not_blank
@right_digit_blank:
  ldy #left_digit
  lda (CMDDATA0),y
  cmp #' '
  bne @single_digit
@all_blank:
  lda ssid_tmp
  beq @parsed
@right_digit_not_blank:
  ldy #left_digit
  lda (CMDDATA0),y
  cmp #'2'
  bcs @error
  cmp #' '
  beq @right_digit_not_blank_ignore_left
  cmp #'0'
  beq @right_digit_not_blank_ignore_left
  cmp #'1'
  bne @error
@right_digit_not_blank_left_digit_one:
  lda #10
  sta ssid_tmp
@right_digit_not_blank_ignore_left:
  ldy #right_digit
  lda (CMDDATA0),y
@single_digit:
  jsr ut_ascii_char_to_digit
  bcs @error
  clc
  adc ssid_tmp
@parsed:
  cmp #16
  bcs @error
  clc
  rts
@error:
  sec
  rts

; parses a callsign with an optional ssid, e.g. NOCALL-1, stopping
; at a space or when the characters run out. callsign will
; be converted to upper case.
;
; inputs:
;   CMDDATA0/1 - ptr to the text
;   CMDDATA2   - number of characters to scan
; outputs:
;   pk_callsign - uppercased and space padded to 6
;   pk_ssid     - the ssid, 0 to 15
;   carry       - clear if valid, set otherwise
; modifies:
;   CMDDATA0/1
;   a,x,y
pk_parse_callsign:
  text_ptr_lo = CMDDATA0
  text_len = CMDDATA2

  ldx #APRS_CALLSIGN_LEN-1
  lda #' '
@blank_loop:
  sta pk_callsign,x
  dex
  bpl @blank_loop

  lda #0
  sta pk_ssid

  ldx #0
  ldy #0
@call_loop:
  cpy text_len
  beq @call_end
  lda (text_ptr_lo),y
  cmp #' '
  beq @call_end
  cmp #'-'
  beq @dash
  jsr ut_to_upper
  jsr ut_is_alphanumeric
  bcs @error
  cpx #APRS_CALLSIGN_LEN
  bcs @error
  sta pk_callsign,x
  inx
  iny
  bne @call_loop
@call_end:
  cpx #0
  beq @error
  clc
  rts
@dash:
  cpx #0
  beq @error
  iny
  lda #' '
  sta ssid_text+0
  sta ssid_text+1
  ldx #0
@ssid_loop:
  cpy text_len
  beq @ssid_end
  lda (text_ptr_lo),y
  cmp #' '
  beq @ssid_end
  cpx #APRS_SSID_LEN
  bcs @error
  sta ssid_text,x
  inx
  iny
  bne @ssid_loop
@ssid_end:
  cpx #0
  beq @error
  lda #<ssid_text
  sta CMDDATA0
  lda #>ssid_text
  sta CMDDATA1
  jsr pk_text_to_ssid
  bcs @error
  sta pk_ssid
  clc
  rts
@error:
  sec
  rts

; writes N chars from the given buffer over rs232 as
; a kiss message type with the option of trimming the end
; off the data. i.e. sending until last non-space char.
;
; inputs:
;   CMDDATA0/1 - ptr to the data
;   CMDDATA2/3 - ptr to the addressee, null terminated or 9 chars.
;                shorter ones are padded out with spaces.
;   CMDDATA4   - size of buf
;   CMDDATA5   - KISS_SEND_FLAG_TRIM_END to trim, KISS_SEND_FLAG_BROADCAST
;                to leave off the message id
pk_send_message:
  data_ptr_lo = CMDDATA0
  addressee_ptr_lo = CMDDATA2
  buf_size = CMDDATA4
  send_flags = CMDDATA5

  lda #0
  sta g_disp_buf_num_lines

  lda send_flags
  bmi @trim
  lda buf_size
  beq @data_empty; was empty string
  bne @ready
@data_empty:
  jmp @done
@trim:
  lda CMDDATA2
  pha
  lda buf_size
  sta CMDDATA2 
  jsr ut_str_trim_end_find
  pla
  sta CMDDATA2
  lda ut_result
  sta buf_size
  beq @all_spaces; was an empty string
  bne @ready
@all_spaces:
  jmp @done
@to_error:
  jmp @error
@ready:
  jsr int_build_tx_buf

  lda #KISS_FEND
  jsr rs232_putchr
  bcs @to_error

  lda #KISS_CMD::DATA_FRAME
  jsr int_putchr_escaped
  bcs @to_error

  ; TODO: don't hard-code the header
  ldy #0
@dest_loop:
  sty tempy
  lda pk_dest_addr,y
  jsr int_putchr_escaped
  bcs @to_error
  ldy tempy
  iny
  cpy #7
  bne @dest_loop 

  ldy #0
@src_loop:
  sty tempy
  lda pk_source_addr,y
  jsr int_putchr_escaped
  bcs @to_error
  ldy tempy
  iny
  cpy #7
  bne @src_loop

  lda pk_digi_len
  beq @digi_done
  ldy #0
@digi_loop:
  sty tempy
  lda pk_digi_addrs,y
  jsr int_putchr_escaped
  bcs @to_error
  ldy tempy
  iny
  cpy pk_digi_len
  bne @digi_loop
@digi_done:

  lda #$03 ; ui frame
  jsr int_putchr_escaped
  bcs @error

  lda #$f0 ; PID, no layer 3
  jsr int_putchr_escaped
  bcs @error

  ldy #0
@info_loop:
  sty tempy
  lda pk_tx_buf,y
  jsr int_putchr_escaped
  bcs @error
  ldy tempy
  iny
  cpy pk_tx_buf_num_chars
  bne @info_loop

  lda #KISS_FEND
  jsr rs232_putchr
  bcs @error

  lda #<pk_tx_header
  sta fmt_hdr_lo
  lda #>pk_tx_header
  sta fmt_hdr_hi
  lda #<pk_tx_buf
  sta fmt_data_lo
  lda #>pk_tx_buf
  sta fmt_data_hi
  lda pk_tx_buf_num_chars
  sta fmt_len

  jsr int_format_message
  jsr int_finalize_disp

  lda send_flags
  and #KISS_SEND_FLAG_BROADCAST
  bne @done
  inc msg_id_lo
  bne @done
  inc msg_id_hi
@done:
  clc
  rts
@error:
  ldy rs232_last_status
  sty pk_error
  sec
  rts

; writes the byte over rs232, replacing it with the two byte
; escape sequence if it collides with a kiss framing byte.
;
; inputs:
;   a - the byte to write
; outputs:
;   carry - set on a putchr error
; modifies:
;   a,x
int_putchr_escaped:
  cmp #KISS_FEND
  beq @fend
  cmp #KISS_FESC
  beq @fesc
  jsr rs232_putchr
  rts
@fend:
  lda #KISS_TFEND
  sta tempchr
  jmp @escape
@fesc:
  lda #KISS_TFESC
  sta tempchr
@escape:
  lda #KISS_FESC
  jsr rs232_putchr
  bcs @done
  lda tempchr
  jsr rs232_putchr
@done:
  rts

; writes the byte as two hex chars into the tx buffer
;
; inputs:
;   a - the byte to write
;   x - offset in the tx buffer to store at
; outputs:
;   x - advanced by two
; modifies:
;   a,x,y
int_hex_to_tx_buf:
  pha
  lsr
  lsr
  lsr
  lsr
  tay
  lda ut_hex_table_atascii,y
  sta pk_tx_buf,x
  inx
  pla
  and #%00001111
  tay
  lda ut_hex_table_atascii,y
  sta pk_tx_buf,x
  inx
  rts

; builds the info field for the message we are sending
;
; inputs:
;   CMDDATA0/1 - ptr to the data
;   CMDDATA2/3 - ptr to the addressee
;   CMDDATA4   - number of chars in the data
;   CMDDATA5   - send flags
; outputs:
;   pk_tx_buf_num_chars - number of chars written
; modifies:
;   a,x,y
int_build_tx_buf:
  ldx #0
  lda #':'
  sta pk_tx_buf,x
  inx

  ldy #0
@addressee_loop:
  lda (addressee_ptr_lo),y
  beq @addressee_pad_loop
  sta pk_tx_buf,x
  inx
  iny
  cpy #KISS_ADDRESSEE_LEN
  bne @addressee_loop
  beq @addressee_done
@addressee_pad_loop:
  lda #' '
  sta pk_tx_buf,x
  inx
  iny
  cpy #KISS_ADDRESSEE_LEN
  bne @addressee_pad_loop
@addressee_done:

  lda #':'
  sta pk_tx_buf,x
  inx

  ldy #0
@data_loop:
  lda (data_ptr_lo),y
  sta pk_tx_buf,x
  inx
  iny
  cpy buf_size
  bne @data_loop

  lda send_flags
  and #KISS_SEND_FLAG_BROADCAST
  bne @id_done
  lda #'{'
  sta pk_tx_buf,x
  inx
  lda msg_id_hi
  jsr int_hex_to_tx_buf
  lda msg_id_lo
  jsr int_hex_to_tx_buf
@id_done:
  stx pk_tx_buf_num_chars
  rts

pk_next_frame:
  lda #0
  sta buf_counter
  sta addr_counter
  sta btwn_counter
  sta g_disp_buf_num_lines
  sta pk_frame_header+KissFrameHeader::num_digi

  lda pk_state
  and #%10000000  ; leave FEND alone, clear rest
  sta pk_state
  rts

; inputs:
;   CMDDATA0 - byte received
pk_new_byte:
  lda #KISS_STATE_NEW
  bit pk_state
  bpl @parse
  ; if here, still waiting on very first FEND
  lda CMDDATA0
  cmp #KISS_FEND
  bne @done
  lda pk_state
  eor #KISS_STATE_NEW
  sta pk_state
  jmp @done
@parse:
  lda pk_state
  and #KISS_STATE_FESC
  bne @in_fesc
  ; if here, not in escape mode
  lda CMDDATA0
  cmp #KISS_FESC
  beq @fesc
  cmp #KISS_FEND
  beq @fend
  bne @data
@fesc:
  ; enter escape mode
  lda pk_state
  ora #KISS_STATE_FESC
  sta pk_state
  jmp @done
@fend:
  jsr int_fend
  jmp @done
@in_fesc:
  ; exit escape mode
  lda pk_state
  eor #KISS_STATE_FESC
  sta pk_state
  lda CMDDATA0
  cmp #KISS_TFESC
  beq @in_fesc_tfesc
  cmp #KISS_TFEND
  beq @in_fesc_tfend
  bne @done ; invalid, drop the byte
@in_fesc_tfesc:
  lda #KISS_FESC
  bne @data
@in_fesc_tfend:
  lda #KISS_FEND
@data:
  sta CMDDATA0
  jsr int_process_byte
@done:
  rts

; Note: assumes we never have a frame with data > 256 bytes
int_process_byte:
  lda pk_state
  and #KISS_STATE_INFO
  beq @chk_in_addr ; dumb cause branch too far
  jmp @in_info
@chk_in_addr:
  lda pk_state
  and #KISS_STATE_ADDR
  beq @chk_in_btwn ; dumb cause branch too far
  jmp @in_addr
@chk_in_btwn:
  lda pk_state
  and #KISS_STATE_BTWN
  beq @in_first_byte
  jmp @in_btwn
@in_first_byte:
  ; just the type field, first byte
  lda CMDDATA0
  sta pk_frame_header+KissFrameHeader::cmd_type
  lda pk_state
  ora #KISS_STATE_ADDR
  sta pk_state
  ldy #1
  sty buf_counter
  jmp @done
@in_addr:
  ldy buf_counter
  lda addr_counter
  cmp #6
  beq @ssid ; last byte has ssid and extension bit
  ; address bytes are all shifted left by one bit
  lda CMDDATA0
  lsr
  sta pk_frame_header,y 
  inc addr_counter
  jmp @in_addr_done
@ssid:
  cpy #KissFrameHeader::digipeater
  bcc @not_digi ; not yet to digipeater section
  inc pk_frame_header+KissFrameHeader::num_digi
@not_digi:
  lda CMDDATA0
  lsr            ; address extension bit -> carry
  and #%00001111 ; ssid
  sta pk_frame_header,y
  bcs @last_addr
  lda #0
  sta addr_counter
@in_addr_done:
  iny
  sty buf_counter
  jmp @done
@last_addr:
  iny
  sty buf_counter
  lda pk_state
  eor #KISS_STATE_ADDR
  ora #KISS_STATE_BTWN
  sta pk_state
  jmp @done
@in_btwn:
  lda CMDDATA0
  ldy btwn_counter
  cpy #1
  beq @last_btwn
  sta pk_frame_header+KissFrameHeader::control
  inc btwn_counter
  jmp @done
@last_btwn:
  sta pk_frame_header+KissFrameHeader::protocol_id
  lda pk_state
  eor #KISS_STATE_BTWN
  ora #KISS_STATE_INFO
  sta pk_state
  ldy #0
  sty buf_counter
  jmp @done
@in_info:
  ldy buf_counter
  lda CMDDATA0
  sta g_rx_buf,y
  iny ; assumes <256 bytes
  sty buf_counter
@done:
  rts

pk_process_frame:
  lda #<g_disp_buf
  sta g_temp_data_ptr_lo
  lda #>g_disp_buf
  sta g_temp_data_ptr_hi

  inc buf_counter
  lda g_rx_buf+0
  cmp #':'
  beq pkpf_message
;  cmp #'>'
;  beq pkpf_status
  bne pkpf_done
;pkpf_status:
;  jsr int_process_status
;  jmp pkpf_done
pkpf_message:
  jsr int_process_message
pkpf_done:
  rts

int_fend:
  lda pk_state
  and #KISS_STATE_INFO
  beq @reset ; frame ended before the info field
  lda buf_counter
  beq @reset ; no data, was an empty frame
  sta g_rx_buf_num_chars

  ; indicate a frame is ready for handling
  lda pk_state
  ora #KISS_FRAME_READY
  sta pk_state
  jmp @done
@reset:
  jsr pk_next_frame
@done:
  rts

; renders a message into the display buffer and computes its crc.
;
; inputs:
;   fmt_hdr_lo/hi  - ptr to the frame header
;   fmt_data_lo/hi - ptr to the info field
;   fmt_len        - number of chars in the info field
; outputs:
;   y_index_var    - one past the last char written
; modifies:
;   a,x,y
int_format_message:
  jsr crc_reset

  lda #<g_disp_buf
  sta g_temp_data_ptr_lo
  lda #>g_disp_buf
  sta g_temp_data_ptr_hi

  ldx #0
  lda #KissFrameHeader::source
  sta x_index_var
  jsr int_addr_to_buf

  lda #'>'
  sta g_disp_buf,x
  inx

  lda #KISS_TYPE_MSG_ADDRESSEE_IDX
  sta x_index_var
  lda #KISS_TYPE_MSG_END_COLON_IDX
  sta x_index_var_end
  lda #' '
  sta terminator
  jsr int_read_until_terminator_with_crc

  lda #KISS_TYPE_MSG_END_COLON_IDX
  sta x_index_var
  lda fmt_len
  sta x_index_var_end
  lda #'{'
  sta terminator
  jsr int_read_until_terminator_with_crc
  bcc @finalize ; no message id
  lda #'#'
  sta g_disp_buf,x
  inx
  iny
  sty x_index_var
  stx tempx
  lda terminator
  jsr crc_upd
  ldx tempx
  jsr int_read_until_end_with_crc
@finalize:
  stx y_index_var
  jsr int_add_header_bytes_to_crc
  rts

int_process_message:
  lda g_rx_buf_num_chars
  cmp #KISS_TYPE_MSG_END_COLON_IDX
  bcc @done ; not a valid message

  jsr int_is_our_source
  bcs @done ; we showed it when we sent it

  lda #<pk_frame_header
  sta fmt_hdr_lo
  lda #>pk_frame_header
  sta fmt_hdr_hi
  lda #<g_rx_buf
  sta fmt_data_lo
  lda #>g_rx_buf
  sta fmt_data_hi
  lda g_rx_buf_num_chars
  sta fmt_len

  jsr int_format_message

  ; todo: actually handle acks
  jsr int_is_ack
  bcs @done
  jsr int_check_duplicate
  bcs @done
  jsr int_finalize_disp
@done:
  rts

;int_process_status:
;  lda #<g_disp_buf
;  sta g_temp_data_ptr_lo
;  lda #>g_disp_buf
;  sta g_temp_data_ptr_hi
;
;  ldy #0
;  lda #'['
;  sta g_disp_buf,y
;
;  iny
;  ldx #KissFrameHeader::source
;  stx x_index_var
;  jsr int_addr_to_buf
;
;  lda #']'
;  sta g_disp_buf,y
;
;  iny
;
;  ; empty statuses are allowed, but we don't
;  ; want to try parsing the string
;  lda g_rx_buf_num_chars
;  cmp #2 ; first char is '>' no matter what
;  bcs @not_empty
;  jmp @finalize
;@not_empty:
;  lda #' '
;  sta g_disp_buf,y
;
;  lda g_rx_buf_num_chars
;  cmp #KISS_TYPE_STATUS_TIMESTAMP_ZULU_IDX
;  bcc @nozulu
;  ldx #KISS_TYPE_STATUS_TIMESTAMP_ZULU_IDX
;  lda g_rx_buf,x
;  cmp #'z'
;  beq @zulu
;  cmp #'Z'
;  beq @zulu
;  ldx #1
;  bne @nozulu
;@zulu:
;  ; might be a timestamp, confirm
;  ldx #1
;  stx x_index_var
;  ldx #KISS_TYPE_STATUS_TIMESTAMP_ZULU_IDX
;  stx x_index_var_end
;  jsr int_all_digits
;  bcc @nozulu
;
;  lda #' '
;  sta g_disp_buf,y
;
;  ; it's a timestamp. Convert from DDHHmm to HH:mm
;  ldx #3
;  iny
;  lda g_rx_buf,x
;  sta g_disp_buf,y
;  iny
;  inx
;  lda g_rx_buf,x
;  sta g_disp_buf,y
;  iny
;  lda #':'
;  sta g_disp_buf,y
;  iny
;  inx
;  lda g_rx_buf,x
;  sta g_disp_buf,y
;  iny
;  inx
;  lda g_rx_buf,x
;  sta g_disp_buf,y
;  iny
;  lda #' '
;  sta g_disp_buf,y
;  inx
;  inx
;@nozulu:
;  iny
;  stx x_index_var
;  lda g_rx_buf_num_chars
;  sta x_index_var_end
;  jsr int_read_until_end
;@finalize:
;  sty y_index_var
;  jsr int_finalize_disp
;@done:
;  rts

; finalizes the output once all the real data
; has been added to the display buffer.
;
; Does the following:
;   - sets line count
;   - fills blank spaces to the end of the last line
;
; inputs
;   y_index_var - one past last character already printed
; modifies:
;   a,y
int_finalize_disp:
  lda y_index_var
  beq @done
@mod_loop:
  inc g_disp_buf_num_lines
  lda y_index_var
  sec
  sbc #TERMINAL_WIDTH
  beq @mod_loop_done ; exactly at zero, on last line
  bcc @mod_loop_done ; needed to borrow, on last line
  ; not on last line yet
  sta y_index_var ; remaining
  lda g_temp_data_ptr_lo
  clc
  adc #TERMINAL_WIDTH
  sta g_temp_data_ptr_lo
  bcc @nowrap
  inc g_temp_data_ptr_hi
@nowrap:
  jmp @mod_loop
@mod_loop_done:
  lda #' '
  ldy y_index_var
@fill_loop:
  cpy #TERMINAL_WIDTH
  beq @done
  sta (g_temp_data_ptr_lo),y
  iny
  jmp @fill_loop
@done:
  rts

; reads the info field from x_index_var to x_index_var_end
; until the given terminator char appears, updating the crc
; with each char written. the terminator itself is not
; written or added to the crc.
;
; assumes x_index_var_end - x_index_var > 1
;
; inputs:
;   terminator      - terminator char
;   fmt_data_lo/hi  - ptr to the info field
;   x_index_var     - start index to check
;   x_index_var_end - end index to check (one past)
;   x               - start index to write to
; outputs:
;   c - set if the terminator was found, clear if we hit the end
;   y - index of the terminator, or x_index_var_end
;   x - index of last written char + 1
; modifies:
;   a, ZPB0
int_read_until_terminator_with_crc:
  ldy x_index_var
@loop:
  lda (fmt_data_lo),y
  cmp terminator
  beq @found
  sta g_disp_buf,x
  stx ZPB0
  jsr crc_upd
  ldx ZPB0
  inx
  iny
  cpy x_index_var_end
  bne @loop
  clc
  rts
@found:
  sec
  rts

; reads the info field from x_index_var to x_index_var_end,
; updating the crc with each char written.
;
; assumes x_index_var_end - x_index_var > 1
;
; inputs:
;   fmt_data_lo/hi  - ptr to the info field
;   x_index_var     - start index to check
;   x_index_var_end - end index to check (one past)
;   x               - start index to write to
; outputs:
;   y - index of last read char + 1
;   x - index of last written char + 1
; modifies:
;   a, ZPB0
int_read_until_end_with_crc:
  ldy x_index_var
@loop:
  lda (fmt_data_lo),y
  sta g_disp_buf,x
  stx ZPB0
  jsr crc_upd
  ldx ZPB0
  inx
  iny
  cpy x_index_var_end
  bne @loop
@done:
  rts

; adds the dest and source addresses from the frame header
; to the crc. digipeaters are not included because we use the
; crc to detect duplicates, and we might have the same message
; received from multiple digipeaters. control and pid never change
; so aren't included, either.
;
; modifies:
;   a,x,y
int_add_header_bytes_to_crc:
  ldy #KissFrameHeader::dest
@dest_loop:
  lda (fmt_hdr_lo),y
  jsr crc_upd
  iny
  cpy #(KissFrameHeader::dest+.sizeof(KissFrameAddr))
  bne @dest_loop

  ldy #KissFrameHeader::source
@source_loop:
  lda (fmt_hdr_lo),y
  jsr crc_upd
  iny
  cpy #(KissFrameHeader::source+.sizeof(KissFrameAddr))
  bne @source_loop

  rts

; checks whether we are the source of the frame we just received
; outputs:
;   c - set if we sent the frame, clear otherwise
; modifies:
;   a,y
int_is_our_source:
  ldy #.sizeof(KissFrameAddr)-1
@source_loop:
  lda pk_frame_header+KissFrameHeader::source,y
  cmp pk_tx_header+KissFrameHeader::source,y
  bne @no
  dey
  bpl @source_loop
  sec
  rts
@no:
  clc
  rts

; checks whether the received message is an ack
; outputs:
;   c - set if the frame is an ack, clear otherwise
; modifies:
;   a,x
int_is_ack:
  lda fmt_len
  cmp #(KISS_TYPE_MSG_TEXT_IDX+KISS_ACK_PREFIX_LEN+KISS_MSG_ID_MIN_LEN)
  bcc @not_ack
  cmp #(KISS_TYPE_MSG_TEXT_IDX+KISS_ACK_PREFIX_LEN+KISS_MSG_ID_MAX_LEN+1)
  bcs @not_ack

  ldy #KISS_TYPE_MSG_TEXT_IDX
  lda (fmt_data_lo),y
  cmp #'a'
  bne @not_ack
  iny
  lda (fmt_data_lo),y
  cmp #'c'
  bne @not_ack
  iny
  lda (fmt_data_lo),y
  cmp #'k'
  bne @not_ack
  sec
  rts
@not_ack:
  clc
  rts

; checks the crc of the frame we just read against the ones
; we have recently seen.
;
; inputs:
;   crc_lo/crc_hi - crc of the frame just read
; outputs:
;   c - set if we have already seen this frame, clear otherwise
; modifies:
;   a,x,y
int_check_duplicate:
  ldx #DEDUP_N-1
@scan_loop:
  lda dedup_ttl,x
  beq @next
  lda dedup_crc_lo,x
  cmp crc_lo
  bne @next
  lda dedup_crc_hi,x
  cmp crc_hi
  beq @duplicate
@next:
  dex
  bpl @scan_loop

  ldx dedup_next
  lda crc_lo
  sta dedup_crc_lo,x
  lda crc_hi
  sta dedup_crc_hi,x
  lda #DEDUP_TTL_SECS
  sta dedup_ttl,x

  inx
  txa
  and #DEDUP_N-1
  sta dedup_next

  clc
  rts
@duplicate:
  sec
  rts

; inputs:
;   fmt_hdr_lo/hi - ptr to the frame header
;   x_index_var   - offset in KissFrameHeader to start of address
;   x             - offset in disp buffer to store address
; outputs:
;   x - one past the last char written
; modifies:
;   x_index_var   - will be one past end of this address
;   a,x,y
int_addr_to_buf:
  ldy x_index_var
  lda x_index_var
  clc
  adc #6
  sta x_index_var ; offset to ssid
@loop:
  lda (fmt_hdr_lo),y
  cmp #$20
  beq @loop_done
  sta g_disp_buf,x
  inx
  iny
  cpy x_index_var
  bne @loop
@loop_done:
  ldy x_index_var       ; index to ssid
  lda (fmt_hdr_lo),y    ; ssid
  ; update our index to one past end of this address
  inc x_index_var
  jsr int_ssid_to_buf
  rts

; writes the "-N" suffix for an ssid or nothing if zero
;
; inputs:
;   a - the ssid, 0 to 15
;   x - offset in disp buffer to store at
; outputs:
;   x - one past the last char written
; modifies:
;   a,x,y
int_ssid_to_buf:
  cmp #0
  beq @done
  stx tempx
  jsr ut_bin_to_bcd
  ldx tempx

  lda #'-'
  sta g_disp_buf,x
  inx
  lda ut_result
  lsr
  lsr
  lsr
  lsr
  beq @no_tens
  tay
  lda ut_hex_table_atascii,y
  sta g_disp_buf,x
  inx
@no_tens:
  lda ut_result
  and #%00001111
  tay
  lda ut_hex_table_atascii,y
  sta g_disp_buf,x
  inx
@done:
  rts

;zulu:            .res 1
terminator:      .res 1
x_index_var:     .res 1
x_index_var_end: .res 1
y_index_var:     .res 1
btwn_counter:    .res 1
tempx:           .res 1
tempy:           .res 1
tempchr:         .res 1
ssid_tmp:        .res 1
ssid_text:       .res APRS_SSID_LEN
pk_callsign:     .res APRS_CALLSIGN_LEN
pk_ssid:         .res 1

pk_dest_addr: ; APKTY1
  .byte $82,$A0,$96,$A8,$B2,$62,$E0

pk_state:        .res 1
pk_frame_header: .tag KissFrameHeader
pk_source_addr:  .res .sizeof(KissFrameAddr)
pk_digi_len:     .res 1
pk_digi_addrs:   .res APRS_MAX_DIGI * .sizeof(KissFrameAddr)
pk_error:        .res 1
pk_broadcast_addressee: .byte "CQ",$00

fmt_len:         .res 1
msg_id_lo:       .res 1
msg_id_hi:       .res 1
pk_tx_header:    .tag KissFrameHeader
pk_tx_buf:       .res PK_TX_BUF_LEN
pk_tx_buf_num_chars: .res 1
dedup_next:      .res 1
dedup_tick:      .res 1
dedup_crc_lo:    .res DEDUP_N
dedup_crc_hi:    .res DEDUP_N
dedup_ttl:       .res DEDUP_N

