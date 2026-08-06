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

.segment "ZEROPAGE"
cfg_ptr_lo:                  .res 1
cfg_ptr_hi:                  .res 1

.segment "CODE"
.linecont +

.define MENU_MARGIN_TOP 1

CONFIG_VERSION    = 1
CFG_NAME_LEN      = 8
CFG_LASTFILE_LEN  = 1 + CFG_NAME_LEN


int_load_default_config:
  make_config cfg_draft_config, \
                  TERM_PROTOCOL::APRS, \
                  TERM_MODE::LINE, \
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

  OFFSET        .set (MENU_MARGIN_TOP+3)*SCREEN_WIDTH+2
  NUM_ITEMS     .set 8
  BORDER_WIDTH  .set 8
  make_menu baud_menu, baud_menu_header, \
            baud_menu_item_values, baud_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+3)*SCREEN_WIDTH+22
  NUM_ITEMS     .set 3
  BORDER_WIDTH  .set 10
  make_menu parity_menu, parity_menu_header, \
            parity_menu_item_values, parity_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+3)*SCREEN_WIDTH+12
  NUM_ITEMS     .set 4
  BORDER_WIDTH  .set 8
  make_menu data_menu, data_menu_header, \
            data_menu_item_values, data_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+9)*SCREEN_WIDTH+12
  NUM_ITEMS     .set 2
  BORDER_WIDTH  .set 8
  make_menu stop_menu, stop_menu_header, \
            stop_menu_item_values, stop_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+13)*SCREEN_WIDTH+2
  NUM_ITEMS     .set 2
  BORDER_WIDTH  .set 6
  make_menu cts_menu, cts_menu_header, \
            cts_menu_item_values, cts_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+13)*SCREEN_WIDTH+10
  NUM_ITEMS     .set 2
  BORDER_WIDTH  .set 6
  make_menu dsr_menu, dsr_menu_header, \
            dsr_menu_item_values, dsr_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+13)*SCREEN_WIDTH+18
  NUM_ITEMS     .set 3
  BORDER_WIDTH  .set 6
  make_menu dtr_menu, dtr_menu_header, \
            dtr_menu_item_values, dtr_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+13)*SCREEN_WIDTH+26
  NUM_ITEMS     .set 3
  BORDER_WIDTH  .set 6
  make_menu rts_menu, rts_menu_header, \
            rts_menu_item_values, rts_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+3)*SCREEN_WIDTH+1
  NUM_ITEMS     .set 2
  BORDER_WIDTH  .set 11
  make_menu protocol_menu, protocol_menu_header, \
            protocol_menu_item_values, protocol_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  jsr int_filetab_init
  jsr int_termtab_init
  jsr int_aprstab_init

  rts

int_termtab_init:
  lda #TERM_FIELD_FIRST
  sta term_form+Form::first
  lda #TERM_FIELD_COUNT
  sta term_form+Form::count
  lda #0
  sta term_form+Form::focus
  rts

int_draw_menu_items:
  ldy #Menu::scr_pos_ptr
  lda (cfg_ptr_lo),y
  clc
  adc #(SCREEN_WIDTH+2)
  sta g_temp_scr_ptr_lo
  iny
  lda (cfg_ptr_lo),y
  adc #0
  sta g_temp_scr_ptr_hi

  ldy #Menu::border_width
  lda (cfg_ptr_lo),y
  sta draw_menu_border_width

  ldy #Menu::num_items
  lda (cfg_ptr_lo),y
  sta menu_item_num_items

  ldy #Menu::items_labels_ptr
  lda (cfg_ptr_lo),y
  sta g_temp_data_ptr_lo
  iny
  lda (cfg_ptr_lo),y
  sta g_temp_data_ptr_hi

  ; menu labels are null terminated strings
  ; stored in a contiguous chunk of memory.
  ; each menu label can vary in length.
  ; we want to loop N rows, but the length
  ; of each label is unknown ahead of time.
  ; so we track what row we're on, but also
  ; where in the menu data we're at (menu_data_offset)
  ldx #0
  stx menu_data_offset
@menu_item_rows_loop:
  ldy #0
@menu_item_loop:
  sty draw_menu_tempy ; offset on current line
  ldy menu_data_offset 
  lda (g_temp_data_ptr_lo),y
  beq @menu_item_done ; null terminator
  jsr ut_atascii_to_icode
  ldy draw_menu_tempy
  sta (g_temp_scr_ptr_lo),y
  iny
  inc menu_data_offset 
  jmp @menu_item_loop
