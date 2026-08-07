.setcpu "6502"

.include "atari.inc" ; /usr/share/cc65/asminc/atari.inc
.include "config.inc"
.include "file.inc"
.include "form.inc"
.include "globals.inc"
.include "line_input.inc"
.include "protocol_kiss.inc"
.include "rs232.inc"
.include "screen.inc"
.include "term.inc"
.include "utils.inc"
.include "version.inc"

.segment "ZEROPAGE"

.segment "CODE"
.linecont +


CONFIG_VERSION    = 1
CFG_NAME_LEN      = 8
CFG_LASTFILE_LEN  = 1 + CFG_NAME_LEN


int_load_default_config:
  make_config cfg_draft_config, \
                  TERM_PROTOCOL::APRS, \
                  TERMINAL_MODE::LINE, \
                  TERM_LINE_ENDING::CR, \
                  RS232_BAUD::B9600, \
                  RS232_WORDSIZE::N8, \
                  RS232_STOPBITS::N1, \
                  RS232_PARITY::NONE, \
                  RS232_CTS::OFF, \
                  RS232_DSR::OFF, \
                  RS232_DTR::ON, \
                  RS232_RTS::ON

  lda #CONFIG_VERSION
  sta cfg_draft_config+Cfg::version

  ldx #APRS_CALLSIGN_LEN-1
  lda #' '
@callsign_loop:
  sta cfg_draft_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::callsign,x
  dex
  bpl @callsign_loop

  lda #0
  sta cfg_draft_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::ssid
  sta cfg_draft_config+Cfg::aprs+CfgAprs::num_digi

  jsr int_aprstab_config_to_text
  rts

cfg_init:
  lda #CONFIG_FLAG_EDITING
  sta cfg_config_flag

  jsr int_load_default_config
  ut_copy_struct_abs_to_abs cfg_draft_config, cfg_saved_config, Cfg

  jsr int_filetab_init
  jsr int_sessiontab_init
  jsr int_serialtab_init
  jsr int_termtab_init
  jsr int_aprstab_init

  rts

int_sessiontab_init:
  lda #SESSION_FIELD_FIRST
  sta session_form+Form::first
  lda #SESSION_FIELD_COUNT
  sta session_form+Form::count
  lda #0
  sta session_form+Form::focus
  rts

int_serialtab_init:
  lda #SERIAL_FIELD_FIRST
  sta serial_form+Form::first
  lda #SERIAL_FIELD_COUNT
  sta serial_form+Form::count
  lda #0
  sta serial_form+Form::focus
  rts

int_termtab_init:
  lda #TERM_FIELD_FIRST
  sta term_form+Form::first
  lda #TERM_FIELD_COUNT
  sta term_form+Form::count
  lda #0
  sta term_form+Form::focus
  rts

int_draw_tabs:
  lda SCR_PTR_LO
  clc
  adc #(2*SCREEN_WIDTH)
  sta g_temp_scr_ptr_lo
  lda SCR_PTR_HI
  adc #0
  sta g_temp_scr_ptr_hi

  ; the dialog border fills this row, so draw the labels over it,
  ; starting at column 1 to keep the border's left corner
  ldy #1
@tabs_banner_loop:
  lda tabs_banner,y
  beq @tabs_banner_done
  ;eor #$80
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  iny
  jmp @tabs_banner_loop
@tabs_banner_done:

  ldx selected_tab
  ldy tabs_highlight_starts,x
@highlight_loop:
  lda (g_temp_scr_ptr_lo),y
  eor #$80
  sta (g_temp_scr_ptr_lo),y
  iny
  tya
  cmp tabs_highlight_ends,x
  bne @highlight_loop
  
  rts

int_draw_dialog_border:
  lda SCR_PTR_LO
  clc
  adc #(2*SCREEN_WIDTH)
  sta g_temp_scr_ptr_lo
  lda SCR_PTR_HI
  adc #0
  sta g_temp_scr_ptr_hi

  ldy #(SCREEN_WIDTH-1)
  lda #ICODE_UPPER_RIGHT_CORNER
  sta (g_temp_scr_ptr_lo),y
  lda #ICODE_HORIZONTAL_BAR
@top_loop:
  dey
  sta (g_temp_scr_ptr_lo),y
  bne @top_loop
  lda #ICODE_UPPER_LEFT_CORNER
  sta (g_temp_scr_ptr_lo),y

  ldx #(SCREEN_HEIGHT-6)
@sides_loop:
  lda g_temp_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  lda g_temp_scr_ptr_hi
  adc #0
  sta g_temp_scr_ptr_hi

  lda #ICODE_VERTICAL_BAR
  ldy #0
  sta (g_temp_scr_ptr_lo),y
  ldy #(SCREEN_WIDTH-1)
  sta (g_temp_scr_ptr_lo),y
  dex
  bne @sides_loop

  lda g_temp_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  lda g_temp_scr_ptr_hi
  adc #0
  sta g_temp_scr_ptr_hi

  ldy #(SCREEN_WIDTH-1)
  lda #ICODE_LOWER_RIGHT_CORNER
  sta (g_temp_scr_ptr_lo),y
  lda #ICODE_HORIZONTAL_BAR
@btm_loop:
  dey
  sta (g_temp_scr_ptr_lo),y
  bne @btm_loop
  lda #ICODE_LOWER_LEFT_CORNER
  sta (g_temp_scr_ptr_lo),y
  rts

VERSION_OFFSET   = 19*SCREEN_WIDTH+32

; draws the banners and the "Preset" label
; and any other ui elements
int_draw_main:
  jsr int_draw_dialog_border

  lda SCR_PTR_LO
  sta g_temp_scr_ptr_lo
  lda SCR_PTR_HI
  sta g_temp_scr_ptr_hi

  ldy #(SCREEN_WIDTH-1)
  lda #' '
  eor #$80
  jsr ut_atascii_to_icode
@top_banner_clear_loop:
  sta (g_temp_scr_ptr_lo),y
  dey
  bpl @top_banner_clear_loop

  ldy #0
@top_banner_loop:
  lda top_banner,y
  beq @top_banner_loop_done
  eor #$80
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  iny
  jmp @top_banner_loop
@top_banner_loop_done:

  lda #<VERSION_OFFSET
  clc
  adc SCR_PTR_LO
  sta g_temp_scr_ptr_lo
  lda #>VERSION_OFFSET
  adc SCR_PTR_HI
  sta g_temp_scr_ptr_hi

  ldy #0
@version_loop:
  lda v_version,y
  beq @version_loop_done
  eor #$80
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  iny
  jmp @version_loop
@version_loop_done:
  jsr int_draw_tabs
  rts

int_refresh_menus:
  ldx selected_tab
  lda tab_form_ptrs_lo,x
  sta CMDDATA0
  lda tab_form_ptrs_hi,x
  sta CMDDATA1
  jsr fm_set_context
  jsr fm_draw_all
  rts

START_STATUS_OFFSET   = 22*SCREEN_WIDTH+1
START_STATUS_WIDTH    = 36

int_start_show_status:
  jsr int_start_clear_status
  lda #<START_STATUS_OFFSET
  sta CMDDATA2
  lda #>START_STATUS_OFFSET
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str
  rts

