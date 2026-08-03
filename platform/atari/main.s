.setcpu "6502"
.include "atari.inc" ; /usr/share/cc65/asminc/atari.inc
.include "config.inc"
.include "crc.inc"
.include "globals.inc"
.include "kbd.inc"
.include "main.inc"
.include "screen.inc"
.include "term.inc"
.include "line_input.inc"
.include "text_area.inc"
.include "utils.inc"

.ifdef DEBUG
.include "wozmon.inc"
.endif

.segment "CODE"

STATE_CONFIG          = %10000000
STATE_RUNNING         = %01000000
CTRL_SHIFT_FLAG_CTRL  = %10000000
CTRL_SHIFT_FLAG_SHIFT = %01000000
CTRL_SHIFT_FLAG_LOWER = %00000000
DEBOUNCE_NUM_FRAMES   = 10

start:
.ifdef DEBUG
  lda #<wozmon_main
  sta $0206
  lda #>wozmon_main
  sta $0207
  cli ; for brk to work
.endif
  jsr init
  jmp main_loop

running_tick:
  lda select_fired
  beq @check_start
  lda #STATE_CONFIG
  sta switch_state
  lda #0
  sta select_fired
@check_start:
  lda start_fired
  beq @tick
  ; ignore, but clear the flag
  lda #0
  sta start_fired
@tick:
  jsr trm_tick
@done:
  rts

config_tick:
  lda select_fired
  beq @check_start
  sta cfg_select_fired
  lda #0
  sta select_fired
@check_start:
  lda start_fired
  beq @tick
  sta cfg_start_fired
  lda #0
  sta start_fired
@tick:
  jsr cfg_tick 
  lda #CONFIG_FLAG_EDITING
  bit cfg_config_flag
  bpl @done
  lda #STATE_RUNNING
  sta switch_state
@done:
  rts

main_loop:
  lda switch_state
  beq @check_kbd
  sta current_state
  cmp #STATE_RUNNING
  beq @switch_to_running
  jsr scr_cls
  jsr cfg_activate
  lda #0
  sta switch_state
  jmp @check_kbd
@switch_to_running:
  lda #0
  sta switch_state
  sta select_fired
  sta start_fired
  jsr scr_cls
  jsr trm_activate
@check_kbd:
  jsr inkbd
  lda current_state
  and #STATE_CONFIG
  bne @config
@running:
  jsr running_tick
  jmp @next_tick
@config:
  jsr config_tick
@next_tick:
  jmp main_loop

; called every vertical blank
vbi_handler:
; basic debouncing of presses for special keys.
; CONSOL Bits (active low):
;   2 - option
;   1 - select
;   0 - start
@check_select:
  lda CONSOL
  and #%00000010
  bne @select_up
@select_down:
  lda debounce_count_select
  bne @check_start ; debouncing
  lda #1
  sta select_fired
  lda #DEBOUNCE_NUM_FRAMES
  sta debounce_count_select
  jmp @check_start
@select_up:
  lda debounce_count_select
  beq @check_start
  dec debounce_count_select

@check_start:
  lda CONSOL
  and #%00000001
  bne @start_up
@start_down:
  lda debounce_count_start
  bne @check_option
  lda #1
  sta start_fired
  lda #DEBOUNCE_NUM_FRAMES
  sta debounce_count_start
  jmp @check_option
@start_debouncing:
  jmp @check_option
@start_up:
  lda debounce_count_start
  beq @check_option
  dec debounce_count_start

@check_option:
@done:
  jmp XITVBV ; hand control back to OS


set_vbi_handler:
  lda #7 ; deferred
  ldx #>vbi_handler
  ldy #<vbi_handler
  jsr SETVBV
  rts

init:
  jsr crc_make_table
  brk
  lda #CTRL_SHIFT_FLAG_LOWER 
  sta ctrl_shift_lock_flag

  ; disable the OS screen editor
  ldx #0
  lda #CLOSE
  sta ICCOM,x
  jsr CIOV

  ; disable cursor
  lda #1
  sta CRSINH

  lda SAVMSC
  sta SCR_PTR_LO
  lda SAVMSC+1
  sta SCR_PTR_HI

  ; init and clear the screen
  ldx #6
  lda #0
  sta ICCOM,x
  jsr CIOV

  lda #0
  sta debounce_count_select
  sta debounce_count_start

  jsr set_vbi_handler
  jsr li_init_context
  jsr ta_init_context
  jsr cfg_init
  jsr trm_init

  lda #STATE_CONFIG
  sta switch_state

  jsr init_ui

  rts