@menu_item_done:
  inc menu_data_offset 
  lda g_temp_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  lda g_temp_scr_ptr_hi
  adc #0
  sta g_temp_scr_ptr_hi

  inx
  cpx menu_item_num_items
  beq @menu_item_rows_loop_done
  bne @menu_item_rows_loop
@menu_item_rows_loop_done:
  rts

; draws the menu border and header
; note: assumes <256 chars worth of menu item data
;
; inputs:
;   cfg_ptr_lo/HI   - pointer to menu struct
;   menu_item_value - initial value
int_draw_menu_border:
  ldy #Menu::scr_pos_ptr
  lda (cfg_ptr_lo),y
  sta g_temp_scr_ptr_lo
  iny
  lda (cfg_ptr_lo),y
  sta g_temp_scr_ptr_hi

  ldy #Menu::border_width
  lda (cfg_ptr_lo),y
  sta draw_menu_border_width

  ldy #Menu::num_items
  lda (cfg_ptr_lo),y
  sta menu_item_num_items
@top_border:
  ldy draw_menu_border_width
  lda #ICODE_UPPER_RIGHT_CORNER
  sta (g_temp_scr_ptr_lo),y
  lda #ICODE_HORIZONTAL_BAR
@top_loop:
  dey
  sta (g_temp_scr_ptr_lo),y
  bne @top_loop
  lda #ICODE_UPPER_LEFT_CORNER
  sta (g_temp_scr_ptr_lo),y
@header:
  ldy #Menu::header_ptr
  lda (cfg_ptr_lo),y
  sta g_temp_data_ptr_lo
  iny
  lda (cfg_ptr_lo),y
  sta g_temp_data_ptr_hi

  ldy #0
@header_loop:
  lda (g_temp_data_ptr_lo),y
  beq @header_loop_done
  jsr ut_atascii_to_icode
  iny
  sta (g_temp_scr_ptr_lo),y
  jmp @header_loop
@header_loop_done:
  ; move to next row for vertical borders
  lda g_temp_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  lda g_temp_scr_ptr_hi
  adc #0
  sta g_temp_scr_ptr_hi
  
  ldx menu_item_num_items
@menu_item_rows_loop:
  lda #ICODE_VERTICAL_BAR
  ldy #0
  sta (g_temp_scr_ptr_lo),y
  ldy draw_menu_border_width 
  sta (g_temp_scr_ptr_lo),y

  dex

  lda g_temp_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  lda g_temp_scr_ptr_hi
  adc #0
  sta g_temp_scr_ptr_hi

  cpx #0
  bne @menu_item_rows_loop

@btm_border:
  ldy draw_menu_border_width
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
  beq @top_banner_done
  eor #$80
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  iny
  jmp @top_banner_loop
@top_banner_done:
  jsr int_draw_tabs
  rts

int_refresh_file_tab:
  jsr int_filetab_clear_status
  lda #<file_form
  sta CMDDATA0
  lda #>file_form
  sta CMDDATA1
  jsr fm_set_context
  jsr fm_draw_all
  rts

int_refresh_session_tab:
  refresh_menu protocol_menu, cfg_draft_config+Cfg::session+CfgSession::protocol
  rts

int_refresh_serial_tab:
  refresh_menu baud_menu,     cfg_draft_config+Cfg::serial+CfgSerial::baud
  refresh_menu parity_menu,   cfg_draft_config+Cfg::serial+CfgSerial::parity
  refresh_menu data_menu,     cfg_draft_config+Cfg::serial+CfgSerial::data_bits
  refresh_menu stop_menu,     cfg_draft_config+Cfg::serial+CfgSerial::stop_bits
  refresh_menu cts_menu,      cfg_draft_config+Cfg::serial+CfgSerial::cts
  refresh_menu dsr_menu,      cfg_draft_config+Cfg::serial+CfgSerial::dsr
  refresh_menu dtr_menu,      cfg_draft_config+Cfg::serial+CfgSerial::dtr
  refresh_menu rts_menu,      cfg_draft_config+Cfg::serial+CfgSerial::rets
  rts

int_refresh_term_tab:
  lda #<term_form
  sta CMDDATA0
  lda #>term_form
  sta CMDDATA1
  jsr fm_set_context
  jsr fm_draw_all
  rts

int_refresh_aprs_tab:
  lda #APRS_FOCUS_CALLSIGN
  sta aprstab_focus

  lda #<cfg_callsign_li
  sta CMDDATA0
  lda #>cfg_callsign_li
  sta CMDDATA1
  jsr li_set_context
  jsr li_repaint

  lda #<cfg_ssid_li
  sta CMDDATA0
  lda #>cfg_ssid_li
  sta CMDDATA1
  jsr li_set_context
  jsr li_repaint

  lda #<cfg_digi_li
  sta CMDDATA0
  lda #>cfg_digi_li
  sta CMDDATA1
  jsr li_set_context
  jsr li_repaint

  jsr int_aprstab_draw_focus
  rts