int_start_clear_status:
  lda #<START_STATUS_OFFSET
  clc
  adc SCR_PTR_LO
  sta g_temp_scr_ptr_lo
  lda #>START_STATUS_OFFSET
  adc SCR_PTR_HI
  sta g_temp_scr_ptr_hi

  ldy #(START_STATUS_WIDTH-1)
  lda #ICODE_SPACE
@loop:
  sta (g_temp_scr_ptr_lo),y
  dey
  bpl @loop
  rts

FILE_LABEL_OFFSET      = 5*SCREEN_WIDTH+2
FILE_FIELD_OFFSET      = 5*SCREEN_WIDTH+14
FILE_SUFFIX_OFFSET     = FILE_FIELD_OFFSET+CFG_NAME_LEN+1
FILE_BTN_LOAD_OFFSET   = 7*SCREEN_WIDTH+2
FILE_BTN_SAVE_OFFSET   = 8*SCREEN_WIDTH+2
FILE_BTN_DEF_OFFSET    = 9*SCREEN_WIDTH+2
FILE_HINT_OFFSET       = 19*SCREEN_WIDTH+2
FILE_STATUS_OFFSET     = 11*SCREEN_WIDTH+2
FILE_STATUS_WIDTH      = 36

FILE_FIELD_FIRST       = 0
FILE_FIELD_COUNT       = 4

FILE_ACTION_LOAD       = 1
FILE_ACTION_SAVE       = 2
FILE_ACTION_DEFAULT    = 3

APRS_CALL_LABEL_OFFSET = 5*SCREEN_WIDTH+2
APRS_CALL_FIELD_OFFSET = 5*SCREEN_WIDTH+16
APRS_SSID_LABEL_OFFSET = 6*SCREEN_WIDTH+2
APRS_SSID_FIELD_OFFSET = 6*SCREEN_WIDTH+16
APRS_DIGI_LABEL_OFFSET = 7*SCREEN_WIDTH+2
APRS_DIGI_FIELD_OFFSET = 7*SCREEN_WIDTH+16
APRS_DIGI_VISIBLE      = 22
APRS_HINT_OFFSET       = 19*SCREEN_WIDTH+2

APRS_FIELD_FIRST       = 15
APRS_FIELD_COUNT       = 3

SERIAL_BAUD_LABEL_OFFSET   = 5*SCREEN_WIDTH+2
SERIAL_BAUD_FIELD_OFFSET   = 5*SCREEN_WIDTH+13
SERIAL_DATA_LABEL_OFFSET   = 6*SCREEN_WIDTH+2
SERIAL_DATA_FIELD_OFFSET   = 6*SCREEN_WIDTH+13
SERIAL_STOP_LABEL_OFFSET   = 7*SCREEN_WIDTH+2
SERIAL_STOP_FIELD_OFFSET   = 7*SCREEN_WIDTH+13
SERIAL_PARITY_LABEL_OFFSET = 8*SCREEN_WIDTH+2
SERIAL_PARITY_FIELD_OFFSET = 8*SCREEN_WIDTH+13
SERIAL_CTS_LABEL_OFFSET    = 9*SCREEN_WIDTH+2
SERIAL_CTS_FIELD_OFFSET    = 9*SCREEN_WIDTH+13
SERIAL_DSR_LABEL_OFFSET    = 10*SCREEN_WIDTH+2
SERIAL_DSR_FIELD_OFFSET    = 10*SCREEN_WIDTH+13
SERIAL_DTR_LABEL_OFFSET    = 11*SCREEN_WIDTH+2
SERIAL_DTR_FIELD_OFFSET    = 11*SCREEN_WIDTH+13
SERIAL_RTS_LABEL_OFFSET    = 12*SCREEN_WIDTH+2
SERIAL_RTS_FIELD_OFFSET    = 12*SCREEN_WIDTH+13
SERIAL_HINT_OFFSET         = 19*SCREEN_WIDTH+2

SERIAL_FIELD_FIRST     = 7
SERIAL_FIELD_COUNT     = 8

SESSION_LABEL_OFFSET   = 5*SCREEN_WIDTH+2
SESSION_FIELD_OFFSET   = 5*SCREEN_WIDTH+12
SESSION_HINT_OFFSET    = 19*SCREEN_WIDTH+2

SESSION_FIELD_FIRST    = 6
SESSION_FIELD_COUNT    = 1

TERM_MODE_LABEL_OFFSET = 5*SCREEN_WIDTH+2
TERM_MODE_FIELD_OFFSET = 5*SCREEN_WIDTH+15
TERM_EOL_LABEL_OFFSET  = 6*SCREEN_WIDTH+2
TERM_EOL_FIELD_OFFSET  = 6*SCREEN_WIDTH+15
TERM_HINT_OFFSET       = 19*SCREEN_WIDTH+2

TERM_FIELD_FIRST       = 4
TERM_FIELD_COUNT       = 2

int_filetab_init:
  jsr int_load_lastfile

  lda #FILE_FIELD_FIRST
  sta file_form+Form::first
  lda #FILE_FIELD_COUNT
  sta file_form+Form::count
  lda #0
  sta file_form+Form::focus

  lda #0
  sta cfg_filename_li+LineInput::scr_cursor
  sta cfg_filename_li+LineInput::data_cursor
  sta cfg_filename_li+LineInput::first_visible

  lda #<FILE_FIELD_OFFSET
  clc
  adc SCR_PTR_LO
  sta cfg_filename_li+LineInput::scr_ptr
  lda #>FILE_FIELD_OFFSET
  adc SCR_PTR_HI
  sta cfg_filename_li+LineInput::scr_ptr+1

  lda #<cfg_filename_text
  sta cfg_filename_li+LineInput::data_ptr
  lda #>cfg_filename_text
  sta cfg_filename_li+LineInput::data_ptr+1
  lda #CFG_NAME_LEN
  sta cfg_filename_li+LineInput::num_visible
  lda #CFG_NAME_LEN
  sta cfg_filename_li+LineInput::data_size
  rts

int_filetab_save_file:
  jsr int_filetab_filename_valid
  bcs @invalid
  jsr int_aprstab_form_to_config
  bcs @invalid_aprs
  jsr cfg_save_config
  bcs @failed
  lda #<msg_saved
  sta CMDDATA0
  lda #>msg_saved
  sta CMDDATA1
  jsr int_filetab_show_status
  rts
@failed:
  lda #<msg_save_failed
  sta CMDDATA0
  lda #>msg_save_failed
  sta CMDDATA1
  jsr int_filetab_show_status
  rts
@invalid_aprs:
  jsr int_filetab_show_status
  rts
@invalid:
  jsr int_filetab_show_invalid
  rts

int_filetab_load:
  jsr int_filetab_filename_valid
  bcs @invalid
  jsr cfg_load_config
  bcs @failed
  jsr int_aprstab_config_to_text
  lda #<msg_loaded
  sta CMDDATA0
  lda #>msg_loaded
  sta CMDDATA1
  jsr int_filetab_show_status
  rts
@failed:
  lda #<msg_load_failed
  sta CMDDATA0
  lda #>msg_load_failed
  sta CMDDATA1
  jsr int_filetab_show_status
  rts
@invalid:
  jsr int_filetab_show_invalid
  rts

