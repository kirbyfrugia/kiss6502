.setcpu "6502"

.include "atari.inc" ; /usr/share/cc65/asminc/atari.inc
.include "config.inc"
.include "file.inc"
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
  sta cfg_draft_config+Cfg::aprs+CfgAprs::callsign,x
  dex
  bpl @callsign_loop
  lda #0
  sta cfg_draft_config+Cfg::aprs+CfgAprs::ssid
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

  OFFSET        .set (MENU_MARGIN_TOP+8)*SCREEN_WIDTH + 22
  NUM_ITEMS     .set 3
  BORDER_WIDTH  .set 10
  make_menu mode_menu, mode_menu_header, \
            mode_menu_item_values, mode_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  jsr int_filetab_init
  jsr int_aprstab_init

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
  lda #FILE_FOCUS_NAME
  sta filetab_focus
  jsr int_filetab_clear_status
  jsr int_filetab_file_input_set_context
  jsr li_repaint
  jsr int_filetab_draw_focus
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
  refresh_menu mode_menu,     cfg_draft_config+Cfg::serial+CfgSerial::mode
  rts

int_refresh_aprs_tab:
  jsr int_aprstab_ssid_to_text

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

FILE_LABEL_OFFSET    = 5*SCREEN_WIDTH+2
FILE_FIELD_OFFSET    = 5*SCREEN_WIDTH+13
FILE_SUFFIX_OFFSET   = FILE_FIELD_OFFSET+CFG_NAME_LEN
FILE_BTN_LOAD_OFFSET = 8*SCREEN_WIDTH+31
FILE_BTN_SAVE_OFFSET = 9*SCREEN_WIDTH+31
FILE_BTN_DEF_OFFSET  = 11*SCREEN_WIDTH+22
FILE_STATUS_OFFSET   = 13*SCREEN_WIDTH+2
FILE_STATUS_WIDTH    = 36

FILE_FOCUS_NAME      = 0
FILE_FOCUS_BTN_START = 1
FILE_FOCUS_LOAD      = 1
FILE_FOCUS_SAVE      = 2
FILE_FOCUS_DEFAULT   = 3
FILE_FOCUS_BTN_END   = 3
FILE_FOCUS_COUNT     = 4

APRS_CALL_LABEL_OFFSET = 5*SCREEN_WIDTH+2
APRS_CALL_FIELD_OFFSET = 5*SCREEN_WIDTH+13
APRS_SSID_LABEL_OFFSET = 7*SCREEN_WIDTH+2
APRS_SSID_FIELD_OFFSET = 7*SCREEN_WIDTH+13

APRS_FOCUS_CALLSIGN  = 0
APRS_FOCUS_FIRST     = 0
APRS_FOCUS_SSID      = 1
APRS_FOCUS_LAST      = 1
APRS_FOCUS_COUNT     = 2

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
  rts

int_filetab_init:
  jsr int_load_lastfile

  lda #FILE_FOCUS_NAME
  sta filetab_focus

  lda #0
  sta cfg_li+LineInput::scr_cursor
  sta cfg_li+LineInput::data_cursor
  sta cfg_li+LineInput::first_visible

  lda #<FILE_FIELD_OFFSET
  clc
  adc SCR_PTR_LO
  sta cfg_li+LineInput::scr_ptr
  lda #>FILE_FIELD_OFFSET
  adc SCR_PTR_HI
  sta cfg_li+LineInput::scr_ptr+1

  lda #<cfg_basename
  sta cfg_li+LineInput::data_ptr
  lda #>cfg_basename
  sta cfg_li+LineInput::data_ptr+1
  lda #CFG_NAME_LEN
  sta cfg_li+LineInput::num_visible
  lda #CFG_NAME_LEN
  sta cfg_li+LineInput::data_len
  rts

int_filetab_file_input_set_context:
  lda #<cfg_li
  sta CMDDATA0
  lda #>cfg_li
  sta CMDDATA1
  jsr li_set_context
  rts

int_filetab_save_file:
  jsr int_filetab_filename_valid
  bcs @invalid
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
@invalid:
  jsr int_filetab_show_invalid
  rts

