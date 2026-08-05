; The output scrollback area. Starts writing at the top of the area
; and scrolls upwards when it reaches the bottom.
;

.ifndef TERM_OUTPUT_INC
TERM_OUTPUT_INC = 1

TO_HEIGHT = 21

.global to_init
.global to_append_char
.global to_append_lines
.global to_println
.global to_repaint
.global to_clear_and_home


.endif