; checks if the file name is valid
; outputs:
;   c     - set if invalid, clear if valid
;         - e.g. space in the middle of the file name
; modifies:
;   CMDDATA0/1/2
;   a,y
int_filetab_filename_valid:
  lda #<cfg_filename_text
  sta CMDDATA0
  lda #>cfg_filename_text
  sta CMDDATA1
  lda #CFG_NAME_LEN
  sta CMDDATA2
  jsr ut_str_validate_no_gaps
  rts

; shows the message in CMDDATA0/1 on the status line, clearing first
; inputs:
;   CMDDATA0/1 - ptr to the message
int_filetab_show_status:
  jsr int_filetab_clear_status
  lda #<FILE_STATUS_OFFSET
  sta CMDDATA2
  lda #>FILE_STATUS_OFFSET
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str
  rts

int_filetab_show_invalid:
  lda #<msg_invalid_filename
  sta CMDDATA0
  lda #>msg_invalid_filename
  sta CMDDATA1
  jsr int_filetab_show_status
  rts

int_filetab_clear_status:
  lda #<FILE_STATUS_OFFSET
  clc
  adc SCR_PTR_LO
  sta g_temp_scr_ptr_lo
  lda #>FILE_STATUS_OFFSET
  adc SCR_PTR_HI
  sta g_temp_scr_ptr_hi

  ldy #(FILE_STATUS_WIDTH-1)
  lda #ICODE_SPACE
@loop:
  sta (g_temp_scr_ptr_lo),y
  dey
  bpl @loop
  rts

; draws the buttons for the aprs tab
; modifies:
;   a,x,y
;   CMDDATA0-4
int_aprstab_init:
  lda #APRS_FIELD_FIRST
  sta aprs_form+Form::first
  lda #APRS_FIELD_COUNT
  sta aprs_form+Form::count
  lda #0
  sta aprs_form+Form::focus

  lda #0
  sta cfg_callsign_li+LineInput::scr_cursor
  sta cfg_callsign_li+LineInput::data_cursor
  sta cfg_callsign_li+LineInput::first_visible
  lda #<APRS_CALL_FIELD_OFFSET
  clc
  adc SCR_PTR_LO
  sta cfg_callsign_li+LineInput::scr_ptr
  lda #>APRS_CALL_FIELD_OFFSET
  adc SCR_PTR_HI
  sta cfg_callsign_li+LineInput::scr_ptr+1
  lda #<cfg_callsign_text
  sta cfg_callsign_li+LineInput::data_ptr
  lda #>cfg_callsign_text
  sta cfg_callsign_li+LineInput::data_ptr+1
  lda #APRS_CALLSIGN_LEN
  sta cfg_callsign_li+LineInput::num_visible
  sta cfg_callsign_li+LineInput::data_size

  lda #0
  sta cfg_ssid_li+LineInput::scr_cursor
  sta cfg_ssid_li+LineInput::data_cursor
  sta cfg_ssid_li+LineInput::first_visible
  lda #<APRS_SSID_FIELD_OFFSET
  clc
  adc SCR_PTR_LO
  sta cfg_ssid_li+LineInput::scr_ptr
  lda #>APRS_SSID_FIELD_OFFSET
  adc SCR_PTR_HI
  sta cfg_ssid_li+LineInput::scr_ptr+1
  lda #<cfg_ssid_text
  sta cfg_ssid_li+LineInput::data_ptr
  lda #>cfg_ssid_text
  sta cfg_ssid_li+LineInput::data_ptr+1
  lda #APRS_SSID_LEN
  sta cfg_ssid_li+LineInput::num_visible
  sta cfg_ssid_li+LineInput::data_size

  lda #0
  sta cfg_digi_li+LineInput::scr_cursor
  sta cfg_digi_li+LineInput::data_cursor
  sta cfg_digi_li+LineInput::first_visible
  lda #<APRS_DIGI_FIELD_OFFSET
  clc
  adc SCR_PTR_LO
  sta cfg_digi_li+LineInput::scr_ptr
  lda #>APRS_DIGI_FIELD_OFFSET
  adc SCR_PTR_HI
  sta cfg_digi_li+LineInput::scr_ptr+1
  lda #<cfg_digi_text
  sta cfg_digi_li+LineInput::data_ptr
  lda #>cfg_digi_text
  sta cfg_digi_li+LineInput::data_ptr+1
  lda #APRS_DIGI_VISIBLE
  sta cfg_digi_li+LineInput::num_visible
  lda #APRS_DIGI_LEN
  sta cfg_digi_li+LineInput::data_size

  rts

int_aprstab_config_to_text:
  jsr int_aprstab_callsign_to_text
  jsr int_aprstab_ssid_to_text
  jsr int_aprstab_digi_to_text

  lda #0
  sta cfg_callsign_li+LineInput::scr_cursor
  sta cfg_callsign_li+LineInput::data_cursor
  sta cfg_callsign_li+LineInput::first_visible
  sta cfg_ssid_li+LineInput::scr_cursor
  sta cfg_ssid_li+LineInput::data_cursor
  sta cfg_ssid_li+LineInput::first_visible
  sta cfg_digi_li+LineInput::scr_cursor
  sta cfg_digi_li+LineInput::data_cursor
  sta cfg_digi_li+LineInput::first_visible
  rts

int_aprstab_callsign_to_text:
  ldy #APRS_CALLSIGN_LEN-1
@copy_loop:
  lda cfg_draft_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::callsign,y
  sta cfg_callsign_text,y
  dey
  bpl @copy_loop
  rts

; converts the draft config ssid byte (0-15) into digits
; for the ssid field.
int_aprstab_ssid_to_text:
  lda cfg_draft_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::ssid
  cmp #10
  bcc @single
  sbc #10
  ldx #'1'
  stx cfg_ssid_text+0
  clc
  adc #'0'
  sta cfg_ssid_text+1
  rts
@single:
  clc
  adc #'0'
  sta cfg_ssid_text+0
  lda #' '
  sta cfg_ssid_text+1
  rts

; validates and converts the ssid field into a hex value for saving
; outputs:
;   c - set if invalid ssid, clear otherwise
int_aprstab_text_to_ssid:
  lda #<cfg_ssid_text
  sta CMDDATA0
  lda #>cfg_ssid_text
  sta CMDDATA1
  jsr pk_text_to_ssid
  bcs @error
  sta cfg_draft_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::ssid
  clc
  rts
@error:
  sec
  rts

; validates and converts the callsign field, uppercasing it
; on the way into the draft config.
; outputs:
;   c - set if invalid callsign, clear otherwise
int_aprstab_text_to_callsign:
  lda #<cfg_callsign_text
  sta CMDDATA0
  lda #>cfg_callsign_text
  sta CMDDATA1
  lda #APRS_CALLSIGN_LEN
  sta CMDDATA2
  jsr ut_str_trim_end_find
  lda ut_result
  beq @blank
  jsr ut_str_validate_no_gaps
  bcs @error
  ldy #APRS_CALLSIGN_LEN-1
@upper_loop:
  lda cfg_callsign_text,y
  cmp #' '
  beq @store
  jsr ut_to_upper
  jsr ut_is_alphanumeric
  bcs @error
