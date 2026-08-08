.ifndef UTILS_INC
UTILS_INC = 1

.globalzp ut_input
.globalzp ut_result
.global   ut_atascii_to_icode
.global   ut_hex_table_atascii
.global   ut_hex_to_atascii
.global   ut_bin_to_bcd_str
.global   ut_bin_to_bcd
.global   ut_bcd_byte_str_to_bin
.global   ut_str_trim_end_find
.global   ut_str_validate_no_gaps
.global   ut_is_alphanumeric
.global   ut_ascii_char_to_digit
.global   ut_to_upper

; compares 16 bit x to y, branches appropriately
.macro ut_cmp16 _x, _y, branch_xlty, branch_xeqy, branch_xgty
  lda _x+1
  cmp _y+1
  bcc branch_xlty
  bne branch_xgty
  lda _x
  cmp _y
  bcc branch_xlty
  bne branch_xgty
  beq branch_xeqy
.endmacro

; stores the min of x and y in out
.macro ut_min8 arg1, arg2, out
  .local done
  lda arg1
  cmp arg2
  bcc done
  lda arg2
done:
  sta out
.endmacro

.macro ut_copy_struct_abs_to_zp src_addr, dest_zp_ptr, struct_type
  .local loop
  ldy #.sizeof(struct_type) - 1
loop:
  lda src_addr,y
  sta (dest_zp_ptr),y
  dey
  bpl loop
.endmacro

.macro ut_copy_struct_zp_to_abs src_zp_ptr, dest_addr, struct_type
  .local loop
  ldy #.sizeof(struct_type) - 1
loop:
  lda (src_zp_ptr),y
  sta dest_addr,y
  dey
  bpl loop
.endmacro

.macro ut_copy_struct_abs_to_abs src_addr, dest_addr, struct_type
  .local loop
  ldy #.sizeof(struct_type) - 1
loop:
  lda src_addr,y
  sta dest_addr,y
  dey
  bpl loop
.endmacro

.macro ut_copy_struct_zp_to_zp src_zp_ptr, dest_zp_ptr, struct_type
  .local loop
  ldy #.sizeof(struct_type) - 1
loop:
  lda (src_zp_ptr),y
  sta (dest_zp_ptr),y
  dey
  bpl loop
.endmacro

; fills char A from addr,y to addr,width-1
; inputs:
;   addr  - address at start of line
;   width - line width
;   A     - the char to fill
;   Y     - index from ptr
; modifies:
;   Y - will be at one past end (unless it was past end when called)
.macro ut_fill_to_end_ptr ptr, width
  .local loop
  .local loop_done
loop:
  cpy width
  bcs loop_done
  sta (ptr),y
  iny
  bne loop
loop_done:

.endmacro

; inverts a string on screen (bg/fg swap)
.macro ut_invstr str
  .repeat .strlen(str), i
    .byte .strat(str, i) | $80
  .endrepeat
.endmacro

; writes out a byte in bcd to buf, indexed by x.
; assumes x is already at start index and A holds the value.
; increments x as it goes, leaving it one past the end of the digits
; See ut_bin_to_bcd_str for more details
.macro ut_byte_to_bcd_str_x buf
  .local loop
  sta ut_input+0
  txa
  pha
  jsr ut_bin_to_bcd_str
  pla
  tax
  ldy #0
loop:
  lda ut_result,y
  sta buf,x
  inx
  iny
  cpy ut_result+3
  bne loop
.endmacro

; writes spaces to buf, starting at x until end (non-inclusive)
.macro ut_pad_x buf, end
  .local loop
  .local done
  lda #' '
loop:
  cpx #end
  bcs done
  sta buf,x
  inx
  bne loop
done:
.endmacro

; lda, indexed by y, converted to uppercase. see ut_to_upper
; for more details
.macro ut_lda_x_to_upper buf
  lda buf,x
  jsr ut_to_upper
.endmacro

.endif