; redraws the menu items, sets the selected by value,
; and highlights the selected menu item.
int_refresh_menus:
  lda selected_tab
  cmp #1
  beq @session
  cmp #2
  beq @serial
  cmp #3
  beq @term
  cmp #4
  beq @aprs
  ; file menu
  jsr int_refresh_file_tab
  jmp @done
@session:
  jsr int_refresh_session_tab
  jmp @done
@serial:
  jsr int_refresh_serial_tab
  jmp @done
@term:
  jsr int_refresh_term_tab
  jmp @done
@aprs:
  jsr int_refresh_aprs_tab
@done:
  rts

START_STATUS_OFFSET   = 22*SCREEN_WIDTH+1
START_STATUS_WIDTH    = 36

; shows the message in CMDDATA0/1 on the start status line, clearing first
; inputs:
;   CMDDATA0/1 - ptr to the message
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
FILE_BTN_LOAD_OFFSET   = 8*SCREEN_WIDTH+31
FILE_BTN_SAVE_OFFSET   = 9*SCREEN_WIDTH+31
FILE_BTN_DEF_OFFSET    = 11*SCREEN_WIDTH+22
FILE_HINT_OFFSET       = 19*SCREEN_WIDTH+2
FILE_STATUS_OFFSET     = 13*SCREEN_WIDTH+2
FILE_STATUS_WIDTH      = 36

FILE_FIELD_FIRST       = 0
FILE_FIELD_COUNT       = 4

FILE_ACTION_LOAD       = 1
FILE_ACTION_SAVE       = 2
FILE_ACTION_DEFAULT    = 3

APRS_CALL_LABEL_OFFSET = 5*SCREEN_WIDTH+2
APRS_CALL_FIELD_OFFSET = 5*SCREEN_WIDTH+15
APRS_SSID_LABEL_OFFSET = 7*SCREEN_WIDTH+2
APRS_SSID_FIELD_OFFSET = 7*SCREEN_WIDTH+15
APRS_DIGI_LABEL_OFFSET = 9*SCREEN_WIDTH+2
APRS_DIGI_FIELD_OFFSET = 9*SCREEN_WIDTH+15

APRS_FOCUS_CALLSIGN    = 0
APRS_FOCUS_FIRST       = 0
APRS_FOCUS_SSID        = 1
APRS_FOCUS_DIGI        = 2
APRS_FOCUS_LAST        = 2
APRS_FOCUS_COUNT       = 3

TERM_MODE_LABEL_OFFSET = 5*SCREEN_WIDTH+2
TERM_MODE_FIELD_OFFSET = 5*SCREEN_WIDTH+15
TERM_EOL_LABEL_OFFSET  = 7*SCREEN_WIDTH+2
TERM_EOL_FIELD_OFFSET  = 7*SCREEN_WIDTH+15
TERM_LF_LABEL_OFFSET   = 9*SCREEN_WIDTH+2
TERM_LF_FIELD_OFFSET   = 9*SCREEN_WIDTH+15
TERM_HINT_OFFSET       = 19*SCREEN_WIDTH+2

TERM_FIELD_FIRST       = 4
TERM_FIELD_COUNT       = 3
TERM_STATIC_COUNT      = 4

int_draw_menu_borders_file_tab:
  lda #<filename_label
  sta CMDDATA0
  lda #>filename_label
  sta CMDDATA1
  lda #<FILE_LABEL_OFFSET
  sta CMDDATA2
  lda #>FILE_LABEL_OFFSET
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str

  lda #<file_cfg_suffix
  sta CMDDATA0
  lda #>file_cfg_suffix
  sta CMDDATA1
  lda #<FILE_SUFFIX_OFFSET
  sta CMDDATA2
  lda #>FILE_SUFFIX_OFFSET
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str

  lda #<form_hint
  sta CMDDATA0
  lda #>form_hint
  sta CMDDATA1
  lda #<FILE_HINT_OFFSET
  sta CMDDATA2
  lda #>FILE_HINT_OFFSET
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str
  rts

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
  lda #APRS_FOCUS_CALLSIGN
  sta aprstab_focus

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
  lda #24 ; fill to right of screen
  sta cfg_digi_li+LineInput::num_visible
  lda #APRS_DIGI_LEN
  sta cfg_digi_li+LineInput::data_size

  rts

; points the line input at the currently focused field
int_aprstab_input_set_context:
  ldx aprstab_focus
  lda cfg_aprs_li_ptrs_lo,x
  sta CMDDATA0
  lda cfg_aprs_li_ptrs_hi,x
  sta CMDDATA1
  jsr li_set_context
  rts

