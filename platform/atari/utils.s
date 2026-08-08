.setcpu "6502"
.include "atari.inc"
.include "globals.inc"
.include "utils.inc"

.segment "ZEROPAGE"

ut_result: .res 4
ut_input:  .res 4

.segment "CODE"

; converts an atascii character to icode,
; used for screen display
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

; Writes char in hex in atascii to (ut_input),y
;
; inputs:
;   ut_input+0/1 - location to print
;   y            - offset from location
;   a            - byte to print 
; modifies:
;   ut_input+2
ut_hex_to_atascii:
  THE_BYTE = ut_input+2
  sta THE_BYTE
  txa
  pha
  tya
  pha

  lda THE_BYTE
  lsr
  lsr
  lsr
  lsr
  tax
  lda ut_hex_table_atascii,x
  sta (ut_input),y
  lda THE_BYTE
  and #%00001111
  tax
  iny
  lda ut_hex_table_atascii,x
  sta (ut_input),y

  pla
  tay
  pla
  tax
  lda THE_BYTE
  rts

; converts the value to bcd format for use in display
;
; inputs:
;   ut_input+0      - value to convert
; outputs:
;   ut_result+0/1/2 - the digits in atascii, left aligned
;   ut_result+3     - num digits written
; modifies:
;   see ut_bin_to_bcd, plus:
;   ut_input+2/3    - contain ut_result+0/1 from ut_bin_to_bcd
;   X,Y
ut_bin_to_bcd_str:
  UBTBS_HUNDREDS  = ut_input+3
  UBTBS_TENS_ONES = ut_input+2

  jsr ut_bin_to_bcd

  ldy #0

  lda ut_result+0
  sta UBTBS_TENS_ONES
  lda ut_result+1
  sta UBTBS_HUNDREDS
  bne @three_digits

  lda UBTBS_TENS_ONES
  lsr
  lsr
  lsr
  lsr
  bne @two_digits
@ones:
  ; all paths end up here because we do the ones no matter what
  lda UBTBS_TENS_ONES
  and #%00001111
  tax
  lda ut_hex_table_atascii,x
  sta ut_result,y
  iny
  bne @done
@three_digits:
  tax
  lda ut_hex_table_atascii,x
  sta ut_result,y
  iny
  lda UBTBS_TENS_ONES
  lsr
  lsr
  lsr
  lsr
  tax
  lda ut_hex_table_atascii,x
  sta ut_result,y
  iny
  bne @ones
@two_digits:
  tax
  lda ut_hex_table_atascii,x
  sta ut_result,y
  iny
  bne @ones
@done:
  sty ut_result+3

  rts

; Thanks to [Andrew Jacobs]( https://6502.org/source/integers/hex2dec-more.htm)
; inputs:
;   ut_input+0  - value to convert
; outputs:
;   ut_result+0 - low nibble is ones, high nibble is 10s
;   ut_result+1 - hundreds digit
; modifies:
;   X
ut_bin_to_bcd:
  lda ut_input+0
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
;   ut_input+0/1 - ptr to the data
;   ut_input+2   - size of the buffer
; outputs:
;   ut_result+0  - index of one past last non-space, zero if all spaces
; modifies:
;   a,y
ut_str_trim_end_find:
  data_ptr_lo = ut_input+0
  buf_size = ut_input+2
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

; takes up to a 3 digit number stored as atascii digits and converts it
; into a byte. All spaces is considered valid and will return 0
;
; the caller must make sure that all digits are either spaces or numbers.
;
; carry will be set if there's an error. Here are some examples
;   - valid, carry will be clear:
;     - "123" -> 123
;     - "8  " -> 8
;     - "67 " -> 67
;     - "   " -> 0
;   - invalid, carry will be set:
;     - " 67"
;     - "8 9"
;   - don't do this or it will return valid but with garbage results:
;     - "ABC"
;     - or anything with chars that aren't numbers or spaces
;
; inputs:
;   ut_input+0/1/2 - the number, in atascii
; outputs:
;   ut_result      - the number, if valid
;   c              - clear if valid number 0 to 255, set otherwise
; modifies:
;   a
ut_bcd_byte_str_to_bin:
  lda ut_input+2
  cmp #' '
  beq @less_than_100
  ; 1's place
  sec
  sbc #'0'
  sta ut_result

  ; 10's place
  lda ut_input+1
  cmp #' '
  beq @error
  sec
  sbc #'0'
  jsr int_mult10
  adc ut_result
  sta ut_result

  ; hundreds place
  lda ut_input+0
  cmp #' '
  beq @error
  sec
  sbc #'0'
  cmp #3
  bcs @error
  jsr int_mult10
  jsr int_mult10
  adc ut_result
  bcs @error
  sta ut_result
  rts
@less_than_100:
  lda ut_input+1
  cmp #' '
  beq @less_than_10
  ; 1's
  sec
  sbc #'0'
  sta ut_result

  lda ut_input+0
  cmp #' '
  beq @error
  sec
  sbc #'0'
  jsr int_mult10
  adc ut_result
  sta ut_result
  rts
@less_than_10:
  lda ut_input+0
  cmp #' '
  beq @zero
  sec
  sbc #'0'
  sta ut_result
  clc
  rts
@zero:
  lda #0
  sta ut_result
  clc
  rts
@error:
  sec
  rts

; multiplies A by ten, using 10x = 8x + 2x
; Thanks to Leo Nechaev for [Fast Multiply by 10](https://6502.org/source/integers/fastx10.htm),
; used mostly verbatim.
;
; inputs:
;   a - the value, must be <26 or it will exit early and set the carry flag
; outputs:
;   a - the value times ten, unchanged if it would overflow
;   c - set if overflowed, clear otherwise
; modifies:
;   a
int_mult10:
  cmp #26
  bcs @error
  asl               ; x2
  sta mult10_tmp
  asl               ; x4
  asl               ; x8
  clc
  adc mult10_tmp    ; x8 + x2
  rts
@error:
  rts

; validates that a space padded field has no leading or interior
; spaces. an all-space (empty) field is also invalid.
; inputs:
;   ut_input+0/1 - ptr to the data
;   ut_input+2   - size of the buffer
; outputs:
;   carry        - clear if valid, set if invalid
; modifies:
;   a,y
ut_str_validate_no_gaps:
  jsr ut_str_trim_end_find
  ldy ut_result
  beq @invalid ; all spaces
  ; now check for spaces before the last non-space char
  dey
@loop:
  lda (ut_input),y
  cmp #' '
  beq @invalid
  dey
  bpl @loop
  clc
  rts
@invalid:
  sec
  rts

bcd_tmp:           .res 1
mult10_tmp:        .res 1

ut_hex_table_atascii: .byte "0123456789ABCDEF"

; subtract 32 from their ATASCII since all are 32 to 95
;hex_table_scr:
;  .byte 16,17,18,19,20,21,22,23,24,25
;  .byte 33,34,35,36,37,38
