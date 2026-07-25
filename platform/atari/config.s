.setcpu "6502"

.include "atari.inc" ; /usr/share/cc65/asminc/atari.inc
.include "config.inc"
.include "globals.inc"
.include "rs232.inc"
.include "term.inc"
.include "utils.inc"

.segment "ZEROPAGE"
cfg_ptr_lo:                  .res 1
cfg_ptr_hi:                  .res 1

.segment "CODE"
.linecont +

.define MENU_MARGIN_TOP 1

cfg_init:
  lda #CONFIG_FLAG_EDITING
  sta cfg_config_flag

  OFFSET       .set (MENU_MARGIN_TOP+18) * SCREEN_WIDTH + 13
  make_config preset_fastchar_config, \
                  TERM_PROTOCOL::TERM, \
                  TERM_MODE::CHAR, \
                  RS232_BAUD::B9600, \
                  RS232_WORDSIZE::N8, \
                  RS232_STOPBITS::N1, \
                  RS232_PARITY::NONE, \
                  RS232_CTS::OFF, \
                  RS232_DSR::OFF, \
                  RS232_DTR::ON, \
                  RS232_RTS::ON
  make_preset preset_fastchar, preset_fastchar_config, \
              preset_fastchar_label, OFFSET 

  OFFSET       .set (MENU_MARGIN_TOP+19) * SCREEN_WIDTH + 13
  make_config preset_fastline_config, \
                  TERM_PROTOCOL::TERM, \
                  TERM_MODE::LINE, \
                  RS232_BAUD::B9600, \
                  RS232_WORDSIZE::N8, \
                  RS232_STOPBITS::N1, \
                  RS232_PARITY::NONE, \
                  RS232_CTS::OFF, \
                  RS232_DSR::OFF, \
                  RS232_DTR::ON, \
                  RS232_RTS::ON
  make_preset preset_fastline, preset_fastline_config, \
              preset_fastline_label, OFFSET 

  OFFSET       .set (MENU_MARGIN_TOP+18) * SCREEN_WIDTH + 25
  make_config preset_vintage_config, \
                  TERM_PROTOCOL::TERM, \
                  TERM_MODE::CHAR, \
                  RS232_BAUD::B1200, \
                  RS232_WORDSIZE::N7, \
                  RS232_STOPBITS::N1, \
                  RS232_PARITY::EVEN, \
                  RS232_CTS::OFF, \
                  RS232_DSR::OFF, \
                  RS232_DTR::ON, \
                  RS232_RTS::ON
  make_preset preset_vintage, preset_vintage_config, \
              preset_vintage_label, OFFSET 

  OFFSET       .set (MENU_MARGIN_TOP+19) * SCREEN_WIDTH + 25
  make_config preset_APRS_config, \
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
  make_preset preset_APRS, preset_APRS_config, \
              preset_APRS_label, OFFSET 

  ; default config
  ut_copy_struct_abs_to_abs preset_APRS_config, cfg_draft_config, Cfg
  ut_copy_struct_abs_to_abs preset_APRS_config, cfg_saved_config, Cfg

  OFFSET        .set (MENU_MARGIN_TOP+1) * SCREEN_WIDTH + 2
  NUM_ITEMS     .set 7
  BORDER_WIDTH  .set 8
  make_menu baud_menu, baud_menu_header, \
            baud_menu_item_values, baud_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+1) * SCREEN_WIDTH + 11
  NUM_ITEMS     .set 3
  BORDER_WIDTH  .set 13
  make_menu parity_menu, parity_menu_header, \
            parity_menu_item_values, parity_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+10) * SCREEN_WIDTH + 2
  NUM_ITEMS     .set 4
  BORDER_WIDTH  .set 8 
  make_menu data_menu, data_menu_header, \
            data_menu_item_values, data_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+16) * SCREEN_WIDTH + 2
  NUM_ITEMS     .set 2
  BORDER_WIDTH  .set 8
  make_menu stop_menu, stop_menu_header, \
            stop_menu_item_values, stop_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+6) * SCREEN_WIDTH + 11
  NUM_ITEMS     .set 2
  BORDER_WIDTH  .set 6
  make_menu cts_menu, cts_menu_header, \
            cts_menu_item_values, cts_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+6) * SCREEN_WIDTH + 18
  NUM_ITEMS     .set 2
  BORDER_WIDTH  .set 6
  make_menu dsr_menu, dsr_menu_header, \
            dsr_menu_item_values, dsr_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+10) * SCREEN_WIDTH + 11
  NUM_ITEMS     .set 3
  BORDER_WIDTH  .set 6
  make_menu dtr_menu, dtr_menu_header, \
            dtr_menu_item_values, dtr_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+10) * SCREEN_WIDTH + 18
  NUM_ITEMS     .set 3
  BORDER_WIDTH  .set 6
  make_menu rts_menu, rts_menu_header, \
            rts_menu_item_values, rts_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+1) * SCREEN_WIDTH + 26
  NUM_ITEMS     .set 3
  BORDER_WIDTH  .set 11
  make_menu protocol_menu, protocol_menu_header, \
            protocol_menu_item_values, protocol_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

  OFFSET        .set (MENU_MARGIN_TOP+6) * SCREEN_WIDTH + 26
  NUM_ITEMS     .set 3
  BORDER_WIDTH  .set 11
  make_menu mode_menu, mode_menu_header, \
            mode_menu_item_values, mode_menu_item_labels, \
            NUM_ITEMS, BORDER_WIDTH, OFFSET

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
  lda #$45 ; upper right corner
  sta (g_temp_scr_ptr_lo),y
  lda #$52 ; horizontal bar