@store:
  sta cfg_draft_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::callsign,y
  dey
  bpl @upper_loop
  clc
  rts
@blank:
  ldy #APRS_CALLSIGN_LEN-1
  lda #' '
@blank_loop:
  sta cfg_draft_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::callsign,y
  dey
  bpl @blank_loop
  clc
  rts
@error:
  sec
  rts

; validates and converts the digi field into an array of callsign+ssid.
; splits the text on commas. an entry may have spaces around it but not
; inside it, so it ends at its first space and the rest up to the comma
; must be blank. empty text means no digipeaters and is valid.
; outputs:
;   c - set if any entry was invalid, clear otherwise
int_aprstab_text_to_digi:
  ; clear stale slots
  lda #0
  ldx #.sizeof(CfgAprsAddr)*APRS_MAX_DIGI-1
@clear_loop:
  sta cfg_draft_config+Cfg::aprs+CfgAprs::digi,x
  dex
  bpl @clear_loop

  lda #<cfg_digi_text
  sta CMDDATA0
  lda #>cfg_digi_text
  sta CMDDATA1
  lda #APRS_DIGI_LEN
  sta CMDDATA2
  jsr ut_str_trim_end_find

  lda #0
  sta digi_count
  sta digi_entry_start
  sta digi_write_offset
  lda ut_result
  sta digi_text_end
  bne @addr_loop
  jmp @done
@addr_loop:
  ; skip any spaces in front of this entry
  ldy digi_entry_start
@skip_space_loop:
  cpy digi_text_end
  bne @skip_space_check
  jmp @error
@skip_space_check:
  lda cfg_digi_text,y
  cmp #' '
  bne @skip_space_done
  iny
  bne @skip_space_loop
@skip_space_done:
  ; scan to the next comma or the end of the text
  sty digi_entry_start
@sep_loop:
  cpy digi_text_end
  beq @sep_done
  lda cfg_digi_text,y
  cmp #','
  beq @sep_done
  iny
  bne @sep_loop
@sep_done:
  ; but it really ends at the first space inside it
  sty digi_entry_sep
  ldy digi_entry_start
@entry_end_loop:
  cpy digi_entry_sep
  beq @entry_end_done
  lda cfg_digi_text,y
  cmp #' '
  beq @entry_end_done
  iny
  bne @entry_end_loop
@entry_end_done:
  ; everything from there to the comma has to be spaces
  sty digi_entry_end
@gap_loop:
  cpy digi_entry_sep
  beq @gap_done
  lda cfg_digi_text,y
  cmp #' '
  bne @error
  iny
  bne @gap_loop
@gap_done:
  lda digi_entry_end
  sec
  sbc digi_entry_start
  beq @error
  sta CMDDATA2

  lda digi_count
  cmp #APRS_MAX_DIGI
  bcs @error

  lda #<cfg_digi_text
  clc
  adc digi_entry_start
  sta CMDDATA0
  lda #>cfg_digi_text
  adc #0
  sta CMDDATA1
  jsr pk_parse_callsign
  bcs @error

  jsr int_aprstab_store_digi
  inc digi_count

  ; step past the comma, a trailing one is an error
  ldy digi_entry_sep
  cpy digi_text_end
  beq @done
  iny
  sty digi_entry_start
  cpy digi_text_end
  beq @error
  jmp @addr_loop
@error:
  sec
  rts
@done:
  lda digi_count
  sta cfg_draft_config+Cfg::aprs+CfgAprs::num_digi
  clc
  rts

; converts all three aprs fields into the draft config. a blank
; callsign is allowed here, callers that require one check for it.
; outputs:
;   CMDDATA0/1 - ptr to the error message when carry is set
;   c          - set if any field was invalid, clear otherwise
int_aprstab_form_to_config:
  jsr int_aprstab_text_to_callsign
  bcs @callsign_error
  jsr int_aprstab_text_to_ssid
  bcs @ssid_error
  jsr int_aprstab_text_to_digi
  bcs @digi_error
  clc
  rts
@callsign_error:
  lda #<msg_invalid_callsign
  sta CMDDATA0
  lda #>msg_invalid_callsign
  sta CMDDATA1
  sec
  rts
@ssid_error:
  lda #<msg_invalid_ssid
  sta CMDDATA0
  lda #>msg_invalid_ssid
  sta CMDDATA1
  sec
  rts
@digi_error:
  lda #<msg_invalid_digi
  sta CMDDATA0
  lda #>msg_invalid_digi
  sta CMDDATA1
  sec
  rts

int_aprstab_store_digi:
  ldy digi_write_offset
  ldx #0
@copy_loop:
  lda pk_callsign,x
  sta cfg_draft_config+Cfg::aprs+CfgAprs::digi,y
  iny
  inx
  cpx #APRS_CALLSIGN_LEN
  bne @copy_loop
  lda pk_ssid
  sta cfg_draft_config+Cfg::aprs+CfgAprs::digi,y
  iny
  sty digi_write_offset
  rts

; converts the draft config digi array into text
; for the digi form field.
int_aprstab_digi_to_text:
  lda #0
  sta digi_count
  ldx #0
  ldy #0
@addr_loop:
  lda digi_count
  cmp cfg_draft_config+Cfg::aprs+CfgAprs::num_digi
  bcs @fill
  stx digi_entry_sep
@call_loop:
  lda cfg_draft_config+Cfg::aprs+CfgAprs::digi,x
  cmp #' '
  beq @call_done
  sta cfg_digi_text,y
  iny
  inx
  txa
  sec
  sbc digi_entry_sep
  cmp #APRS_CALLSIGN_LEN
  bcc @call_loop
@call_done:
  lda digi_entry_sep
  clc
  adc #APRS_CALLSIGN_LEN
  tax
  lda cfg_draft_config+Cfg::aprs+CfgAprs::digi,x
  beq @addr_done
  sta digi_entry_sep
  lda #'-'
  sta cfg_digi_text,y
  iny
  lda digi_entry_sep
  cmp #10
  bcc @ssid_ones
  sbc #10
  pha
  lda #'1'
  sta cfg_digi_text,y
  iny
  pla
@ssid_ones:
  clc
  adc #'0'
  sta cfg_digi_text,y
  iny
@addr_done:
  inx
  inc digi_count
  lda digi_count
  cmp cfg_draft_config+Cfg::aprs+CfgAprs::num_digi
  bcs @fill
  lda #','
  sta cfg_digi_text,y
  iny
  jmp @addr_loop
@fill:
  lda #' '
@fill_loop:
  cpy #APRS_DIGI_LEN
  bcs @done
  sta cfg_digi_text,y
  iny
  jmp @fill_loop
@done:
  rts

int_draw_tab_static:
  ldx selected_tab
  lda tab_static_first,x
  sta static_idx
  clc
  adc tab_static_count,x
  sta static_end
@static_loop:
  ldx static_idx
  lda cfg_static_ptrs_lo,x
  sta CMDDATA0
  lda cfg_static_ptrs_hi,x
  sta CMDDATA1
  lda cfg_static_offs_lo,x
  sta CMDDATA2
  lda cfg_static_offs_hi,x
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str
  inc static_idx
  lda static_idx
  cmp static_end
  bne @static_loop
  rts

