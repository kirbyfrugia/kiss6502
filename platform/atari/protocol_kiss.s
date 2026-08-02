.setcpu "6502"
.include "protocol_kiss.inc"
.include "atari.inc"
.include "globals.inc"
.include "rs232.inc"
.include "utils.inc"

.segment "ZEROPAGE"
buf_counter:  .res 1
addr_counter: .res 1

.segment "CODE"

pk_reset:
  lda #KISS_STATE_NEW
  sta pk_state
  jsr pk_next_frame
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

; writes N chars from the given buffer over rs232 as
; a kiss message type with the option of trimming the end
; off the data. i.e. sending until last non-space char.
;
; inputs:
;   CMDDATA0/1 - ptr to the data
;   CMDDATA2/3 - ptr to the addressee
;   CMDDATA4   - size of buf
;   CMDDATA5   - trim flag, set RS232_PUTBUF_TRIM to trim
pk_send_message:
  data_ptr_lo = CMDDATA0
  addressee_ptr_lo = CMDDATA2
  buf_size = CMDDATA4
  trim = CMDDATA5

  lda trim
  bmi @trim
  lda buf_size
  beq @data_empty; was empty string
  sta ut_result
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
  beq @all_spaces; was an empty string
  bne @ready
@all_spaces:
  jmp @done
@ready:
  lda #KISS_FEND
  jsr rs232_putchr
  bcs @error

  lda #KISS_CMD::DATA_FRAME
  jsr rs232_putchr
  bcs @error

  ; TODO: don't hard-code the header
  ldy #0
@dest:
  sty tempy
  lda pk_dest_addr,y
  jsr rs232_putchr
  bcs @error
  ldy tempy
  iny
  cpy #7
  bne @dest 

  ldy #0
@src:
  sty tempy
  lda pk_source_addr,y
  jsr rs232_putchr
  bcs @error
  ldy tempy
  iny
  cpy #7
  bne @src

  lda #$03 ; ui frame
  jsr rs232_putchr
  bcs @error

  lda #$f0 ; PID, no layer 3
  jsr rs232_putchr
  bcs @error

  lda #':'
  jsr rs232_putchr
  bcs @error

  ldy #0
@addressee:
  sty tempy
  lda pk_broadcast_addressee,y
  jsr rs232_putchr
  bcs @error
  ldy tempy
  iny
  cpy #9
  bne @addressee
 
  lda #':'
  jsr rs232_putchr
  bcs @error

  lda CMDDATA2
  pha
  lda ut_result
  sta CMDDATA2
  jsr rs232_putchrs
  pla
  sta CMDDATA2
  bcs @error

  lda #KISS_FEND
  jsr rs232_putchr
  bcs @error
@done:
  clc
  rts
@error:
  ldy rs232_last_status
  sty pk_error
  sec
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
  cmp #'>'
  beq pkpf_status
  bne pkpf_done
pkpf_message:
  jsr int_process_message
  jmp pkpf_done
pkpf_status:
  jsr int_process_status
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

; inputs:
;   
int_process_message:
  lda g_rx_buf_num_chars
  cmp #KISS_TYPE_MSG_END_COLON_IDX
  bcc @done ; not a valid message

  lda #<g_disp_buf
  sta g_temp_data_ptr_lo
  lda #>g_disp_buf
  sta g_temp_data_ptr_hi

  ldy #0
  ldx #KissFrameHeader::source
  stx x_index_var
  jsr int_addr_to_buf

  lda #'>'
  sta g_disp_buf,y

  iny

  lda #KISS_TYPE_MSG_ADDRESSEE_IDX
  sta x_index_var
  lda #KISS_TYPE_MSG_END_COLON_IDX
  sta x_index_var_end
  lda #' '
  sta terminator
  jsr int_read_until_terminator

  lda #KISS_TYPE_MSG_END_COLON_IDX
  sta x_index_var
  lda g_rx_buf_num_chars
  sta x_index_var_end
  lda #'{'
  sta terminator
  jsr int_read_until_terminator
  sty y_index_var
  jsr int_finalize_disp
@done:
  rts

int_process_status:
  lda #<g_disp_buf
  sta g_temp_data_ptr_lo
  lda #>g_disp_buf
  sta g_temp_data_ptr_hi

  ldy #0
  lda #'['
  sta g_disp_buf,y

  iny
  ldx #KissFrameHeader::source
  stx x_index_var
  jsr int_addr_to_buf

  lda #']'
  sta g_disp_buf,y

  iny

  ; empty statuses are allowed, but we don't
  ; want to try parsing the string
  lda g_rx_buf_num_chars
  cmp #2 ; first char is '>' no matter what
  bcs @not_empty
  jmp @finalize
@not_empty:
  lda #' '
  sta g_disp_buf,y

  lda g_rx_buf_num_chars
  cmp #KISS_TYPE_STATUS_TIMESTAMP_ZULU_IDX
  bcc @nozulu
  ldx #KISS_TYPE_STATUS_TIMESTAMP_ZULU_IDX
  lda g_rx_buf,x
  cmp #'z'
  beq @zulu
  cmp #'Z'
  beq @zulu
  ldx #1
  bne @nozulu