@top_loop:
  dey
  sta (g_temp_scr_ptr_lo),y
  bne @top_loop
  lda #$51 ; upper left corner
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
  ldy #0
  lda #$41 ; vertical left bar
  sta (g_temp_scr_ptr_lo),y
  ldy draw_menu_border_width 
  lda #$44 ; vertical right bar
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
  lda #$43 ; lower right corner
  sta (g_temp_scr_ptr_lo),y
  lda #$52 ; horizontal bar
@btm_loop:
  dey
  sta (g_temp_scr_ptr_lo),y
  bne @btm_loop
  lda #$5a ; lower left corner
  sta (g_temp_scr_ptr_lo),y

  rts

; draws the preset title for a given preset
; inputs:
;   cfg_ptr_lo/hi - ptr to the preset
int_draw_preset:
  ldy #Preset::scr_pos_ptr
  lda (cfg_ptr_lo),y
  sta g_temp_scr_ptr_lo
  iny
  lda (cfg_ptr_lo),y
  sta g_temp_scr_ptr_hi

  ldy #Preset::label_ptr
  lda (cfg_ptr_lo),y
  sta g_temp_data_ptr_lo
  iny
  lda (cfg_ptr_lo),y
  sta g_temp_data_ptr_hi

  ldy #0
@loop:
  lda (g_temp_data_ptr_lo),y
  beq @loop_done ; null char
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  iny
  bne @loop
@loop_done:
  rts

int_draw_tabs:
  lda SCR_PTR_LO
  clc
  adc #SCREEN_WIDTH
  sta g_temp_scr_ptr_lo
  lda SCR_PTR_HI
  adc #0
  sta g_temp_scr_ptr_hi

  ldy #(SCREEN_WIDTH-1)
  lda #' '
  eor #$80
  jsr ut_atascii_to_icode
@clear_loop:
  sta (g_temp_scr_ptr_lo),y
  dey
  bpl @clear_loop

  ldy #0
@tabs_banner_loop:
  lda tabs_banner,y
  beq @tabs_banner_done
  eor #$80
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  iny
  jmp @tabs_banner_loop
@tabs_banner_done:
  rts

