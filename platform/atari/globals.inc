.ifndef GLOBALS_INC
GLOBALS_INC = 1

.globalzp ZPB0
.globalzp ZPB1
.globalzp ZPB2
.globalzp ZPB3
.globalzp ZPB4
.globalzp ZPB5
.globalzp CMDDATA0
.globalzp CMDDATA1
.globalzp CMDDATA2
.globalzp CMDDATA3
.globalzp CMDDATA4
.globalzp CMDDATA5
.globalzp CMDDATA6
.globalzp CMDDATA7
.globalzp g_temp_scr_ptr_lo
.globalzp g_temp_scr_ptr_hi
.globalzp g_temp_data_ptr_lo
.globalzp g_temp_data_ptr_hi

.global   g_copy_buffer40 
.global   g_copy_buffer40_size

.global   g_kbd_key_pressed
.global   g_kbdcode_raw
.global   g_kbdcode_raw_stripped
.global   g_kbdcode_atascii

.global   g_rx_buf
.global   g_disp_buf
.global   g_disp_buf_num_lines
.globalzp g_rx_buf_num_chars

G_DISP_BUF_MAX_LINES = 12
TERMINAL_WIDTH       = 38

.endif