int_aprstab_draw_focus:
  ldx #APRS_FOCUS_FIRST
@hide_loop:
  lda cfg_aprs_li_ptrs_lo,x
  sta CMDDATA0
  lda cfg_aprs_li_ptrs_hi,x
  sta CMDDATA1
  jsr li_set_context
  jsr li_hide_cursor
  cpx #APRS_FOCUS_LAST
  beq @show
  inx
  bne @hide_loop
@show:
  jsr int_aprstab_input_set_context
  jsr li_show_cursor
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

int_draw_menu_borders_session_tab:
  draw_menu_border protocol_menu
  rts

int_draw_menu_borders_serial_tab:
  draw_menu_border baud_menu
  draw_menu_border parity_menu
  draw_menu_border data_menu
  draw_menu_border stop_menu
  draw_menu_border cts_menu
  draw_menu_border dsr_menu
  draw_menu_border dtr_menu
  draw_menu_border rts_menu
  rts

int_draw_menu_borders_term_tab:
  ldx #0
@static_loop:
  stx term_static_idx
  lda term_static_ptrs_lo,x
  sta CMDDATA0
  lda term_static_ptrs_hi,x
  sta CMDDATA1
  lda term_static_offs_lo,x
  sta CMDDATA2
  lda term_static_offs_hi,x
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str
  ldx term_static_idx
  inx
  cpx #TERM_STATIC_COUNT
  bne @static_loop
  rts

int_draw_menu_borders_aprs_tab:
  lda #<aprs_callsign_label
  sta CMDDATA0
  lda #>aprs_callsign_label
  sta CMDDATA1
  lda #<APRS_CALL_LABEL_OFFSET
  sta CMDDATA2
  lda #>APRS_CALL_LABEL_OFFSET
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str

  lda #<aprs_ssid_label
  sta CMDDATA0
  lda #>aprs_ssid_label
  sta CMDDATA1
  lda #<APRS_SSID_LABEL_OFFSET
  sta CMDDATA2
  lda #>APRS_SSID_LABEL_OFFSET
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str

  lda #<aprs_digi_label
  sta CMDDATA0
  lda #>aprs_digi_label
  sta CMDDATA1
  lda #<APRS_DIGI_LABEL_OFFSET
  sta CMDDATA2
  lda #>APRS_DIGI_LABEL_OFFSET
  sta CMDDATA3
  lda #0
  sta CMDDATA4
  jsr scr_draw_str

  rts

; draws the chroma around the borders and the header
int_draw_menu_borders:
  lda selected_tab
  cmp #1
  beq @session
  cmp #2
  beq @serial
  cmp #3
  beq @term
  cmp #4
  beq @aprs
  ; file menu
  jsr int_draw_menu_borders_file_tab
  jmp @done
@session:
  jsr int_draw_menu_borders_session_tab
  jmp @done
@serial:
  jsr int_draw_menu_borders_serial_tab
  jmp @done
@term:
  jsr int_draw_menu_borders_term_tab
  jmp @done
@aprs:
  jsr int_draw_menu_borders_aprs_tab
@done:
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

  jsr int_draw_menu_borders
  jsr int_refresh_menus
  jsr int_draw_main

  rts

; inputs:
;   cfg_ptr_lo/HI   - pointer to menu struct
int_highlight_selected_menu_item:
  ldy #Menu::scr_pos_ptr
  lda (cfg_ptr_lo),y
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  iny
  lda (cfg_ptr_lo),y
  adc #0
  sta g_temp_scr_ptr_hi

  ldy #Menu::border_width
  lda (cfg_ptr_lo),y
  sta menu_item_border_width

  ldy #Menu::num_items
  lda (cfg_ptr_lo),y
  sta menu_item_num_items

  ldy #Menu::selected_index
  lda (cfg_ptr_lo),y
  sta menu_item_index

  ldx #0
@menu_item_rows_loop:
  cpx menu_item_index
  beq @menu_item_match

  ; if here, this is not the row, but let's
  ; make sure we de-highlight it if needed
  ldy #1
  lda (g_temp_scr_ptr_lo),y
  and #%10000000 ; check if msb set on first char
  beq @menu_item_row_done ; was not highlighted
@dehighlight_loop:
  lda (g_temp_scr_ptr_lo),y
  and #%01111111
  sta (g_temp_scr_ptr_lo),y
  iny
  cpy menu_item_border_width
  bne @dehighlight_loop
  beq @menu_item_row_done
@menu_item_match:
  ldy #1