cfg_activate:
  lda #0
  sta cfg_select_fired
  sta cfg_start_fired
  sta selected_tab

  lda #CONFIG_FLAG_EDITING
  sta cfg_config_flag

  ut_copy_struct_abs_to_abs cfg_saved_config, cfg_draft_config, Cfg
  jsr int_aprstab_config_to_text

  jsr int_draw_tab_static
  jsr int_refresh_menus
  jsr int_draw_main

  rts

; inputs:
;   cfg_ptr_lo/HI   - pointer to menu struct
int_cmd_cancel:
  ; make sure they've started at least once
  ; or config will be invalid
  lda started_once
  beq @never_started
  lda #CONFIG_FLAG_CANCELED
  sta cfg_config_flag
  jmp @done
@never_started:
  lda #<msg_start_first
  sta CMDDATA0
  lda #>msg_start_first
  sta CMDDATA1
  jsr int_start_show_status
@done:
  rts

int_cmd_start:
  jsr int_aprstab_form_to_config
  bcs @show_error

  lda cfg_draft_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::APRS
  bne @start

  lda cfg_draft_config+Cfg::aprs+CfgAprs::me+CfgAprsAddr::callsign
  cmp #' '
  bne @start
  lda #<msg_invalid_callsign
  sta CMDDATA0
  lda #>msg_invalid_callsign
  sta CMDDATA1
@show_error:
  jsr int_start_show_status
  sec
  rts
@start:
  ut_copy_struct_abs_to_abs cfg_draft_config, cfg_saved_config, Cfg
  lda #CONFIG_FLAG_START
  sta cfg_config_flag
  lda #1
  sta started_once
  clc
  rts

int_highlight_selected_tab:
  rts

int_next_tab:
  ldy selected_tab
  iny
  cpy num_tabs
  bne @updated
  ldy #0
@updated:
  sty selected_tab
  jsr scr_cls
  jsr int_draw_main
  jsr int_draw_tabs
  jsr int_draw_tab_static
  jsr int_refresh_menus
  rts

int_handle_console_keys:
  lda cfg_start_fired
  bne @start
  lda cfg_select_fired
  bne @next_tab
  clc
  beq @done
@next_tab:
  jsr int_next_tab
  sec
  jmp @done
@start:
  jsr int_cmd_start
  sec
@done:
  rts

int_form_handle_kbd:
  lda #FM_ACTION_NONE
  sta fm_action
  lda g_kbdcode_raw
  cmp #KEY_ESC
  beq @escape
  jsr fm_handle_key
  jmp @done
@escape:
  jsr int_cmd_cancel
@done:
  rts

int_handle_kbd:
  lda g_kbd_key_pressed
  beq @done
  jsr int_form_handle_kbd
  lda fm_action
  cmp #FILE_ACTION_LOAD
  beq @do_load
  cmp #FILE_ACTION_SAVE
  beq @do_save
  cmp #FILE_ACTION_DEFAULT
  beq @do_default
  jmp @done
@do_load:
  jsr int_filetab_clear_status
  jsr int_filetab_load
  jmp @done
@do_save:
  jsr int_filetab_clear_status
  jsr int_filetab_save_file
  jmp @done
@do_default:
  jsr int_filetab_clear_status
  jsr int_load_default_config
@done:
  rts

cfg_tick:
  jsr int_handle_console_keys
  bcs @done ; handled one of the special keys
  jsr int_handle_kbd
@done:
  lda #0
  sta cfg_select_fired
  sta cfg_start_fired
  rts

; assembles "Dn:<name>.CFG",EOL into cfg_filespec from cfg_drive and
; the space-padded name in cfg_filename_text.
cfg_build_filespec:
  lda #'D'
  sta cfg_filespec
  lda cfg_drive
  clc
  adc #'0'
  sta cfg_filespec+1
  lda #':'
  sta cfg_filespec+2

  ldx #0
@name_loop:
  lda cfg_filename_text,x
  cmp #' '
  beq @name_done
  sta cfg_filespec+3,x
  inx
  cpx #CFG_NAME_LEN
  bne @name_loop
@name_done:
  txa
  clc
  adc #3
  tay
  lda #'.'
  sta cfg_filespec,y
  iny
  lda #'C'
  sta cfg_filespec,y
  iny
  lda #'F'
  sta cfg_filespec,y
  iny
  lda #'G'
  sta cfg_filespec,y
  iny
  lda #EOL
  sta cfg_filespec,y
  rts

; writes the draft config to Dn:<name>.CFG and updates the lastfile
; outputs:
;   c - clear on success, set on error
cfg_save_config:
  jsr cfg_build_filespec

  lda #<cfg_filespec
  sta CMDDATA0
  lda #>cfg_filespec
  sta CMDDATA1
  lda #<cfg_draft_config
  sta CMDDATA2
  lda #>cfg_draft_config
  sta CMDDATA3
  lda #<.sizeof(Cfg)
  sta CMDDATA4
  lda #>.sizeof(Cfg)
  sta CMDDATA5
  jsr file_save
  bcs @error

  jsr cfg_save_lastfile
  clc
  rts
@error:
  sec
  rts

; reads Dn:<name>.CFG into the draft config.
; outputs:
;   c - clear on success, set on error
cfg_load_config:
  jsr cfg_build_filespec

  lda #<cfg_filespec
  sta CMDDATA0
  lda #>cfg_filespec
  sta CMDDATA1
  lda #<cfg_draft_config
  sta CMDDATA2
  lda #>cfg_draft_config
  sta CMDDATA3
  lda #<.sizeof(Cfg)
  sta CMDDATA4
  lda #>.sizeof(Cfg)
  sta CMDDATA5
  jsr file_load
  bcs @error

  lda CMDDATA4
  cmp #<.sizeof(Cfg)
  bne @error
  lda CMDDATA5
  cmp #>.sizeof(Cfg)
  bne @error
  lda cfg_draft_config+Cfg::version
  cmp #CONFIG_VERSION
  beq @valid
@error:
  jsr int_load_default_config
  sec
  rts
@valid:
  jsr cfg_save_lastfile
  clc
  rts

; stores the last saved or loaded filename in a hard-coded
; file so we can load their last file on boot.
; outputs:
;   c - clear on success, set on error
cfg_save_lastfile:
  lda cfg_drive
  sta cfg_lastfile_data
  ldx #CFG_NAME_LEN-1
@copy:
  lda cfg_filename_text,x
  sta cfg_lastfile_data+1,x
  dex
  bpl @copy

  lda #<cfg_lastfile_filespec
  sta CMDDATA0
  lda #>cfg_lastfile_filespec
  sta CMDDATA1
  lda #<cfg_lastfile_data
  sta CMDDATA2
  lda #>cfg_lastfile_data
  sta CMDDATA3
  lda #CFG_LASTFILE_LEN
  sta CMDDATA4
  lda #0
  sta CMDDATA5
  jsr file_save
  rts

