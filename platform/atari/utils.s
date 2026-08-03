.setcpu "6502"
.include "atari.inc"
.include "globals.inc"
.include "utils.inc"


.segment "ZEROPAGE"

bcd_tmp:   .res 1
ut_result: .res 4
ut_input:  .res 4

.segment "CODE"

; converts an atascii character to icode,
; used for screen display
;
;
; Reference: Mapping the atari, $e108
; inputs:
;   a - the character in atascii
; modifies/outputs:
;   a - the char in icode
ut_atascii_to_icode:
  cmp #32
  bcs @check_gteq_32
  ; 0 to 31, add 64
  clc
  adc #64
  bne @done
@check_gteq_32:
  cmp #96
  bcs @check_gteq_96
  ; 32 to 95, sub 32
  sec
  sbc #32
  jmp @done
@check_gteq_96:
  cmp #128
  bcs @check_gteq_128
  ; 96 to 127, no change
  bne @done
@check_gteq_128:
  cmp #160
  bcs @check_gteq_160
  ; 128 to 159, add 64
  clc
  adc #64
  bne @done
@check_gteq_160:
  cmp #224
  bcs @gteq_224
  ; 160 to 223, sub 32
  sec
  sbc #32
  bne @done
@gteq_224:
  ; 224 to 255, no change
@done:
  rts

; Writes char in hex in atascii to (CMDDATA0),y
;
; inputs:
;   - CMDDATA0/CMDDATA1 - location to print
;   - y - offset from location
;   - a - byte to print 
ut_hex_to_atascii:
  sta tmp_byte_to_str
  txa
  pha
  tya
  pha

  lda tmp_byte_to_str
  lsr
  lsr
  lsr
  lsr
  tax
  lda ut_hex_table_atascii,x
  sta (CMDDATA0),y
  lda tmp_byte_to_str
  and #%00001111
  tax
  iny
  lda ut_hex_table_atascii,x
  sta (CMDDATA0),y

  pla
  tay
  pla
  tax
  lda tmp_byte_to_str
  rts


; Writes char in icode to (CMDDATA0),y
;
; inputs:
;   - CMDDATA0/CMDDATA1 - location to print
;   - y - offset from location
;   - a - byte to print 
ut_hex_to_icode:
  sta tmp_byte_to_str
  txa
  pha
  tya
  pha

  lda tmp_byte_to_str
  lsr
  lsr
  lsr
  lsr
  tax
  lda hex_table_scr,x
  sta (CMDDATA0),y
  lda tmp_byte_to_str
  and #%00001111
  tax
  iny
  lda hex_table_scr,x
  sta (CMDDATA0),y

  pla
  tay
  pla
  tax
  lda tmp_byte_to_str
  rts

; Multiples a 32-bit number by 91
; APRS uses base-91 encoding/decoding for positions
; in some messages.
;
; 91 = 1 + 2 + 8 + 16 + 64
; 91 * n = n + 2n + 8n +16n + 64n
;
; inputs:
ut_mult_32bitX91:

  ; TODO: obviously I haven't implemented this yet.
  lda ut_input+0
  sta ut_result+0
  lda ut_input+1
  sta ut_result+1
  lda ut_input+2
  sta ut_result+2
  lda ut_input+3
  sta ut_result+3

  rts

; converts an ssid into its decimal digits, left aligned
;
; inputs:
;   a - the ssid, 0 to 15
; outputs:
;   ut_ssid_digits - the digits
;   ut_ssid_len    - number of digits, 1 or 2
; modifies:
;   a,y
ut_ssid_to_digits:
  cmp #10
  bcs @tens
  clc
  adc #'0'
  sta ut_ssid_digits+0
  ldy #1
  sty ut_ssid_len
  jmp @done
@tens:
  sbc #10
  clc
  adc #'0'
  sta ut_ssid_digits+1
  lda #'1'
  sta ut_ssid_digits+0
  ldy #2
  sty ut_ssid_len
@done:
  rts