@highlight_loop:
  lda (g_temp_scr_ptr_lo),y
  ora #%10000000
  sta (g_temp_scr_ptr_lo),y
  iny
  cpy menu_item_border_width
  bne @highlight_loop
@menu_item_row_done:
  inx
  cpx menu_item_num_items
  beq @done
  lda g_temp_scr_ptr_lo
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  lda g_temp_scr_ptr_hi
  adc #0
  sta g_temp_scr_ptr_hi
  jmp @menu_item_rows_loop
@done:
  rts

; Finds menu item with the provided value and
; sets the selected index.
;
; inputs:
;   cfg_ptr_lo/hi       - pointer to the menu
;   menu_item_value     - value to search for
int_select_menu_item_by_value:
  ldy #Menu::num_items
  lda (cfg_ptr_lo),y
  sta menu_item_num_items

  ldy #Menu::items_values_ptr
  lda (cfg_ptr_lo),y
  sta g_temp_data_ptr_lo
  iny
  lda (cfg_ptr_lo),y
  sta g_temp_data_ptr_hi
  
  ldy #0
@loop:
  lda (g_temp_data_ptr_lo),y
  cmp menu_item_value
  beq @found
  iny
  cpy menu_item_num_items
  bne @loop
  ldy #0
@found:
  tya
  ldy #Menu::selected_index
  sta (cfg_ptr_lo),y
@done:
  rts

; Selects the index after the current index (with wrapping)
; for this menu. And highlights the new item.
;
; inputs:
;   cfg_ptr_lo/HI - pointer to menu
int_select_next_menu_item:
  ldy #Menu::num_items
  lda (cfg_ptr_lo),y
  sta menu_item_num_items

  ldy #Menu::selected_index
  lda (cfg_ptr_lo),y
  clc
  adc #1
  cmp menu_item_num_items
  bcc @nowrap
  lda #0
@nowrap:
  sta menu_item_index
  ldy #Menu::selected_index
  sta (cfg_ptr_lo),y
  jsr int_highlight_selected_menu_item

  rts

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

int_cmd_baud:
  handle_menu_next baud_menu
  ldy baud_menu+Menu::selected_index
  lda baud_menu_item_values,y
  sta cfg_draft_config+Cfg::serial+CfgSerial::baud
  rts

int_cmd_parity:
  handle_menu_next parity_menu
  ldy parity_menu+Menu::selected_index
  lda parity_menu_item_values,y
  sta cfg_draft_config+Cfg::serial+CfgSerial::parity
  rts

int_cmd_data:
  handle_menu_next data_menu
  ldy data_menu+Menu::selected_index
  lda data_menu_item_values,y
  sta cfg_draft_config+Cfg::serial+CfgSerial::data_bits
  rts

int_cmd_stop:
  handle_menu_next stop_menu
  ldy stop_menu+Menu::selected_index
  lda stop_menu_item_values,y
  sta cfg_draft_config+Cfg::serial+CfgSerial::stop_bits
  rts

int_cmd_cts:
  handle_menu_next cts_menu
  ldy cts_menu+Menu::selected_index
  lda cts_menu_item_values,y
  sta cfg_draft_config+Cfg::serial+CfgSerial::cts
  rts

int_cmd_dsr:
  handle_menu_next dsr_menu
  ldy dsr_menu+Menu::selected_index
  lda dsr_menu_item_values,y
  sta cfg_draft_config+Cfg::serial+CfgSerial::dsr
  rts

int_cmd_dtr:
  handle_menu_next dtr_menu
  ldy dtr_menu+Menu::selected_index
  lda dtr_menu_item_values,y
  sta cfg_draft_config+Cfg::serial+CfgSerial::dtr
  rts

int_cmd_rets:
  handle_menu_next rts_menu
  ldy rts_menu+Menu::selected_index
  lda rts_menu_item_values,y
  sta cfg_draft_config+Cfg::serial+CfgSerial::rets
  rts

int_cmd_protocol:
  handle_menu_next protocol_menu
  ldy protocol_menu+Menu::selected_index
  lda protocol_menu_item_values,y
  sta cfg_draft_config+Cfg::session+CfgSession::protocol
  rts

int_cmd_start:
  jsr int_aprstab_form_to_config
  bcs @show_error

  lda cfg_draft_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::APRS
  bne @start

  ; only allow line mode in aprs
  lda #TERM_MODE::LINE
  sta cfg_draft_config+Cfg::term+CfgTerm::mode

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
  jsr int_draw_menu_borders
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

int_filetab_handle_kbd:
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

int_session_handle_kbd:
  lda g_kbdcode_raw
  cmp #$32
  beq @protocol
  cmp #$1c
  beq @escape
  bne @done
