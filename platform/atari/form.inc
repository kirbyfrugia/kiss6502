.ifndef FORM_INC
FORM_INC = 1

.global fm_set_context
.global fm_draw_all
.global fm_handle_key
.global fm_action

.struct Form
  first  .byte ; index of the tab's first field in the field table
  count  .byte ; how many fields the tab has
  focus  .byte ; position of the focused field, counted from first
.endstruct

FIELD_SELECT = 0
FIELD_TEXT   = 1
FIELD_BUTTON = 2

FIELD_FOCUSED = %10000000

; allowed chars for a text field
CHAR_ALL   = %10000000
CHAR_ALPHA = %01000000
CHAR_DASH  = %00100000
CHAR_SPACE = %00010000
CHAR_COMMA = %00001000
CHAR_DIGIT = %00000100

; modifications that can be automatically made to user input
INPUT_UPPER = %10000000

FM_ACTION_NONE = 0

HINT_GAP   = 1
HINT_WIDTH = 2

KEY_SHIFT_TAB    = $6c
KEY_CTRL_LEFT    = $86
KEY_CTRL_RIGHT   = $87
KEY_CTRL_UP      = $8e
KEY_CTRL_DOWN    = $8f
KEY_CTRL_DELETE  = $b4
KEY_CTRL_INSERT  = $b7

.endif