; draws the banners and the "Preset" label
; and any other ui elements
int_draw_main:
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

  lda SCR_PTR_LO
  clc
  adc #<((SCREEN_HEIGHT-2)*SCREEN_WIDTH+1)
  sta g_temp_scr_ptr_lo
  lda SCR_PTR_HI
  adc #>((SCREEN_HEIGHT-2)*SCREEN_WIDTH+1)
  sta g_temp_scr_ptr_hi
 
  ldy #0
@mode_protocol_loop:
  lda mode_protocol_str,y
  beq @mode_protocol_done
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  iny
  jmp @mode_protocol_loop
@mode_protocol_done:

  OFFSET .set (MENU_MARGIN_TOP+17) * SCREEN_WIDTH + 13
  lda SCR_PTR_LO
  clc
  adc #<OFFSET
  sta g_temp_scr_ptr_lo
  lda SCR_PTR_HI
  adc #>OFFSET
  sta g_temp_scr_ptr_hi

  ldy #0
@serial_preset_loop:
  lda presets,y
  beq @serial_preset_done
  jsr ut_atascii_to_icode
  sta (g_temp_scr_ptr_lo),y
  iny
  jmp @serial_preset_loop
@serial_preset_done:
  rts

; redraws the menu items, sets the selected by value,
; and highlights the selected menu item.
int_refresh_menus:
  ; TODO: split this out based on what tab is selected
  refresh_menu baud_menu,     cfg_draft_config+Cfg::serial+CfgSerial::baud
  refresh_menu parity_menu,   cfg_draft_config+Cfg::serial+CfgSerial::parity
  refresh_menu data_menu,     cfg_draft_config+Cfg::serial+CfgSerial::data_bits
  refresh_menu stop_menu,     cfg_draft_config+Cfg::serial+CfgSerial::stop_bits
  refresh_menu cts_menu,      cfg_draft_config+Cfg::serial+CfgSerial::cts
  refresh_menu dsr_menu,      cfg_draft_config+Cfg::serial+CfgSerial::dsr
  refresh_menu dtr_menu,      cfg_draft_config+Cfg::serial+CfgSerial::dtr
  refresh_menu rts_menu,      cfg_draft_config+Cfg::serial+CfgSerial::rets
  refresh_menu mode_menu,     cfg_draft_config+Cfg::serial+CfgSerial::mode
  refresh_menu protocol_menu, cfg_draft_config+Cfg::session+CfgSession::protocol
  rts

; draws the chroma around the borders and the header
int_draw_menu_borders:
  ; TODO: split this out based on what tab is selected
  draw_menu_border baud_menu
  draw_menu_border parity_menu
  draw_menu_border data_menu
  draw_menu_border stop_menu
  draw_menu_border cts_menu
  draw_menu_border dsr_menu
  draw_menu_border dtr_menu
  draw_menu_border rts_menu
  draw_menu_border mode_menu
  draw_menu_border protocol_menu
  
  rts

cfg_activate:
  lda #CONFIG_FLAG_EDITING
  sta cfg_config_flag

  ut_copy_struct_abs_to_abs cfg_saved_config, cfg_draft_config, Cfg

  jsr int_draw_menu_borders
  jsr int_refresh_menus

  draw_preset preset_fastchar
  draw_preset preset_vintage
  draw_preset preset_fastline
  draw_preset preset_APRS

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

int_cmd_preset_fastchar:
  ut_copy_struct_abs_to_abs preset_fastchar_config, cfg_draft_config, Cfg
  jsr int_refresh_menus
  rts

int_cmd_preset_fastline:
  ut_copy_struct_abs_to_abs preset_fastline_config, cfg_draft_config, Cfg
  jsr int_refresh_menus
  rts

int_cmd_preset_vintage:
  ut_copy_struct_abs_to_abs preset_vintage_config, cfg_draft_config, Cfg
  jsr int_refresh_menus
  rts

int_cmd_preset_APRS:
  ut_copy_struct_abs_to_abs preset_APRS_config, cfg_draft_config, Cfg
  jsr int_refresh_menus
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

