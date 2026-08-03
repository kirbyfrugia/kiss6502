; Thanks to Paul Guertin (pg@sff.net) 
; [CRC-16 CCITT version](https://6502.org/source/integers/crc.htm)
;
; Modified to assemble with CA65

.setcpu "6502"
.include "atari.inc"
.include "crc.inc"

.segment "ZEROPAGE"
crc_lo: .res 1
crc_hi: .res 1

.segment "CODE"

CRCLO    = $9600       ; Two 256-byte tables for quick lookup
CRCHI    = $9700       ; (should be page-aligned for speed)

crc_make_table:
          LDX #0              ; X counts from 0 to 255
BYTELOOP: LDA #0              ; A contains the low 8 bits of the CRC-16
          STX crc_lo         ; and CRC contains the high 8 bits
          LDY #8              ; Y counts bits in a byte
BITLOOP:  ASL
          ROL crc_lo         ; Shift CRC left
          BCC NOADD           ; Do nothing if no overflow
          EOR #$21            ; else add CRC-16 polynomial $1021
          PHA                 ; Save low byte
          LDA crc_lo         ; Do high byte
          EOR #$10
          STA crc_lo
          PLA                 ; Restore low byte
NOADD:    DEY
          BNE BITLOOP         ; Do next bit
          STA CRCLO,X         ; Save CRC into table, low byte
          LDA crc_lo         ; then high byte
          STA CRCHI,X
          INX
          BNE BYTELOOP        ; Do next byte
          RTS

crc_upd:
          EOR crc_lo+1       ; Quick CRC computation with lookup tables
          TAX
          LDA crc_lo
          EOR CRCHI,X
          STA crc_lo+1
          LDA CRCLO,X
          STA crc_lo
          RTS