int_filetab_load:
  jsr int_filetab_filename_valid
  bcs @invalid
  jsr cfg_load_config
  bcs @failed
  jsr int_aprstab_ssid_to_text
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
;   carry - set if invalid, clear if valid
;         - e.g. space in the middle of the file name
; modifies:
;   CMDDATA0/1/2
;   a,y
int_filetab_filename_valid:
  lda #<cfg_basename
  sta CMDDATA0
  lda #>cfg_basename
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

; draws the buttons for the file tab
; modifies:
;   a,x,y
;   CMDDATA0-4
int_filetab_draw_buttons:
  ldx #0
@loop:
  stx file_btn_idx
  lda file_btn_ptrs_lo,x
  sta CMDDATA0
  lda file_btn_ptrs_hi,x
  sta CMDDATA1
  lda file_btn_offs_lo,x
  sta CMDDATA2
  lda file_btn_offs_hi,x
  sta CMDDATA3

  lda #0
  sta CMDDATA4
  txa
  clc
  adc #FILE_FOCUS_BTN_START
  cmp filetab_focus
  bne @nofocus
  lda #$80
  sta CMDDATA4
@nofocus:
  jsr scr_draw_str
  ldx file_btn_idx
  inx
  cpx #FILE_FOCUS_BTN_END
  bne @loop
  rts

int_filetab_draw_focus:
  jsr int_filetab_draw_buttons
  jsr int_filetab_file_input_set_context
  lda filetab_focus
  bne @hide
  jsr li_show_cursor
  rts
@hide:
  jsr li_hide_cursor
  rts

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
  lda #<(cfg_draft_config+Cfg::aprs+CfgAprs::callsign)
  sta cfg_callsign_li+LineInput::data_ptr
  lda #>(cfg_draft_config+Cfg::aprs+CfgAprs::callsign)
  sta cfg_callsign_li+LineInput::data_ptr+1
  lda #APRS_CALLSIGN_LEN
  sta cfg_callsign_li+LineInput::num_visible
  sta cfg_callsign_li+LineInput::data_len

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
  sta cfg_ssid_li+LineInput::data_len
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

; converts the draft config ssid byte (0-15) into digits
; for the ssid field.
int_aprstab_ssid_to_text:
  lda cfg_draft_config+Cfg::aprs+CfgAprs::ssid
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
;   carry - set if invalid ssid, clear otherwise
int_aprstab_text_to_ssid:
  lda #<cfg_ssid_text
  sta CMDDATA0
  lda #>cfg_ssid_text
  sta CMDDATA1
  jsr pk_text_to_ssid
  bcs @error
  sta cfg_draft_config+Cfg::aprs+CfgAprs::ssid
  clc
  rts
@error:
  sec
  rts

; checks if the callsign is valid: no leading or interior spaces.
; outputs:
;   carry - set if invalid, clear if valid
; modifies:
;   CMDDATA0/1/2
;   a,y
int_aprstab_callsign_valid:
  lda #<(cfg_draft_config+Cfg::aprs+CfgAprs::callsign)
  sta CMDDATA0
  lda #>(cfg_draft_config+Cfg::aprs+CfgAprs::callsign)
  sta CMDDATA1
  lda #APRS_CALLSIGN_LEN
  sta CMDDATA2
  jsr ut_str_validate_no_gaps
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
  draw_menu_border mode_menu
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
  rts

; draws the chroma around the borders and the header
int_draw_menu_borders:
  lda selected_tab
  cmp #1
  beq @session
  cmp #2
  beq @serial
  cmp #3
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
  lda #CONFIG_FLAG_CANCELED
  sta cfg_config_flag
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

int_cmd_mode:
  handle_menu_next mode_menu
  ldy mode_menu+Menu::selected_index
  lda mode_menu_item_values,y
  sta cfg_draft_config+Cfg::serial+CfgSerial::mode
  rts

int_cmd_protocol:
  handle_menu_next protocol_menu
  ldy protocol_menu+Menu::selected_index
  lda protocol_menu_item_values,y
  sta cfg_draft_config+Cfg::session+CfgSession::protocol
  rts

int_cmd_start:
  lda cfg_draft_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::APRS
  bne @start

  ; only allow line mode in aprs
  lda #TERM_MODE::LINE
  sta cfg_draft_config+Cfg::serial+CfgSerial::mode