int_cmd_accept:
  lda #CONFIG_FLAG_ACCEPTED
  sta cfg_config_flag

  ; if APRS mode, override the user setting
  lda cfg_draft_config+Cfg::session+CfgSession::protocol
  cmp #TERM_PROTOCOL::APRS
  bne @no_override
  lda #TERM_MODE::LINE
  sta cfg_draft_config+Cfg::serial+CfgSerial::mode
@no_override:
  ut_copy_struct_abs_to_abs cfg_draft_config, cfg_saved_config, Cfg
  rts

int_handle_key_serial:
  rts

  ; TODO: split this out based on what tab is selected
int_handle_kbd:
  lda g_kbd_key_pressed
  bne @valid_key
  jmp @done
@valid_key:
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
  cmp #$32
  beq @protocol
  cmp #$1f
  beq @one
  cmp #$1e
  beq @two
  cmp #$1a
  beq @three
  cmp #$18
  beq @four
  cmp #$1c
  beq @escape
  cmp #$0c
  beq @return
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
@protocol:
  jsr int_cmd_protocol
  jmp @done
@one:
  jsr int_cmd_preset_fastchar
  jmp @done
@two:
  jsr int_cmd_preset_fastline
  jmp @done
@three:
  jsr int_cmd_preset_vintage
  jmp @done
@four:
  jsr int_cmd_preset_APRS
  jmp @done
@escape:
  jsr int_cmd_cancel
  jmp @done
@return:
  jsr int_cmd_accept
@done:
  rts

cfg_tick:
  jsr int_handle_kbd
  rts

baud_menu:                     .tag Menu
baud_menu_header:              .byte 'B'|$80,"aud",$00
baud_menu_item_values:
  .byte RS232_BAUD::B50
  .byte RS232_BAUD::B300
  .byte RS232_BAUD::B600
  .byte RS232_BAUD::B1200
  .byte RS232_BAUD::B2400
  .byte RS232_BAUD::B9600
  .byte RS232_BAUD::B19200
baud_menu_item_values_end:
baud_menu_item_labels:
baud_menu_item_label_50:       .byte "50",$00
baud_menu_item_label_300:      .byte "300",$00
baud_menu_item_label_600:      .byte "600",$00
baud_menu_item_label_1200:     .byte "1200",$00
baud_menu_item_label_2400:     .byte "2400",$00
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
mode_menu_header:              .byte "Term ",'M'|$80,"ode*",$00
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
  .byte TERM_PROTOCOL::RTTY
protocol_menu_item_values_end:
protocol_menu_item_labels:
protocol_menu_item_label_aprs: .byte "APRS",$00
protocol_menu_item_label_term: .byte "Terminal",$00
protocol_menu_item_label_rtty: .byte "RTTY",$00

presets:                .byte "Presets:",$00
preset_fastchar:        .tag Preset
preset_fastchar_config: .tag Cfg
preset_fastchar_label:  .byte '1'|$80,"Fast Char",$00
preset_fastline:        .tag Preset
preset_fastline_config: .tag Cfg
preset_fastline_label:  .byte '2'|$80,"Fast Line",$00
preset_vintage:         .tag Preset
preset_vintage_config:  .tag Cfg
preset_vintage_label:   .byte '3'|$80,"Slow Char",$00
preset_APRS:            .tag Preset
preset_APRS_config:     .tag Cfg
preset_APRS_label:      .byte '4'|$80,"APRS",$00


top_banner:             .byte ' ','S'|$80,'E'|$80,'L'|$80,"next "
                        .byte "            "
                        .byte 'E'|$80,'S'|$80,'C'|$80,"cancel "
                        .byte 'S'|$80,'T'|$80,'A'|$80,'R'|$80,'T'|$80,"run"
                        .byte $00
;tabs_banner:            .byte "File|Sess|Ser|APRS"
tabs_banner:            .byte " File|Sess|Ser|APRS"
                        .byte $00
mode_protocol_str:      .byte "* may be ignored for some protocols",$00
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