@protocol:
  jsr int_cmd_protocol
  jmp @done
@escape:
  jsr int_cmd_cancel
@done:
  rts

int_serial_handle_kbd:
  lda g_kbdcode_raw
  cmp #$15
  beq @baud
  cmp #$0a
  beq @parity
  cmp #$3a
  beq @data
  cmp #$08
  beq @stop
  cmp #$12
  beq @cts
  cmp #$3e
  beq @dsr
  cmp #$2d
  beq @dtr
  cmp #$28
  beq @rets
  cmp #$1c
  beq @escape
  bne @done
@baud:
  jsr int_cmd_baud
  jmp @done
@parity:
  jsr int_cmd_parity
  jmp @done
@data:
  jsr int_cmd_data
  jmp @done
@stop:
  jsr int_cmd_stop
  jmp @done
@cts:
  jsr int_cmd_cts
  jmp @done
@dsr:
  jsr int_cmd_dsr
  jmp @done
@dtr:
  jsr int_cmd_dtr
  jmp @done
@rets:
  jsr int_cmd_rets
  jmp @done
@escape:
  jsr int_cmd_cancel
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

int_aprstab_handle_kbd:
  lda g_kbdcode_raw
  cmp #KEY_ESC
  beq @escape
  cmp #KEY_TAB
  beq @focus_next
  cmp #$86 ; ctrl+left arrow
  beq @cursor_left
  cmp #$87 ; ctrl+right arrow
  beq @cursor_right
  cmp #KEY_DELETE ; backspace
  beq @backspace
  cmp #$b4 ; ctrl+delete
  beq @char_delete
  cmp #$b7 ; ctrl+insert
  beq @char_insert
  jmp @typechar
@escape:
  jsr int_cmd_cancel
  jmp @done
@focus_next:
  ldx aprstab_focus
  inx
  cpx #APRS_FOCUS_COUNT
  bne @focus_store
  ldx #APRS_FOCUS_CALLSIGN
@focus_store:
  stx aprstab_focus
  jsr int_aprstab_draw_focus
  jmp @done
@cursor_left:
  jsr int_aprstab_input_set_context
  jsr li_move_cursor_left
  jmp @done
@cursor_right:
  jsr int_aprstab_input_set_context
  jsr li_move_cursor_right
  jmp @done
@backspace:
  jsr int_aprstab_input_set_context
  jsr li_backspace
  jmp @done
@char_delete:
  jsr int_aprstab_input_set_context
  jsr li_char_delete
  jmp @done
@char_insert:
  jsr int_aprstab_input_set_context
  jsr li_char_insert
  jmp @done
@typechar:
  lda g_kbdcode_atascii
  cmp #' '
  beq @type
  cmp #'-'
  beq @type
  cmp #','
  beq @type
  jsr ut_is_alphanumeric
  bcs @done
@type:
  jsr int_aprstab_input_set_context
  lda g_kbdcode_atascii
  sta CMDDATA0
  jsr li_type_char
@done:
  rts

int_handle_kbd:
  lda g_kbd_key_pressed
  bne @valid_key
  jmp @done
@valid_key:
  lda selected_tab
  cmp #1
  beq @session
  cmp #2
  beq @serial
  cmp #3
  beq @term
  cmp #4
  beq @aprs
  jsr int_filetab_handle_kbd
  jmp @done
@session:
  jsr int_session_handle_kbd
  jmp @done
@serial:
  jsr int_serial_handle_kbd
  jmp @done
@term:
  jsr int_form_handle_kbd
  jmp @done
@aprs:
  jsr int_aprstab_handle_kbd
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

baud_menu:                     .tag Menu
baud_menu_header:              .byte 'B'|$80,"aud",$00
baud_menu_item_values:
  .byte RS232_BAUD::B50
  .byte RS232_BAUD::B300
  .byte RS232_BAUD::B600
  .byte RS232_BAUD::B1200
  .byte RS232_BAUD::B2400
  .byte RS232_BAUD::B4800
  .byte RS232_BAUD::B9600
  .byte RS232_BAUD::B19200
baud_menu_item_values_end:
baud_menu_item_labels:
baud_menu_item_label_50:       .byte "50",$00
baud_menu_item_label_300:      .byte "300",$00
baud_menu_item_label_600:      .byte "600",$00
baud_menu_item_label_1200:     .byte "1200",$00
baud_menu_item_label_2400:     .byte "2400",$00
baud_menu_item_label_4800:     .byte "4800",$00
baud_menu_item_label_9600:     .byte "9600",$00
baud_menu_item_label_19200:    .byte "19200",$00