; Thanks to [Andrew Jacobs]( https://6502.org/source/integers/hex2dec-more.htm)
; inputs:
;   A - value to convert
; outputs:
;   ut_result+0 = low nibble is ones, high nibble is 10s
;   ut_result+1 = hundreds digit
; modifies:
;   A and X
ut_bin_to_bcd:
  sta bcd_tmp
  lda #0
  sta ut_result+0
  sta ut_result+1
  ldx #8

  sed
@loop:
  asl bcd_tmp
  lda ut_result+0
  adc ut_result+0
  sta ut_result+0
  lda ut_result+1
  adc ut_result+1
  sta ut_result+1
  dex
  bne @loop
  cld

  rts

; copies the null-terminated string to the given
; output buffer.
;
; inputs:
;   CMDDATA0/1 - ptr to string
;   CMDDATA2/3 - ptr to buf
; outputs:
;   y - index of the null byte character
; modifies:
;   y
ut_str_to_buf:
  ldy #0
@loop:
  lda (CMDDATA0),y
  beq @done
  sta (CMDDATA2),y
  iny
  bne @loop
@done:
  sta (CMDDATA2),y ; add the null at the end
  rts

; writes the null-terminated string and byte code
; in bcd to the given output buffer with a ": "
; separating. Writes a null at the end of the str.
;
; inputs:
;   CMDDATA0/1 - ptr to string
;   CMDDATA2/3 - ptr to buf
;   CMDDATA4   - error code
ut_str_with_code_to_buf:
  jsr ut_str_to_buf
  lda #':'
  sta (CMDDATA2),y
  iny
  lda #' '
  sta (CMDDATA2),y

  lda CMDDATA4
  jsr ut_bin_to_bcd

  lda ut_result+1
  beq @no_hundreds
  tax
  lda ut_hex_table_atascii,x
  iny
  sta (CMDDATA2),y 
@no_hundreds:
  lda ut_result
  lsr
  lsr
  lsr
  lsr
  beq @no_tens
  tax
  lda ut_hex_table_atascii,x
  iny
  sta (CMDDATA2),y 
@no_tens:
  iny
  lda ut_result
  and #%00001111
  tax
  lda ut_hex_table_atascii,x
  sta (CMDDATA2),y

  iny
  lda #$00
  sta (CMDDATA2),y

  rts

; checks if char is an alphanumeric atascii char
; (0-9, A-Z, a-z). a is preserved.
;
; inputs:
;   a - the character
; outputs:
;   carry - clear if alphanumeric, set otherwise
ut_is_alphanumeric:
  cmp #'0'
  bcc @no
  cmp #'9'+1
  bcc @yes
  cmp #'A'
  bcc @no
  cmp #'Z'+1
  bcc @yes
  cmp #'a'
  bcc @no
  cmp #'z'+1
  bcs @no
@yes:
  clc
  rts
@no:
  sec
  rts

; maps a lowercase ascii letter to uppercase. anything else
; comes back unchanged.
;
; inputs:
;   a - the character
; outputs:
;   a - the uppercased character
ut_to_upper:
  cmp #'a'
  bcc @done
  cmp #'z'+1
  bcs @done
  sec
  sbc #('a'-'A')
@done:
  rts

; maps an ascii digit to its 0-9 value.
; inputs:
;   a - the character
; outputs:
;   a     - the digit value, unchanged if not a digit
;   carry - clear if a held a digit, set otherwise
ut_ascii_char_to_digit:
  cmp #'0'
  bcc @not_digit
  cmp #'9'+1
  bcs @not_digit
  sec
  sbc #'0'
  clc
  rts
@not_digit:
  sec
  rts

; finds the last non-space character in the given data buf, returning
; zero if all spaces. also returns zero if the buffer size is zero.
;
; inputs:
;   CMDDATA0/1  - ptr to the data
;   CMDDATA2    - size of the buffer
; outputs:
;   ut_result+0 - index of one past last non-space, zero if all spaces
; modifies:
;   a,y
ut_str_trim_end_find:
  data_ptr_lo = CMDDATA0
  buf_size = CMDDATA2
  ; find the last non space char in the buf
  ; put_data_size will be one after that
  ldy buf_size
  beq @result ; empty buf, result is zero
  dey
@trim_loop:
  lda (data_ptr_lo),y
  cmp #' '
  bne @found
  dey
  cpy #$ff
  bne @trim_loop
  ; if here, rolled over without finding a non-space
  ; so result should be zero, which will be set by the iny below
@found:
  iny
@result:
  sty ut_result
@done:
  rts

; validates that a space padded field has no leading or interior
; spaces. an all-space (empty) field is also invalid.
; inputs:
;   CMDDATA0/1 - ptr to the data
;   CMDDATA2   - size of the buffer
; outputs:
;   carry - clear if valid, set if invalid
; modifies:
;   a,y
ut_str_validate_no_gaps:
  jsr ut_str_trim_end_find
  ldy ut_result
  beq @invalid ; all spaces
  ; now check for spaces before the last non-space char
  dey
@loop:
  lda (CMDDATA0),y
  cmp #' '
  beq @invalid
  dey
  bpl @loop
  clc
  rts
@invalid:
  sec
  rts

ut_ssid_digits:  .res 2
ut_ssid_len:     .res 1

ut_hex_table_atascii: .byte "0123456789ABCDEF"

; subtract 32 from their ATASCII since all are 32 to 95
hex_table_scr:
  .byte 16,17,18,19,20,21,22,23,24,25
  .byte 33,34,35,36,37,38

tmp_byte_to_str: .byte 0
