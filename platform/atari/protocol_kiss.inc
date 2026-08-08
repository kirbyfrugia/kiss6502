; Protocols:
; * [KISS](https://erikarn.github.io/ax25/CNC1987-KISS-TNC-K3MC-KA9Q.pdf)
; * [APRS](https://aprspedia.com/doku.php?id=aprs_protocols:digipeter_addresses_field)
; * [AX.25](https://www.ax25.net/AX25.2.2-Jul%2098-2.pdf)
;
; Frames are sent in 8-bit binary.
; Frames are preceded and followed by the FEND byte, e.g.
; FEND CMD ...data... FEND
;
; We need to handle the case where we get data before the
; first FEND and the case where we get multiple FENDs
; in a row (e.g. between frames or when the sender wants
; to explicitly flush the buffer).
;
; This is simple.
;
; On startup, set `kiss_started` to false and `buffer_index`
; to zero.
;
; When FEND is received, if buffer_index is greater than zero,
; process the frame. Whether or not there was data, reset
; the buffer (set buffer_index to 0).
;
; Special bytes within the data are escaped using two-byte
; sequences. FESC introduces the escape, and the byte
; following it indicates what the original byte was:
;   FESC TFEND ($db $dc) -> original byte was $c0 (FEND)
;   FESC TFESC ($db $dd) -> original byte was $db (FESC)
.ifndef PCTL_KISS_INC
PCTL_KISS_INC = 1

.linecont +

.global pk_reset
.global pk_set_tx_header
.global pk_vbi_tick
.global pk_new_byte
.global pk_next_frame
.global pk_process_frame
.global pk_state
.global pk_frame_header
.global pk_send_message
.global pk_send_param
.global pk_error
.global pk_broadcast_addressee
.global pk_encode_addr
.global pk_source_addr
.global pk_digi_addrs
.global pk_digi_len
.global pk_parse_callsign
.global pk_callsign
.global pk_ssid
.global pk_ack_state
.global pk_repeats
.global pk_have_sent

APRS_CALLSIGN_LEN             = 6
APRS_MAX_MSG_LEN              = 67
APRS_SSID_LEN                 = 2
APRS_MAX_DIGI                 = 8
APRS_DIGI_LEN                 = (APRS_CALLSIGN_LEN+1+APRS_SSID_LEN) \
                                *APRS_MAX_DIGI + (APRS_MAX_DIGI-1)*2

KISS_STATE_NEW                = %10000000 ; waiting for first FEND
KISS_STATE_FESC               = %01000000 ; in an FESC waiting for next byte
KISS_STATE_ADDR               = %00100000 ; the address portion of the frame
KISS_STATE_BTWN               = %00010000 ; the bytes between addr and info
KISS_STATE_INFO               = %00001000 ; the info portion
KISS_FRAME_READY              = %00000100 ; frame complete and ready to be processed

KISS_FEND                     = $c0
KISS_FESC                     = $db
KISS_TFEND                    = $dc
KISS_TFESC                    = $dd

KISS_DUPLEX_HALF              = %00000000
KISS_DUPLEX_FULL              = %11111111

KISS_DEFAULT_TNC_TX_DELAY     = 50
KISS_DEFAULT_TNC_PERSISTENCE  = 63
KISS_DEFAULT_TNC_SLOT_TIME    = 10
KISS_DEFAULT_TNC_TX_TAIL      = 10

; >092345zNet Control center
;KISS_TYPE_STATUS_TIMESTAMP_ZULU_IDX = 7

; :NOCALL   :Message
KISS_TYPE_MSG_START_COLON_IDX = 0
KISS_TYPE_MSG_ADDRESSEE_IDX   = 1
KISS_TYPE_MSG_END_COLON_IDX   = 10
KISS_TYPE_MSG_TEXT_IDX        = 11
KISS_ADDRESSEE_LEN            = 9

; an ack is the text "ack" followed by a 1 to 5 char message id
KISS_ACK_PREFIX_LEN           = 3
KISS_MSG_ID_MIN_LEN           = 1
KISS_MSG_ID_MAX_LEN           = 5
KISS_MSG_ID_LEN               = 4

KISS_ACK_STATE_NONE           = 0
KISS_ACK_STATE_PENDING        = 1
KISS_ACK_STATE_ACKED          = 2
KISS_REPEATS_MAX              = 99

KISS_SEND_FLAG_TRIM_END       = %10000000
KISS_SEND_FLAG_NO_MSG_ID      = %01000000
KISS_SEND_FLAG_NO_ECHO        = %00100000

KISS_HIGHLIGHT_SOURCE         = %10000000
KISS_HIGHLIGHT_ADDRESSEE      = %01000000

KISS_ADDR_COMMAND             = %10000000
KISS_ADDR_RESERVED            = %01100000
KISS_ADDR_LAST                = %00000001

; commands 
; all the times/delays are in 10ms units,
; e.g. a TX_DELAY of 50 = 500ms
.enum KISS_CMD
  DATA_FRAME  = $00
  TX_DELAY    = $01 ; keyup delay
  PERSISTENCE = $02 ; next byte is persp
  SLOT_TIME   = $03
  TX_TAIL     = $04
  DUPLEX      = $05
  RETURN      = $ff
.endenum

; these are sent shifted left by one bit
; but they are unshifted in this struct
.struct KissFrameAddr
  callsign .res 6
  ssid     .res 1
.endstruct

.struct KissFrameHeader
  cmd_type    .res 1
  dest        .tag KissFrameAddr
  source      .tag KissFrameAddr
  digipeater  .res 8 * .sizeof(KissFrameAddr)
  control     .res 1
  protocol_id .res 1
  num_digi    .res 1 ; number of digipeater addresses
.endstruct

.endif