; loads the last file saved or loaded into cfg_drive and cfg_filename_text.
; on error (e.g. first boot) falls back to drive 1 and a blank name.
;
; on-disk format: "DXXXXXXXX"
;   D         - drive number
;    XXXXXXXX - file name (CFG_NAME_LEN chars), trailing space padded
;
; outputs:
;   c - clear on success, set on error
int_load_lastfile:
  lda #<cfg_lastfile_filespec
  sta CMDDATA0
  lda #>cfg_lastfile_filespec
  sta CMDDATA1
  lda #<cfg_lastfile_data
  sta CMDDATA2
  lda #>cfg_lastfile_data
  sta CMDDATA3
  lda #CFG_LASTFILE_LEN
  sta CMDDATA4
  lda #0
  sta CMDDATA5
  jsr file_load
  bcs @default

  lda CMDDATA4
  cmp #CFG_LASTFILE_LEN
  bne @default
  lda CMDDATA5
  bne @default

  lda cfg_lastfile_data+0
  sta cfg_drive
  ldx #CFG_NAME_LEN-1
@copy:
  lda cfg_lastfile_data+1,x
  sta cfg_filename_text,x
  dex
  bpl @copy
  clc
  rts
@default:
  lda #1
  sta cfg_drive
  ldx #CFG_NAME_LEN-1
  lda #' '
@blank_loop:
  sta cfg_filename_text,x
  dex
  bpl @blank_loop
  sec
  rts

cfg_field_kind:
  .byte FIELD_TEXT, FIELD_BUTTON, FIELD_BUTTON, FIELD_BUTTON
  .byte FIELD_SELECT, FIELD_SELECT
  .byte FIELD_SELECT
  .byte FIELD_SELECT, FIELD_SELECT, FIELD_SELECT, FIELD_SELECT, FIELD_SELECT, FIELD_SELECT, FIELD_SELECT, FIELD_SELECT
  .byte FIELD_TEXT, FIELD_TEXT, FIELD_TEXT
cfg_field_scr_lo:
  .byte <FILE_FIELD_OFFSET, <FILE_BTN_LOAD_OFFSET, <FILE_BTN_SAVE_OFFSET, <FILE_BTN_DEF_OFFSET
  .byte <TERM_MODE_FIELD_OFFSET, <TERM_EOL_FIELD_OFFSET
  .byte <SESSION_FIELD_OFFSET
  .byte <SERIAL_BAUD_FIELD_OFFSET, <SERIAL_DATA_FIELD_OFFSET, <SERIAL_STOP_FIELD_OFFSET, <SERIAL_PARITY_FIELD_OFFSET, <SERIAL_CTS_FIELD_OFFSET, <SERIAL_DSR_FIELD_OFFSET, <SERIAL_DTR_FIELD_OFFSET, <SERIAL_RTS_FIELD_OFFSET
  .byte <APRS_CALL_FIELD_OFFSET, <APRS_SSID_FIELD_OFFSET, <APRS_DIGI_FIELD_OFFSET
cfg_field_scr_hi:
  .byte >FILE_FIELD_OFFSET, >FILE_BTN_LOAD_OFFSET, >FILE_BTN_SAVE_OFFSET, >FILE_BTN_DEF_OFFSET
  .byte >TERM_MODE_FIELD_OFFSET, >TERM_EOL_FIELD_OFFSET
  .byte >SESSION_FIELD_OFFSET
  .byte >SERIAL_BAUD_FIELD_OFFSET, >SERIAL_DATA_FIELD_OFFSET, >SERIAL_STOP_FIELD_OFFSET, >SERIAL_PARITY_FIELD_OFFSET, >SERIAL_CTS_FIELD_OFFSET, >SERIAL_DSR_FIELD_OFFSET, >SERIAL_DTR_FIELD_OFFSET, >SERIAL_RTS_FIELD_OFFSET
  .byte >APRS_CALL_FIELD_OFFSET, >APRS_SSID_FIELD_OFFSET, >APRS_DIGI_FIELD_OFFSET
cfg_field_width:
  .byte CFG_NAME_LEN, 6, 6, 15
  .byte 7, 7
  .byte 8
  .byte 6, 6, 6, 6, 6, 6, 6, 6
  .byte APRS_CALLSIGN_LEN, APRS_SSID_LEN, APRS_DIGI_VISIBLE
cfg_field_data_lo:
  .byte <cfg_filename_li, <btn_load, <btn_save, <btn_default
  .byte <(cfg_draft_config+Cfg::term+CfgTerm::terminal_mode),<(cfg_draft_config+Cfg::term+CfgTerm::line_ending)
  .byte <(cfg_draft_config+Cfg::session+CfgSession::protocol)
  .byte <(cfg_draft_config+Cfg::serial+CfgSerial::baud), <(cfg_draft_config+Cfg::serial+CfgSerial::data_bits), <(cfg_draft_config+Cfg::serial+CfgSerial::stop_bits), <(cfg_draft_config+Cfg::serial+CfgSerial::parity), <(cfg_draft_config+Cfg::serial+CfgSerial::cts), <(cfg_draft_config+Cfg::serial+CfgSerial::dsr), <(cfg_draft_config+Cfg::serial+CfgSerial::dtr), <(cfg_draft_config+Cfg::serial+CfgSerial::rets)
  .byte <cfg_callsign_li, <cfg_ssid_li, <cfg_digi_li
cfg_field_data_hi:
  .byte >cfg_filename_li, >btn_load, >btn_save, >btn_default
  .byte >(cfg_draft_config+Cfg::term+CfgTerm::terminal_mode),>(cfg_draft_config+Cfg::term+CfgTerm::line_ending)
  .byte >(cfg_draft_config+Cfg::session+CfgSession::protocol)
  .byte >(cfg_draft_config+Cfg::serial+CfgSerial::baud), >(cfg_draft_config+Cfg::serial+CfgSerial::data_bits), >(cfg_draft_config+Cfg::serial+CfgSerial::stop_bits), >(cfg_draft_config+Cfg::serial+CfgSerial::parity), >(cfg_draft_config+Cfg::serial+CfgSerial::cts), >(cfg_draft_config+Cfg::serial+CfgSerial::dsr), >(cfg_draft_config+Cfg::serial+CfgSerial::dtr), >(cfg_draft_config+Cfg::serial+CfgSerial::rets)
  .byte >cfg_callsign_li, >cfg_ssid_li, >cfg_digi_li
cfg_field_values_lo:
  .byte 0, 0, 0, 0
  .byte <term_mode_field_values, <term_eol_field_values
  .byte <session_protocol_field_values
  .byte <serial_baud_field_values, <serial_data_field_values, <serial_stop_field_values, <serial_parity_field_values, <serial_cts_field_values, <serial_dsr_field_values, <serial_dtr_field_values, <serial_rts_field_values
  .byte 0, 0, 0
cfg_field_values_hi:
  .byte 0, 0, 0, 0
  .byte >term_mode_field_values, >term_eol_field_values
  .byte >session_protocol_field_values
  .byte >serial_baud_field_values, >serial_data_field_values, >serial_stop_field_values, >serial_parity_field_values, >serial_cts_field_values, >serial_dsr_field_values, >serial_dtr_field_values, >serial_rts_field_values
  .byte 0, 0, 0
cfg_field_labels_lo:
  .byte 0, 0, 0, 0
  .byte <term_mode_field_labels_lo, <term_eol_field_labels_lo
  .byte <session_protocol_field_labels_lo
  .byte <serial_baud_field_labels_lo, <serial_data_field_labels_lo, <serial_stop_field_labels_lo, <serial_parity_field_labels_lo, <serial_cts_field_labels_lo, <serial_dsr_field_labels_lo, <serial_dtr_field_labels_lo, <serial_rts_field_labels_lo
  .byte 0, 0, 0