; Keyboard behavior described in the Atari OS User Manual Page 47
inkbd:
  lda CH
  cmp #$ff
  bne @key_pressed

  lda #0
  sta g_kbd_key_pressed
  jmp @done

@key_pressed:
  sta g_kbdcode_raw  ; with ctrl/shift bits
  lda #$ff
  sta CH
  sta g_kbd_key_pressed
  ; first let's handle ctrl-lock and shift-lock
  ; presses
  lda g_kbdcode_raw
  cmp #$3c
  beq @lock_lower
  cmp #$bc
  beq @lock_ctrl
  cmp #$7c
  beq @lock_shift
  bne @not_a_lock_key
@lock_lower:
  lda #CTRL_SHIFT_FLAG_LOWER 
  sta ctrl_shift_lock_flag
  jmp @done
@lock_ctrl:
  lda #CTRL_SHIFT_FLAG_CTRL  
  sta ctrl_shift_lock_flag
  jmp @done
@lock_shift:
  lda #CTRL_SHIFT_FLAG_SHIFT 
  sta ctrl_shift_lock_flag
  jmp @done

@not_a_lock_key:
  lda g_kbdcode_raw
  and #%00111111
  sta g_kbdcode_raw_stripped ; stripped of ctrl/shift bits

  lda g_kbdcode_raw
  ; Bit 7 is 1 if ctrl key pressed
  ; Bit 6 is 1 if shift key pressed
  and #%11000000
  beq @lower_case
  cmp #%11000000
  beq @done ; ignore if ctrl+shift

  and #%10000000
  bne @control_pressed

  lda g_kbdcode_raw
  and #%01000000
  bne @shift_pressed

@lower_case:
  ; if here, lower case, but we need to check
  ; ctrl lock or shift lock are on
  ldx g_kbdcode_raw_stripped
  lda kbd_unmodified,x
  sta g_kbdcode_atascii

  ; ignore for non-alphas according to spec (OS User's manual)
  cmp #$61 ;#'A'
  bcc @done

  cmp #$7b ;#'['
  bcs @done

  ; now check to see if CTRL lock
  lda ctrl_shift_lock_flag
  and #CTRL_SHIFT_FLAG_CTRL
  bne @control_locked

  lda ctrl_shift_lock_flag
  and #CTRL_SHIFT_FLAG_SHIFT
  bne @shift_locked
  jmp @done

@shift_locked:
  ldx g_kbdcode_raw_stripped
  lda kbd_shifted,x
  sta g_kbdcode_atascii
  jmp @done
@control_locked:
  ldx g_kbdcode_raw_stripped
  lda kbd_ctrld,x
  sta g_kbdcode_atascii
  jmp @done
@shift_pressed:
  ; if here, shift pressed
  ldx g_kbdcode_raw_stripped
  lda kbd_shifted,x
  sta g_kbdcode_atascii
  jmp @done
@control_pressed:
  ldx g_kbdcode_raw_stripped
  lda kbd_ctrld,x
  sta g_kbdcode_atascii
@done:
  rts

; inputs:
;   x - theme number
set_theme:
  ldx current_theme
  lda themes_bg,x
  sta COLOR2
  lda themes_fg,x
  sta COLOR1
  rts

next_theme:
  ldx current_theme
  inx
  cpx #(themes_fg_end-themes_fg)
  bcc @nowrap
  ldx #0
@nowrap:
  stx current_theme
@do_it:
  jsr set_theme
  stx current_theme
  rts

init_ui:
  ldx #0
  stx current_theme
  jsr set_theme
  rts


ctrl_shift_lock_flag:  .byte 0
debounce_count_select: .byte 0
debounce_count_start:  .byte 0
select_fired:          .byte 0
start_fired:           .byte 0
current_theme:         .byte 0
current_state:         .byte 0
switch_state:          .byte 0

themes_bg:
  .byte $be,$02,$c2,$22
themes_bg_end:
themes_fg:
  .byte $b2,$0e,$ce,$2e
themes_fg_end:

