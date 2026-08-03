; Thanks to Bruce Clark
; [Bruce Clark mem move](https://6502.org/source/general/memory_move.html)
.setcpu "6502"

.include "globals.inc"
.include "memmove.inc"

.segment "CODE"

; Move memory down to a lower address
;
; MM_FROM = source start address
;   MM_TO = destination start address
; SIZE = number of bytes to move
;
MM_MOVEDOWN:
         LDY #0
         LDX MM_SIZEH
         BEQ @MD2
@MD1:    LDA (MM_FROM),Y ; move a page at a time
         STA (MM_TO),Y
         INY
         BNE @MD1
         INC MM_FROM+1
         INC MM_TO+1
         DEX
         BNE @MD1
@MD2:    LDX MM_SIZEL
         BEQ @MD4
@MD3:    LDA (MM_FROM),Y ; move the remaining bytes
         STA (MM_TO),Y
         INY
         DEX
         BNE @MD3
@MD4:    RTS

; Move memory up to a higher address
;
; MM_FROM = source start address
;   MM_TO = destination start address
; SIZE = number of bytes to move
;
MM_MOVEUP_SS:
           LDX MM_SIZEH    ; the last byte must be moved first
           CLC          ; start at the final pages of MM_FROM and MM_TO
           TXA
           ADC MM_FROM+1
           STA MM_FROM+1
           CLC
           TXA
           ADC MM_TO+1
           STA MM_TO+1
           INX          ; allows the use of BNE after the DEX below
           LDY MM_SIZEL
           BEQ @MU3
           DEY          ; move bytes on the last page first
           BEQ @MU2
@MU1:      LDA (MM_FROM),Y
           STA (MM_TO),Y
           DEY
           BNE @MU1
@MU2:      LDA (MM_FROM),Y ; handle Y = 0 separately
           STA (MM_TO),Y
@MU3:      DEY
           DEC MM_FROM+1   ; move the next page (if any)
           DEC MM_TO+1
           DEX
           BNE @MU1
           RTS

; Move memory up to a higher address
;
; MM_FROM = 1 + source end address
; MM_TO   = 1 + destination end address
; SIZE = number of bytes to move
;
MM_MOVEUP_E1E1:
         LDY #$FF
         LDX MM_SIZEH
         BEQ @MU3
@MU1:    DEC MM_FROM+1
         DEC MM_TO+1
@MU2:    LDA (MM_FROM),Y ; move a page at a time
         STA (MM_TO),Y
         DEY
         BNE @MU2
         LDA (MM_FROM),Y ; handle Y = 0 separately
         STA (MM_TO),Y
         DEY
         DEX
         BNE @MU1
@MU3:    LDX MM_SIZEL
         BEQ @MU5
         DEC MM_FROM+1
         DEC MM_TO+1
@MU4:    LDA (MM_FROM),Y ; move the remaining bytes
         STA (MM_TO),Y
         DEY
         DEX
         BNE @MU4
@MU5:    RTS

; Move memory up to a higher address
;
; MM_FROM = source end address
; MM_TO   = destination end address
; SIZE = number of bytes to move
;
MM_MOVEUP_EE:
         LDY #0
         LDX MM_SIZEH
         BEQ @MU3
@MU1:    LDA (MM_FROM),Y ; handle Y = 0 separately
         STA (MM_TO),Y
         DEY
         DEC MM_FROM+1
         DEC MM_TO+1
@MU2:    LDA (MM_FROM),Y ; move a page at a time
         STA (MM_TO),Y
         DEY
         BNE @MU2
         DEX
         BNE @MU1
@MU3:    LDX MM_SIZEL
         BEQ @MU5
         LDA (MM_FROM),Y ; handle Y = 0 separately
         STA (MM_TO),Y
         DEY
         DEX
         BEQ @MU5
         DEC MM_FROM+1
         DEC MM_TO+1
@MU4:    LDA (MM_FROM),Y ; move the remaining bytes
         STA (MM_TO),Y
         DEY
         DEX
         BNE @MU4
@MU5:    RTS
