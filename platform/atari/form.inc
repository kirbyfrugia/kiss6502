.ifndef FORM_INC
FORM_INC = 1

.global fm_set_context
.global fm_draw_all
.global fm_handle_key

.struct Form
  first  .byte ; index of the tab's first field in the field table
  count  .byte ; how many fields the tab has
  focus  .byte ; position of the focused field, counted from first
.endstruct

FIELD_SELECT = 0
FIELD_TEXT   = 1
FIELD_BUTTON = 2

FIELD_FOCUSED = %10000000

HINT_GAP   = 1
HINT_WIDTH = 2

KEY_SHIFT_TAB = $6c
KEY_CTRL_UP   = $8e
KEY_CTRL_DOWN = $8f

.endif
