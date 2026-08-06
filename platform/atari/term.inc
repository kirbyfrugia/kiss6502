.ifndef TERM_INC
TERM_INC = 1

.global trm_init
.global trm_activate
.global trm_deactivate
.global trm_tick

TERM_EOL_CR      = $0d
TERM_EOL_LF      = $0a
TERM_EOL_ATASCII = $9b

.enum TERMINAL_MODE
  NONE  = %00000000
  CHAR  = %10000000
  LINE  = %01000000
.endenum

.enum TERM_LINE_ENDING
  CR      = 0
  LF      = 1
  CRLF    = 2
  ATASCII = 3
.endenum

.enum TERM_PROTOCOL
  TERM = %10000000
  APRS = %01000000
  RTTY = %00100000
.endenum

.macro print_str str
  lda #<str
  sta CMDDATA0
  lda #>str
  sta CMDDATA1

  jsr to_println
.endmacro

.macro print_str_with_code str, buf, err_code
  lda #<str
  sta CMDDATA0
  lda #>str
  sta CMDDATA1

  lda #<buf
  sta CMDDATA2
  lda #>buf
  sta CMDDATA3

  lda err_code
  sta CMDDATA4
  jsr ut_str_with_code_to_buf

  lda #<buf
  sta CMDDATA0
  lda #>buf
  sta CMDDATA1
  jsr to_println
.endmacro

.endif