data_menu:                     .tag Menu
data_menu_header:              .byte 'D'|$80,"ata",$00
data_menu_item_values:
  .byte RS232_WORDSIZE::N5
  .byte RS232_WORDSIZE::N6
  .byte RS232_WORDSIZE::N7
  .byte RS232_WORDSIZE::N8
data_menu_item_values_end:
data_menu_item_labels:
data_menu_item_label_word5:    .byte "5 bit",$00
data_menu_item_label_word6:    .byte "6 bit",$00
data_menu_item_label_word7:    .byte "7 bit",$00
data_menu_item_label_word8:    .byte "8 bit",$00

stop_menu:                     .tag Menu
stop_menu_header:              .byte "St",'O'|$80,"p",$00
stop_menu_item_values:
  .byte RS232_STOPBITS::N1
  .byte RS232_STOPBITS::N2
stop_menu_item_values_end:
stop_menu_item_labels:
stop_menu_item_label_word1:    .byte "1 bit",$00
stop_menu_item_label_word2:    .byte "2 bit",$00

cts_menu:                      .tag Menu
cts_menu_header:               .byte 'C'|$80,"TS",$00
cts_menu_item_values:
  .byte RS232_CTS::OFF
  .byte RS232_CTS::ON
cts_menu_item_values_end:
cts_menu_item_labels:
cts_menu_item_label_off:       .byte "OFF",$00
cts_menu_item_label_on:        .byte "ON",$00

dsr_menu:                      .tag Menu
dsr_menu_header:               .byte "D",'S'|$80,"R",$00
dsr_menu_item_values:
  .byte RS232_DSR::OFF
  .byte RS232_DSR::ON
dsr_menu_item_values_end:
dsr_menu_item_labels:
dsr_menu_item_label_off:       .byte "OFF",$00
dsr_menu_item_label_on:        .byte "ON",$00

dtr_menu:                      .tag Menu
dtr_menu_header:               .byte "D",'T'|$80,"R",$00
dtr_menu_item_values:
  .byte RS232_DTR::NO_CHANGE
  .byte RS232_DTR::OFF
  .byte RS232_DTR::ON
dtr_menu_item_values_end:
dtr_menu_item_labels:
dtr_menu_item_label_no_chage:  .byte "N/C",$00
dtr_menu_item_label_off:       .byte "OFF",$00
dtr_menu_item_label_on:        .byte "ON",$00

rts_menu:                      .tag Menu
rts_menu_header:               .byte 'R'|$80,"TS",$00
rts_menu_item_values:
  .byte RS232_RTS::NO_CHANGE
  .byte RS232_RTS::OFF
  .byte RS232_RTS::ON
rts_menu_item_values_end:
rts_menu_item_labels:
rts_menu_item_label_no_change: .byte "N/C",$00
rts_menu_item_label_off:       .byte "OFF",$00
rts_menu_item_label_on:        .byte "ON",$00

parity_menu:                   .tag Menu
parity_menu_header:            .byte 'P'|$80,"arity",$00
parity_menu_item_values:
  .byte RS232_PARITY::NONE
  .byte RS232_PARITY::EVEN
  .byte RS232_PARITY::ODD
parity_menu_item_values_end:
parity_menu_item_labels:
parity_menu_item_label0:       .byte "None",$00
parity_menu_item_label1:       .byte "Even",$00
parity_menu_item_label2:       .byte "Odd",$00

protocol_menu:                 .tag Menu
protocol_menu_header:          .byte '0'|$80,"Protocol",$00
protocol_menu_item_values:
  .byte TERM_PROTOCOL::APRS
  .byte TERM_PROTOCOL::TERM
protocol_menu_item_values_end:
protocol_menu_item_labels:
protocol_menu_item_label_aprs: .byte "APRS",$00
protocol_menu_item_label_term: .byte "Terminal",$00

file_form:              .tag Form
term_form:              .tag Form

; the form field table for all tabs
cfg_field_kind:
  .byte FIELD_TEXT, FIELD_BUTTON, FIELD_BUTTON, FIELD_BUTTON
  .byte FIELD_SELECT, FIELD_SELECT, FIELD_SELECT
cfg_field_scr_lo:
  .byte <FILE_FIELD_OFFSET, <FILE_BTN_LOAD_OFFSET, <FILE_BTN_SAVE_OFFSET, <FILE_BTN_DEF_OFFSET
  .byte <TERM_MODE_FIELD_OFFSET, <TERM_EOL_FIELD_OFFSET, <TERM_LF_FIELD_OFFSET
