.setcpu "6502"
.include "atari.inc"
.include "config.inc"
.include "globals.inc"
.include "rs232.inc"
.include "utils.inc"

.segment "CODE"
WRITE_BUF_LEN             = 512
CMD_CONFIGURE_TRANSLATION = $26
CMD_CONTROL               = $22
CMD_CONCURRENCY_MODE      = $28
CMD_CONFIGURE_BAUD        = $24

; inputs:
;   x - channel
rs232_open:
  stx iocb
  lda #1         ; Device 1
  sta ICDNO,x
  lda #<dev_name ; R1
  sta ICBAL,x
  lda #>dev_name ; R1
  sta ICBAH,x
 
  lda #CLOSE
  sta ICCOM,x
  jsr CIOV

  ; set control lines
  ldx iocb
  lda #CMD_CONTROL
  sta ICCOM,x
  lda cfg_saved_config+Cfg::serial+CfgSerial::dtr
  ora cfg_saved_config+Cfg::serial+CfgSerial::rets ; rts
  ora cfg_saved_config+Cfg::serial+CfgSerial::xmt
  sta ICAX1,x
  lda #0
  sta ICAX2,x
  jsr CIOV
  bpl @open_port
  jmp @error
@open_port:
  ; open port
  ldx iocb
  lda #OPEN
  sta ICCOM,x
  lda #$0d ; input, output, concurrent
  sta ICAX1,x
  lda #$00
  sta ICAX2,x
  jsr CIOV
  bpl @configure_baud
  jmp @error
@configure_baud:
  ldx iocb
  lda #CMD_CONFIGURE_BAUD
  sta ICCOM,x
  lda #0
  ora cfg_saved_config+Cfg::serial+CfgSerial::baud
  ora cfg_saved_config+Cfg::serial+CfgSerial::stop_bits
  sta ICAX1,x
  lda cfg_saved_config+Cfg::serial+CfgSerial::dsr
  ora cfg_saved_config+Cfg::serial+CfgSerial::cts
  ora cfg_saved_config+Cfg::serial+CfgSerial::crx
  sta ICAX2,x
  jsr CIOV
  bpl @configure_translation
  jmp @error
@configure_translation:
  ldx iocb
  lda #CMD_CONFIGURE_TRANSLATION
  sta ICCOM,x
  lda cfg_saved_config+Cfg::serial+CfgSerial::translation
  ora cfg_saved_config+Cfg::serial+CfgSerial::parity
  ora cfg_saved_config+Cfg::serial+CfgSerial::line_feed
  sta ICAX1,x
  lda #0
  sta ICAX2,x
  jsr CIOV
  bpl @start_concurrent
  jmp @error
@start_concurrent:
  ; start concurrent mode
  ldx iocb
  lda #CMD_CONCURRENCY_MODE 
  sta ICCOM,x
  lda #<write_buf
  sta ICBAL,x
  lda #>write_buf
  sta ICBAH,x
  lda #<WRITE_BUF_LEN
  sta ICBLL,x
  lda #>WRITE_BUF_LEN
  sta ICBLH,x
  lda #$0c ; concurrent mode
  sta ICAX1,x
  lda #$00
  sta ICAX2,x
  jsr CIOV
  bmi @error
@opened:
  clc
  rts
@error:
  sec
  rts

rs232_status:
  ldx iocb
  lda #STATIS ; CIO status
  sta ICCOM,x
  jsr CIOV
  bmi @error
  
  lda $02ea
  sta rs232_last_status
  lda $02eb
  sta rs232_input_buffer_size
  lda $02ec
  sta rs232_input_buffer_size+1
  lda $02ed
  sta rs232_output_buffer_size
  clc
  rts
@error:
  lda $02ea
  ; TODO: do this elsewhere
  sta rs232_last_status
  sec
  rts

rs232_getchr:
  ldx iocb
  lda #GETCHR
  sta ICCOM,x
  lda #0
  sta ICBLL,x
  lda #0
  sta ICBLH,x
  jsr CIOV
  bmi @error
  clc
  rts
@error:
  sec
  rts

rs232_putchr:
  sta output_char
  ldx iocb
  lda #PUTCHR
  sta ICCOM,x
  lda #0
  sta ICBLL,x
  lda #0
  sta ICBLH,x
  lda output_char
  jsr CIOV
  bmi @error
  clc
  rts
@error:
  sec
  rts

; sends a buf over rs232
; inputs:
;   CMDDATA0/1 - ptr to data
;   CMDDATA2   - size of buf
rs232_putchrs:
  data_ptr_lo = CMDDATA0
  buf_size    = CMDDATA2
  ldy #0
@send_loop:
  sty tempy
  lda (data_ptr_lo),y
  jsr rs232_putchr
  ldy tempy
  bcs @error
  iny
  cpy buf_size
  bne @send_loop
  clc
  rts
@error:
  ldy tempy
  sec
  rts

rs232_close:
  ldx iocb
  lda #CLOSE
  sta ICCOM,x
  jsr CIOV
  bmi @error
@closed:
  clc
  rts
@error:
  sec
  rts

write_buf:                .res WRITE_BUF_LEN
dev_name:                 .byte "R1",$9b
iocb:                     .byte 48
output_char:              .byte 0,$9b
tempy:                    .res 1

rs232_last_status:        .byte 0
rs232_input_buffer_size:  .byte 0, 0
rs232_output_buffer_size: .byte 0
