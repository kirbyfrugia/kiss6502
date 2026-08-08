.ifndef CONFIG_INC
CONFIG_INC = 1

.global cfg_init
.global cfg_activate
.global cfg_tick
.global cfg_config_flag
.global cfg_saved_config
.global cfg_select_fired
.global cfg_start_fired

.global cfg_field_kind
.global cfg_field_scr_lo
.global cfg_field_scr_hi
.global cfg_field_width
.global cfg_field_data_lo
.global cfg_field_data_hi
.global cfg_field_values_lo
.global cfg_field_values_hi
.global cfg_field_labels_lo
.global cfg_field_labels_hi
.global cfg_field_arg0
.global cfg_field_arg1

CONFIG_VERSION       = 1
CONFIG_FLAG_EDITING  = %00000000
CONFIG_FLAG_CANCELED = %10000000
CONFIG_FLAG_START    = %11000000

.linecont +

.struct CfgSerial
  baud           .res 1
  data_bits      .res 1
  stop_bits      .res 1
  parity         .res 1
  cts            .res 1
  dsr            .res 1
  crx            .res 1
  dtr            .res 1
  rets           .res 1
  xmt            .res 1
  translation    .res 1
  line_feed      .res 1
  placeholder    .res 4
.endstruct

.struct CfgSession
  protocol       .res 1
  placeholder    .res 4
.endstruct

.struct CfgTerm
  terminal_mode  .res 1
  line_ending    .res 1
  placeholder    .res 8
.endstruct

.struct CfgAprsAddr
  callsign       .res 6
  ssid           .res 1
.endstruct

.struct CfgAprs
  me             .tag CfgAprsAddr
  num_digi       .res 1
  digi           .res 8*.sizeof(CfgAprsAddr)
  placeholder    .res 4
.endstruct

.struct CfgTnc
  tx_delay       .res 1
  persistence    .res 1
  slot_time      .res 1
  tx_tail        .res 1
  duplex         .res 1
  placeholder    .res 4
.endstruct

.struct Cfg
  config_version .res 1
  session        .tag CfgSession
  serial         .tag CfgSerial
  term           .tag CfgTerm
  aprs           .tag CfgAprs
  tnc            .tag CfgTnc
.endstruct

.struct Preset
  scr_pos_ptr    .word
  label_ptr      .word
  config_ptr     .word
.endstruct

.assert .sizeof(Cfg) = 109, error, "sizeof(Cfg) changed, bump CONFIG_VERSION"

.macro init_li _li, _text, _scr_offset, _num_visible, _data_size
  lda #0
  sta _li+LineInput::scr_cursor
  sta _li+LineInput::data_cursor
  sta _li+LineInput::first_visible
  lda #<_scr_offset
  clc
  adc SCR_PTR_LO
  sta _li+LineInput::scr_ptr
  lda #>_scr_offset
  adc SCR_PTR_HI
  sta _li+LineInput::scr_ptr+1
  lda #<_text
  sta _li+LineInput::data_ptr
  lda #>_text
  sta _li+LineInput::data_ptr+1
  lda #_num_visible
  sta _li+LineInput::num_visible
  lda #_data_size
  sta _li+LineInput::data_size

.endmacro

.endif