@aprs_check_callsign:
  jsr int_aprstab_callsign_valid
  bcc @aprs_check_ssid
  lda #<msg_invalid_callsign
  sta CMDDATA0
  lda #>msg_invalid_callsign
  sta CMDDATA1
  jsr int_start_show_status
  jmp @error
@aprs_check_ssid:
  jsr int_aprstab_text_to_ssid
  bcc @start
  lda #<msg_invalid_ssid
  sta CMDDATA0
  lda #>msg_invalid_ssid
  sta CMDDATA1
  jsr int_start_show_status
@error:
  sec
  rts
@start:
  ut_copy_struct_abs_to_abs cfg_draft_config, cfg_saved_config, Cfg
  lda #CONFIG_FLAG_START
  sta cfg_config_flag
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
  lda g_kbdcode_raw
  cmp #KEY_ESC
  beq @escape
  cmp #KEY_TAB
  beq @focus_next
  cmp #KEY_RETURN
  beq @activate
  ldx filetab_focus
  beq @name_focused
  jmp @done
@name_focused:
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
  ldx filetab_focus
  inx
  cpx #FILE_FOCUS_COUNT
  bne @focus_store
  ldx #FILE_FOCUS_NAME
@focus_store:
  stx filetab_focus
  jsr int_filetab_draw_focus
  jmp @done
@cursor_left:
  jsr int_filetab_file_input_set_context
  jsr li_move_cursor_left
  jmp @done
@cursor_right:
  jsr int_filetab_file_input_set_context
  jsr li_move_cursor_right
  jmp @done
@backspace:
  jsr int_filetab_file_input_set_context
  jsr li_backspace
  jmp @done
@char_delete:
  jsr int_filetab_file_input_set_context
  jsr li_char_delete
  jmp @done
@char_insert:
  jsr int_filetab_file_input_set_context
  jsr li_char_insert
  jmp @done
@activate:
  lda filetab_focus
  cmp #FILE_FOCUS_DEFAULT
  beq @do_default
  cmp #FILE_FOCUS_LOAD
  beq @do_load
  cmp #FILE_FOCUS_SAVE
  beq @do_save
  jmp @done
@do_default:
  jsr int_filetab_clear_status
  jsr int_load_default_config
  jmp @done
@do_load:
  jsr int_filetab_clear_status
  jsr int_filetab_load
  jmp @done
@do_save:
  jsr int_filetab_clear_status
  jsr int_filetab_save_file
  jmp @done
@typechar:
  lda g_kbdcode_atascii
  cmp #' '
  beq @type
  jsr ut_is_alphanumeric
  bcs @done
  cmp #'a'
  bcc @type
  cmp #'z'+1
  bcs @type
  sec
  sbc #$20
@type:
  pha
  jsr int_filetab_file_input_set_context
  pla
  sta CMDDATA0
  jsr li_type_char
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
  cmp #$25
  beq @mode
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
@mode:
  jsr int_cmd_mode
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
  jsr int_aprstab_text_to_ssid
  jmp @done
@char_delete:
  jsr int_aprstab_input_set_context
  jsr li_char_delete
  jsr int_aprstab_text_to_ssid
  jmp @done
@char_insert:
  jsr int_aprstab_input_set_context
  jsr li_char_insert
  jsr int_aprstab_text_to_ssid
  jmp @done
@typechar:
  lda aprstab_focus
  cmp #APRS_FOCUS_SSID
  beq @ssid_char
@call_char:
  lda g_kbdcode_atascii
  cmp #' '
  beq @type_callsign
  jsr ut_is_alphanumeric
  bcs @done
  cmp #'a'
  bcc @type_callsign
  cmp #'z'+1
  bcs @type_callsign
  sec
  sbc #$20
@type_callsign:
  pha
  jsr int_aprstab_input_set_context
  pla
  sta CMDDATA0
  jsr li_type_char
  jmp @done
@ssid_char:
  lda g_kbdcode_atascii
  cmp #' '
  beq @type_ssid
  jsr ut_ascii_char_to_digit
  bcs @done
@type_ssid:
  jsr int_aprstab_input_set_context
  lda g_kbdcode_atascii
  sta CMDDATA0
  jsr li_type_char
  jsr int_aprstab_text_to_ssid
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
  beq @aprs
  jsr int_filetab_handle_kbd
  jmp @done