@zulu:
  ; might be a timestamp, confirm
  ldx #1
  stx x_index_var
  ldx #KISS_TYPE_STATUS_TIMESTAMP_ZULU_IDX
  stx x_index_var_end
  jsr int_all_digits
  bcc @nozulu

  lda #' '
  sta g_disp_buf,y

  ; it's a timestamp. Convert from DDHHmm to HH:mm
  ldx #3
  iny
  lda g_rx_buf,x
  sta g_disp_buf,y
  iny
  inx
  lda g_rx_buf,x
  sta g_disp_buf,y
  iny
  lda #':'
  sta g_disp_buf,y
  iny
  inx
  lda g_rx_buf,x
  sta g_disp_buf,y
  iny
  inx
  lda g_rx_buf,x
  sta g_disp_buf,y
  iny
  lda #' '
  sta g_disp_buf,y
  inx
  inx
@nozulu:
  iny
  stx x_index_var
  lda g_rx_buf_num_chars
  sta x_index_var_end
  jsr int_read_until_end
@finalize:
  sty y_index_var
  jsr int_finalize_disp
@done:
  rts

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

; reads from x_index_var to x_index_var_end
; and sets the carry bit if it's all digits,
; otherwise it clears the carry bit
; inputs:
;   x_index_var        - start index to check
;   x_index_var_end    - end index to check (one past)
; outputs:
;   C - sec if all digits, clc otherwise
int_all_digits:
  ldx x_index_var
@loop:
  lda g_rx_buf,x
  cmp $30 ; ascii 0
  bcc @nozulu
  cmp $39 ; ascii 9 + 1
  bcs @nozulu
  inx
  cpx x_index_var_end
  bne @loop
  sec
  rts
@nozulu:
  clc
  rts

; reads from rx_buf from x_index_var to x_index_var_end
; or the given terminator char appears
;
; assumes x_index_var_end - x_index_var > 1
;
; inputs:
;   terminator            - char to search for or $00 until
;   g_temp_data_ptr_lo/hi - pointer to where to store output
;   x_index_var           - start index to check
;   x_index_var_end       - end index to check (one past)
;   y                     - start index to write to
; outputs:
;   x - index of last read char + 1
;   y - index of last written char + 1
int_read_until_terminator:
  ldx x_index_var
@loop:
  lda g_rx_buf,x
  cmp terminator
  beq @done
  sta (g_temp_data_ptr_lo),y
  iny
  inx
  cpx x_index_var_end
  bne @loop
@done:
  rts

; reads from rx_buf from x_index_var to x_index_var_end
;
; assumes x_index_var_end - x_index_var > 1
;
; inputs:
;   g_temp_data_ptr_lo/hi - pointer to where to store output
;   x_index_var           - start index to check
;   x_index_var_end       - end index to check (one past)
;   y                     - start index to write to
; outputs:
;   x - index of last read char + 1
;   y - index of last written char + 1
int_read_until_end:
  ldx x_index_var
@loop:
  lda g_rx_buf,x
  sta (g_temp_data_ptr_lo),y
  iny
  inx
  cpx x_index_var_end
  bne @loop
@done:
  rts


int_ack_message:
  rts

; inputs:
;   g_temp_data_ptr_lo/hi - address of line
;   x_index_var        - offset in KissFrameHeader to start of address
;   y                  - offset in disp buffer to store address
; modifies:
;   x_index_var        - will be one past end of this address
;   a,x,y
int_addr_to_buf:
  lda x_index_var
  tax
  clc
  adc #6
  sta x_index_var ; offset to ssid
@loop:
  lda pk_frame_header,x
  cmp #$20
  beq @loop_done
  sta (g_temp_data_ptr_lo),y
  iny
  inx
  cpx x_index_var
  bne @loop
@loop_done:
  ldx x_index_var       ; index to ssid
  lda pk_frame_header,x ; ssid
  beq @done             ; ssid of zero
  jsr ut_bin_to_bcd

  lda #'-'
  sta (g_temp_data_ptr_lo),y
  lda ut_result
  lsr
  lsr
  lsr
  lsr
  beq @no_tens
  tax
  lda ut_hex_table_atascii,x
  iny
  sta (g_temp_data_ptr_lo),y 
@no_tens:
  iny
  lda ut_result
  and #%00001111
  tax
  lda ut_hex_table_atascii,x
  sta (g_temp_data_ptr_lo),y
  iny
@done:
  ; update our x to one past end of this address
  inc x_index_var
  rts

zulu:            .res 1
terminator:      .res 1
x_index_var:     .res 1
x_index_var_end: .res 1
y_index_var:     .res 1
btwn_counter:    .res 1
tempy:           .res 1

pk_dest_addr: ; APKTY1
  .byte $82,$A0,$96,$A8,$B2,$62,$E0

pk_state:        .res 1
pk_frame_header: .tag KissFrameHeader
pk_source_addr:  .res .sizeof(KissFrameAddr)
pk_error:        .res 1
pk_broadcast_addressee: .byte "CQ       "

