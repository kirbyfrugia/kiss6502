.setcpu "6502"

.include "globals.inc"

.segment "ZEROPAGE"
ZPB0:               .res 1
ZPB1:               .res 1
ZPB2:               .res 1
ZPB3:               .res 1
ZPB4:               .res 1
ZPB5:               .res 1
CMDDATA0:           .res 1
CMDDATA1:           .res 1
CMDDATA2:           .res 1
CMDDATA3:           .res 1
CMDDATA4:           .res 1
CMDDATA5:           .res 1
CMDDATA6:           .res 1
CMDDATA7:           .res 1

g_temp_scr_ptr_lo:  .res 1
g_temp_scr_ptr_hi:  .res 1
g_temp_data_ptr_lo: .res 1
g_temp_data_ptr_hi: .res 1

g_rx_buf_num_chars:      .res 1

.segment "CODE"

g_copy_buffer40:         .res 40
g_copy_buffer40_size:    .res 1
g_rx_buf:                .res 256
g_disp_buf:              .res G_DISP_BUF_MAX_LINES*TERMINAL_WIDTH
g_disp_buf_num_lines:    .res 1 ; max of G_DISP_BUF_MAX_LINES
g_kbd_key_pressed:       .res 1 ; nonzero if pressed
g_kbdcode_raw:           .res 1 ; raw keyboard code currently pressed
g_kbdcode_raw_stripped:  .res 1 ; raw minus ctrl bits
g_kbdcode_atascii:       .res 1 ; keyboard code in atascii