@session:
  jsr int_session_handle_kbd
  jmp @done
@serial:
  jsr int_serial_handle_kbd
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
; the space-padded name in cfg_basename.
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
  lda cfg_basename,x
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
;   carry - clear on success, set on error
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
;   carry - clear on success, set on error
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
;   carry - clear on success, set on error
cfg_save_lastfile:
  lda cfg_drive
  sta cfg_lastfile_data
  ldx #CFG_NAME_LEN-1
@copy:
  lda cfg_basename,x
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

; loads the last file saved or loaded into cfg_drive and cfg_basename.
; on error (e.g. first boot) falls back to drive 1 and a blank name.
;
; on-disk format: "DXXXXXXXX"
;   D         - drive number
;    XXXXXXXX - file name (CFG_NAME_LEN chars), trailing space padded
;
; outputs:
;   carry - clear on success, set on error
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
  sta cfg_basename,x
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
  sta cfg_basename,x
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

mode_menu:                     .tag Menu
mode_menu_header:              .byte 'M'|$80,"ode",$00
mode_menu_item_values:
  .byte TERM_MODE::LINE
  .byte TERM_MODE::CHAR
  .byte TERM_MODE::MULTI
mode_menu_item_values_end:
mode_menu_item_labels:
mode_menu_item_label_line:     .byte "Line",$00
mode_menu_item_label_char:     .byte "Char",$00
mode_menu_item_label_multi:    .byte "Multi",$00

protocol_menu:                 .tag Menu
protocol_menu_header:          .byte '0'|$80,"Protocol",$00
protocol_menu_item_values:
  .byte TERM_PROTOCOL::APRS
  .byte TERM_PROTOCOL::TERM
protocol_menu_item_values_end:
protocol_menu_item_labels:
protocol_menu_item_label_aprs: .byte "APRS",$00
protocol_menu_item_label_term: .byte "Terminal",$00

top_banner:             .byte ' ','S'|$80,'E'|$80,'L'|$80,"tab-> "
                        .byte "          "
                        .byte 'E'|$80,'S'|$80,'C'|$80,"cancel "
                        .byte 'S'|$80,'T'|$80,'A'|$80,'R'|$80,'T'|$80,"start"
                        .byte $00
tabs_banner:            .byte " File|Session|Serial|APRS"
                        .byte $00
tabs_highlight_starts:  .byte 1,6,14,21
tabs_highlight_ends:    .byte 5,13,20,25
num_tabs:               .byte 4
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

cfg_drive:              .byte 1
cfg_basename:           .res CFG_NAME_LEN
cfg_filespec:           .res 3+CFG_NAME_LEN+4+1; "Dn:"+name+".CFG"+EOL
cfg_lastfile_filespec:  .byte "D1:KISSTTY.LST", EOL
cfg_lastfile_data:      .res CFG_LASTFILE_LEN

cfg_li:                 .tag LineInput
filetab_focus:          .byte 0
file_btn_idx:           .byte 0

cfg_callsign_li:        .tag LineInput
cfg_ssid_li:            .tag LineInput
cfg_ssid_text:          .res APRS_SSID_LEN
aprstab_focus:          .byte 0
aprs_callsign_label:    .byte "Callsign:",$00
aprs_ssid_label:        .byte "SSID:",$00

cfg_aprs_li_ptrs_lo:    .byte <cfg_callsign_li, <cfg_ssid_li
cfg_aprs_li_ptrs_hi:    .byte >cfg_callsign_li, >cfg_ssid_li

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

msg_invalid_callsign:   .byte "Invalid APRS callsign",$00
msg_invalid_ssid:       .byte "Invalid APRS ssid",$00

file_btn_offs_lo:       .byte <FILE_BTN_LOAD_OFFSET, <FILE_BTN_SAVE_OFFSET, <FILE_BTN_DEF_OFFSET
file_btn_offs_hi:       .byte >FILE_BTN_LOAD_OFFSET, >FILE_BTN_SAVE_OFFSET, >FILE_BTN_DEF_OFFSET
file_btn_ptrs_lo:       .byte <btn_load, <btn_save, <btn_default
file_btn_ptrs_hi:       .byte >btn_load, >btn_save, >btn_default

