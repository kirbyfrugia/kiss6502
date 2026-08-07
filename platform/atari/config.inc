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

.struct Cfg
  config_version .res 1
  session        .tag CfgSession
  term           .tag CfgTerm
  serial         .tag CfgSerial
  aprs           .tag CfgAprs
.endstruct

.struct Preset
  scr_pos_ptr    .word
  label_ptr      .word
  config_ptr     .word
.endstruct



.macro make_config  config, _protocol, _terminal_mode, _line_ending, _baud, _data_bits, \
                   _stop_bits, _parity, _cts, _dsr, _dtr, _rets
  lda #_protocol
  sta config+Cfg::session+CfgSession::protocol
  lda #_terminal_mode
  sta config+Cfg::term+CfgTerm::terminal_mode
  lda #_line_ending
  sta config+Cfg::term+CfgTerm::line_ending
  lda #_baud
  sta config+Cfg::serial+CfgSerial::baud
  lda #_data_bits
  sta config+Cfg::serial+CfgSerial::data_bits
  lda #_stop_bits
  sta config+Cfg::serial+CfgSerial::stop_bits
  lda #_parity
  sta config+Cfg::serial+CfgSerial::parity
  lda #_cts
  sta config+Cfg::serial+CfgSerial::cts
  lda #_dsr
  sta config+Cfg::serial+CfgSerial::dsr
  lda #_dtr
  sta config+Cfg::serial+CfgSerial::dtr
  lda #_rets
  sta config+Cfg::serial+CfgSerial::rets
  ; TODO: maybe make the rest of these options
  lda #RS232_TRANSLATION::NONE
  sta config+Cfg::serial+CfgSerial::translation
  lda #RS232_LINE_FEED::NO_APPEND_LF
  sta config+Cfg::serial+CfgSerial::line_feed
  lda #RS232_CRX::OFF
  sta config+Cfg::serial+CfgSerial::crx
  lda #RS232_XMT::NO_CHANGE
  sta config+Cfg::serial+CfgSerial::xmt
.endmacro

.assert .sizeof(Cfg) = 100, error, "sizeof(Cfg) changed, bump CONFIG_VERSION"

.endif