cfg_field_labels_hi:
  .byte 0, 0, 0, 0
  .byte >term_mode_field_labels_lo, >term_eol_field_labels_lo
  .byte >session_protocol_field_labels_lo
  .byte >serial_baud_field_labels_lo, >serial_data_field_labels_lo, >serial_stop_field_labels_lo, >serial_parity_field_labels_lo, >serial_cts_field_labels_lo, >serial_dsr_field_labels_lo, >serial_dtr_field_labels_lo, >serial_rts_field_labels_lo
  .byte 0, 0, 0
cfg_field_arg0:
  .byte CHAR_ALPHA|CHAR_DIGIT|CHAR_SPACE, FILE_ACTION_LOAD, FILE_ACTION_SAVE, FILE_ACTION_DEFAULT
  .byte 2, 4
  .byte 2
  .byte 15, 4, 2, 3, 2, 2, 3, 3
  .byte CHAR_ALPHA|CHAR_DIGIT|CHAR_SPACE, CHAR_DIGIT|CHAR_SPACE, CHAR_ALPHA|CHAR_DIGIT|CHAR_SPACE|CHAR_DASH|CHAR_COMMA
cfg_field_arg1:
  .byte INPUT_UPPER, 0, 0, 0
  .byte 0, 0
  .byte 0
  .byte 0, 0, 0, 0, 0, 0, 0, 0
  .byte INPUT_UPPER, 0, INPUT_UPPER

serial_baud_field_values:
  .byte RS232_BAUD::B45_5, RS232_BAUD::B50, RS232_BAUD::B56_875, RS232_BAUD::B75, RS232_BAUD::B110, RS232_BAUD::B134_5, RS232_BAUD::B150, RS232_BAUD::B300, RS232_BAUD::B600, RS232_BAUD::B1200, RS232_BAUD::B1800, RS232_BAUD::B2400, RS232_BAUD::B4800, RS232_BAUD::B9600, RS232_BAUD::B19200
serial_baud_field_labels_lo:
  .byte <item_45_5, <item_50, <item_56_875, <item_75, <item_110, <item_134_5, <item_150, <item_300, <item_600, <item_1200, <item_1800, <item_2400, <item_4800, <item_9600, <item_19200
serial_baud_field_labels_hi:
  .byte >item_45_5, >item_50, >item_56_875, >item_75, >item_110, >item_134_5, >item_150, >item_300, >item_600, >item_1200, >item_1800, >item_2400, >item_4800, >item_9600, >item_19200

serial_data_field_values:
  .byte RS232_WORDSIZE::N5, RS232_WORDSIZE::N6, RS232_WORDSIZE::N7, RS232_WORDSIZE::N8
serial_data_field_labels_lo:
  .byte <item_5bit, <item_6bit, <item_7bit, <item_8bit
serial_data_field_labels_hi:
  .byte >item_5bit, >item_6bit, >item_7bit, >item_8bit

serial_stop_field_values:
  .byte RS232_STOPBITS::N1, RS232_STOPBITS::N2
serial_stop_field_labels_lo:
  .byte <item_1bit, <item_2bit
serial_stop_field_labels_hi:
  .byte >item_1bit, >item_2bit

serial_parity_field_values:
  .byte RS232_PARITY::NONE, RS232_PARITY::EVEN, RS232_PARITY::ODD
serial_parity_field_labels_lo:
  .byte <item_none, <item_even, <item_odd
serial_parity_field_labels_hi:
  .byte >item_none, >item_even, >item_odd

serial_cts_field_values:
  .byte RS232_CTS::OFF, RS232_CTS::ON
serial_cts_field_labels_lo:
  .byte <item_off, <item_on
serial_cts_field_labels_hi:
  .byte >item_off, >item_on

serial_dsr_field_values:
  .byte RS232_DSR::OFF, RS232_DSR::ON
serial_dsr_field_labels_lo:
  .byte <item_off, <item_on
serial_dsr_field_labels_hi:
  .byte >item_off, >item_on

serial_dtr_field_values:
  .byte RS232_DTR::NO_CHANGE, RS232_DTR::OFF, RS232_DTR::ON
serial_dtr_field_labels_lo:
  .byte <item_nc, <item_off, <item_on
serial_dtr_field_labels_hi:
  .byte >item_nc, >item_off, >item_on

serial_rts_field_values:
  .byte RS232_RTS::NO_CHANGE, RS232_RTS::OFF, RS232_RTS::ON
serial_rts_field_labels_lo:
  .byte <item_nc, <item_off, <item_on
serial_rts_field_labels_hi:
  .byte >item_nc, >item_off, >item_on

session_protocol_field_values:
  .byte TERM_PROTOCOL::APRS, TERM_PROTOCOL::TERM
session_protocol_field_labels_lo:
  .byte <item_aprs, <item_terminal
session_protocol_field_labels_hi:
  .byte >item_aprs, >item_terminal

term_mode_field_values:
  .byte TERMINAL_MODE::LINE, TERMINAL_MODE::CHAR
term_mode_field_labels_lo:
  .byte <item_line, <item_char
term_mode_field_labels_hi:
  .byte >item_line, >item_char

term_eol_field_values:
  .byte TERM_LINE_ENDING::CR, TERM_LINE_ENDING::LF, TERM_LINE_ENDING::CRLF, TERM_LINE_ENDING::ATASCII
term_eol_field_labels_lo:
  .byte <item_cr, <item_lf, <item_crlf, <item_atascii
term_eol_field_labels_hi:
  .byte >item_cr, >item_lf, >item_crlf, >item_atascii

item_45_5:              .byte "45.5",$00
item_50:                .byte "50",$00
item_56_875:            .byte "56.875",$00
item_75:                .byte "75",$00
item_110:               .byte "110",$00
item_134_5:             .byte "134.5",$00
item_150:               .byte "150",$00
item_300:               .byte "300",$00
item_600:               .byte "600",$00
item_1200:              .byte "1200",$00
item_1800:              .byte "1800",$00
item_2400:              .byte "2400",$00
item_4800:              .byte "4800",$00
item_9600:              .byte "9600",$00
item_19200:             .byte "19200",$00
item_5bit:              .byte "5 bit",$00
item_6bit:              .byte "6 bit",$00
item_7bit:              .byte "7 bit",$00
item_8bit:              .byte "8 bit",$00
item_1bit:              .byte "1 bit",$00
item_2bit:              .byte "2 bit",$00
item_none:              .byte "None",$00
item_even:              .byte "Even",$00
item_odd:               .byte "Odd",$00
item_off:               .byte "OFF",$00
item_on:                .byte "ON",$00
item_nc:                .byte "N/C",$00
item_aprs:              .byte "APRS",$00
item_terminal:          .byte "Terminal",$00
item_line:              .byte "Line",$00
item_char:              .byte "Char",$00
item_cr:                .byte "CR",$00
item_lf:                .byte "LF",$00
item_crlf:              .byte "CR+LF",$00
item_atascii:           .byte "ATASCII",$00