cfg_field_scr_hi:
  .byte >FILE_FIELD_OFFSET, >FILE_BTN_LOAD_OFFSET, >FILE_BTN_SAVE_OFFSET, >FILE_BTN_DEF_OFFSET
  .byte >TERM_MODE_FIELD_OFFSET, >TERM_EOL_FIELD_OFFSET, >TERM_LF_FIELD_OFFSET
cfg_field_width:
  .byte CFG_NAME_LEN, 6, 6, 15
  .byte 7, 7, 7
cfg_field_data_lo:
  .byte <cfg_filename_li, <btn_load, <btn_save, <btn_default
  .byte <(cfg_draft_config+Cfg::term+CfgTerm::mode),<(cfg_draft_config+Cfg::term+CfgTerm::line_ending),<(cfg_draft_config+Cfg::serial+CfgSerial::line_feed)
cfg_field_data_hi:
  .byte >cfg_filename_li, >btn_load, >btn_save, >btn_default
  .byte >(cfg_draft_config+Cfg::term+CfgTerm::mode),>(cfg_draft_config+Cfg::term+CfgTerm::line_ending),>(cfg_draft_config+Cfg::serial+CfgSerial::line_feed)
cfg_field_values_lo:
  .byte 0, 0, 0, 0
  .byte <term_mode_field_values, <term_eol_field_values, <term_lf_field_values
cfg_field_values_hi:
  .byte 0, 0, 0, 0
  .byte >term_mode_field_values, >term_eol_field_values, >term_lf_field_values
cfg_field_labels_lo:
  .byte 0, 0, 0, 0
  .byte <term_mode_field_labels_lo, <term_eol_field_labels_lo, <term_lf_field_labels_lo
cfg_field_labels_hi:
  .byte 0, 0, 0, 0
  .byte >term_mode_field_labels_lo, >term_eol_field_labels_lo, >term_lf_field_labels_lo
cfg_field_arg0:
  .byte CHAR_ALNUM|CHAR_SPACE, FILE_ACTION_LOAD, FILE_ACTION_SAVE, FILE_ACTION_DEFAULT
  .byte 2, 4, 2
cfg_field_arg1:
  .byte INPUT_UPPER, 0, 0, 0
  .byte 0, 0, 0

term_mode_field_values:
  .byte TERM_MODE::LINE, TERM_MODE::CHAR
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

term_lf_field_values:
  .byte RS232_LINE_FEED::NO_APPEND_LF, RS232_LINE_FEED::APPEND_LF
term_lf_field_labels_lo:
  .byte <item_no, <item_yes
term_lf_field_labels_hi:
  .byte >item_no, >item_yes

item_line:              .byte "Line",$00
item_char:              .byte "Char",$00
item_cr:                .byte "CR",$00
item_lf:                .byte "LF",$00
item_crlf:              .byte "CR+LF",$00
item_atascii:           .byte "ATASCII",$00
item_no:                .byte "No",$00
item_yes:               .byte "Yes",$00

term_mode_label:        .byte "Mode:",$00
term_eol_label:         .byte "Line ending:",$00
term_lf_label:          .byte "Append LF:",$00
form_hint:              .byte 'T'|$80,'A'|$80,'B'|$80," next field",$00
term_static_idx:        .byte 0
term_static_ptrs_lo:    .byte <term_mode_label, <term_eol_label, <term_lf_label, <form_hint
term_static_ptrs_hi:    .byte >term_mode_label, >term_eol_label, >term_lf_label, >form_hint
term_static_offs_lo:    .byte <TERM_MODE_LABEL_OFFSET, <TERM_EOL_LABEL_OFFSET, <TERM_LF_LABEL_OFFSET, <TERM_HINT_OFFSET
term_static_offs_hi:    .byte >TERM_MODE_LABEL_OFFSET, >TERM_EOL_LABEL_OFFSET, >TERM_LF_LABEL_OFFSET, >TERM_HINT_OFFSET

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
draw_menu_tempy:        .byte 0
draw_menu_border_width: .byte 0
draw_menu_end_column:   .byte 0
draw_menu_data_length:  .byte 0

menu_data_offset:       .byte 0
menu_item_index:        .byte 0
menu_item_value:        .byte 0
menu_item_num_items:    .byte 0
menu_item_border_width: .byte 0

highlight_border_width: .byte 0

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
aprstab_focus:          .byte 0
aprs_callsign_label:    .byte "Callsign:",$00
aprs_ssid_label:        .byte "SSID:",$00
aprs_digi_label:        .byte "Digipeaters:",$00

cfg_aprs_li_ptrs_lo:    .byte <cfg_callsign_li, <cfg_ssid_li, <cfg_digi_li
cfg_aprs_li_ptrs_hi:    .byte >cfg_callsign_li, >cfg_ssid_li, >cfg_digi_li

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

