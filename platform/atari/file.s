.setcpu "6502"
.include "atari.inc"
.include "file.inc"
.include "globals.inc"
.include "utils.inc"

.segment "CODE"
FILE_OPEN_READ  = $04 ; open for input
FILE_OPEN_WRITE = $08 ; open for output (truncate/create)
FILE_EOF        = $88 ; CIO end of file status

; opens iocb using the mode in A and the filespec in CMDDATA0/1.
; the filespec must be a full EOL ($9b) terminated CIO name including
; the device and drive, e.g. "D1:FOO.DAT",$9b
;
; inputs:
;   A          - open mode (FILE_OPEN_READ or FILE_OPEN_WRITE)
;   CMDDATA0/1 - ptr to filespec
; outputs:
;   carry clear on success, set on error
int_file_open:
  fname_ptr_lo = CMDDATA0

  sta file_open_mode

  ; close first in case the channel was left open
  ldx iocb
  lda #CLOSE
  sta ICCOM,x
  jsr CIOV

  ; open the file
  ldx iocb
  lda fname_ptr_lo
  sta ICBAL,x
  lda fname_ptr_lo+1
  sta ICBAH,x
  lda #OPEN
  sta ICCOM,x
  lda file_open_mode
  sta ICAX1,x
  lda #0
  sta ICAX2,x
  jsr CIOV
  bmi @error
  clc
  rts
@error:
  sec
  rts

int_file_close:
  ldx iocb
  lda #CLOSE
  sta ICCOM,x
  jsr CIOV
  rts

; loads a file into a buffer.
;
; inputs:
;   CMDDATA0/1 - ptr to full filespec (e.g. "D1:FOO.DAT",EOL)
;   CMDDATA2/3 - ptr to destination buffer
;   CMDDATA4/5 - max bytes to read
; outputs:
;   CMDDATA4/5 - actual bytes read
;   carry - clear on success, set on error
file_load:
  lda #FILE_OPEN_READ
  jsr int_file_open
  bcs @error

  ldx iocb
  lda #GETCHR
  sta ICCOM,x
  lda CMDDATA2
  sta ICBAL,x
  lda CMDDATA3
  sta ICBAH,x
  lda CMDDATA4
  sta ICBLL,x
  lda CMDDATA5
  sta ICBLH,x
  jsr CIOV

  ; report how many bytes were actually read
  ldx iocb
  lda ICBLL,x
  sta CMDDATA4
  lda ICBLH,x
  sta CMDDATA5

  cpy #FILE_EOF
  beq @read_ok
  cpy #$80
  bcs @close_error
@read_ok:
  jsr int_file_close
  clc
  rts
@close_error:
  jsr int_file_close
@error:
  sec
  rts

; saves a buffer to a file.
;
; inputs:
;   CMDDATA0/1 - ptr to full filespec (e.g. "D1:FOO.DAT",EOL)
;   CMDDATA2/3 - ptr to source buffer
;   CMDDATA4/5 - number of bytes to write
; outputs:
;   carry - clear on success, set on error
file_save:
  lda #FILE_OPEN_WRITE
  jsr int_file_open
  bcs @error

  ; write the whole buffer out
  ldx iocb
  lda #PUTCHR
  sta ICCOM,x
  lda CMDDATA2
  sta ICBAL,x
  lda CMDDATA3
  sta ICBAH,x
  lda CMDDATA4
  sta ICBLL,x
  lda CMDDATA5
  sta ICBLH,x
  jsr CIOV
  bmi @close_error

  jsr int_file_close
  clc
  rts
@close_error:
  jsr int_file_close
@error:
  sec
  rts

iocb:           .byte 16 ; channel 1
file_open_mode: .byte 0