serial_baud_label:      .byte "Baud:",$00
serial_data_label:      .byte "Data bits:",$00
serial_stop_label:      .byte "Stop bits:",$00
serial_parity_label:    .byte "Parity:",$00
serial_cts_label:       .byte "CTS:",$00
serial_dsr_label:       .byte "DSR:",$00
serial_dtr_label:       .byte "DTR:",$00
serial_rts_label:       .byte "RTS:",$00

session_protocol_label: .byte "Protocol:",$00

term_mode_label:        .byte "Mode:",$00
term_eol_label:         .byte "Line ending:",$00

form_hint:              .byte 'T'|$80,'A'|$80,'B'|$80," next field",$00

cfg_static_ptrs_lo:
  .byte <filename_label, <file_cfg_suffix, <form_hint
  .byte <session_protocol_label, <form_hint
  .byte <serial_baud_label, <serial_data_label, <serial_stop_label, <serial_parity_label, <serial_cts_label, <serial_dsr_label, <serial_dtr_label, <serial_rts_label, <form_hint
  .byte <term_mode_label, <term_eol_label, <form_hint
  .byte <aprs_callsign_label, <aprs_ssid_label, <aprs_digi_label, <form_hint
cfg_static_ptrs_hi:
  .byte >filename_label, >file_cfg_suffix, >form_hint
  .byte >session_protocol_label, >form_hint
  .byte >serial_baud_label, >serial_data_label, >serial_stop_label, >serial_parity_label, >serial_cts_label, >serial_dsr_label, >serial_dtr_label, >serial_rts_label, >form_hint
  .byte >term_mode_label, >term_eol_label, >form_hint
  .byte >aprs_callsign_label, >aprs_ssid_label, >aprs_digi_label, >form_hint
cfg_static_offs_lo:
  .byte <FILE_LABEL_OFFSET, <FILE_SUFFIX_OFFSET, <FILE_HINT_OFFSET
  .byte <SESSION_LABEL_OFFSET, <SESSION_HINT_OFFSET
  .byte <SERIAL_BAUD_LABEL_OFFSET, <SERIAL_DATA_LABEL_OFFSET, <SERIAL_STOP_LABEL_OFFSET, <SERIAL_PARITY_LABEL_OFFSET, <SERIAL_CTS_LABEL_OFFSET, <SERIAL_DSR_LABEL_OFFSET, <SERIAL_DTR_LABEL_OFFSET, <SERIAL_RTS_LABEL_OFFSET, <SERIAL_HINT_OFFSET
  .byte <TERM_MODE_LABEL_OFFSET, <TERM_EOL_LABEL_OFFSET, <TERM_HINT_OFFSET
  .byte <APRS_CALL_LABEL_OFFSET, <APRS_SSID_LABEL_OFFSET, <APRS_DIGI_LABEL_OFFSET, <APRS_HINT_OFFSET
cfg_static_offs_hi:
  .byte >FILE_LABEL_OFFSET, >FILE_SUFFIX_OFFSET, >FILE_HINT_OFFSET
  .byte >SESSION_LABEL_OFFSET, >SESSION_HINT_OFFSET
  .byte >SERIAL_BAUD_LABEL_OFFSET, >SERIAL_DATA_LABEL_OFFSET, >SERIAL_STOP_LABEL_OFFSET, >SERIAL_PARITY_LABEL_OFFSET, >SERIAL_CTS_LABEL_OFFSET, >SERIAL_DSR_LABEL_OFFSET, >SERIAL_DTR_LABEL_OFFSET, >SERIAL_RTS_LABEL_OFFSET, >SERIAL_HINT_OFFSET
  .byte >TERM_MODE_LABEL_OFFSET, >TERM_EOL_LABEL_OFFSET, >TERM_HINT_OFFSET
  .byte >APRS_CALL_LABEL_OFFSET, >APRS_SSID_LABEL_OFFSET, >APRS_DIGI_LABEL_OFFSET, >APRS_HINT_OFFSET

tab_static_first:       .byte 0, 3, 5, 14, 17
tab_static_count:       .byte 3, 2, 9, 3, 4
tab_form_ptrs_lo:       .byte <file_form, <session_form, <serial_form, <term_form, <aprs_form
tab_form_ptrs_hi:       .byte >file_form, >session_form, >serial_form, >term_form, >aprs_form
static_idx:             .byte 0
static_end:             .byte 0

top_banner:             .byte ' ','S'|$80,'E'|$80,'L'|$80,"tab-> "
                        .byte "          "
                        .byte 'E'|$80,'S'|$80,'C'|$80,"cancel "
                        .byte 'S'|$80,'T'|$80,'A'|$80,'R'|$80,'T'|$80,"start"
                        .byte $00
tabs_banner:            .byte " File|Session|Serial|Term|APRS",$00
tabs_highlight_starts:  .byte 1,6,14,21,26
tabs_highlight_ends:    .byte 5,13,20,25,30
num_tabs:               .byte 5
selected_tab:           .byte 0

file_form:              .tag Form
session_form:           .tag Form
serial_form:            .tag Form
aprs_form:              .tag Form
term_form:              .tag Form

cfg_draft_config:       .tag Cfg
cfg_saved_config:       .tag Cfg
cfg_config_flag:        .byte 0
cfg_select_fired:       .byte 0
cfg_start_fired:        .byte 0
started_once:           .byte 0

cfg_drive:              .byte 1
cfg_filespec:           .res 3+CFG_NAME_LEN+4+1; "Dn:"+name+".CFG"+EOL
cfg_lastfile_filespec:  .byte "D1:KISSTTY.LST", EOL
cfg_lastfile_data:      .res CFG_LASTFILE_LEN

cfg_filename_li:        .tag LineInput
cfg_filename_text:      .res CFG_NAME_LEN
cfg_callsign_li:        .tag LineInput
cfg_callsign_text:      .res APRS_CALLSIGN_LEN
cfg_ssid_li:            .tag LineInput
cfg_ssid_text:          .res APRS_SSID_LEN
cfg_digi_li:            .tag LineInput
cfg_digi_text:          .res APRS_DIGI_LEN
digi_count:             .byte 0
digi_write_offset:      .byte 0
digi_text_end:          .byte 0
digi_entry_start:       .byte 0
digi_entry_end:         .byte 0
digi_entry_sep:         .byte 0
aprs_callsign_label:    .byte "Callsign:",$00
aprs_ssid_label:        .byte "SSID:",$00
aprs_digi_label:        .byte "Digipeaters:",$00


filename_label:         .byte "File name:",$00
file_cfg_suffix:        .byte ".CFG",$00
btn_load:               .byte "[Load]",$00
btn_save:               .byte "[Save]",$00
btn_default:            .byte "[Load Defaults]",$00
msg_invalid_filename:   .byte "Invalid filename",$00
msg_saved:              .byte "Saved",$00
msg_save_failed:        .byte "Save failed",$00
msg_loaded:             .byte "Loaded",$00
msg_load_failed:        .byte "Load failed",$00

msg_start_first:        .byte "Press START to begin",$00
msg_invalid_callsign:   .byte "Invalid APRS callsign",$00
msg_invalid_ssid:       .byte "Invalid APRS ssid",$00
msg_invalid_digi:       .byte "Invalid APRS digipeaters",$00

