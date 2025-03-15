//
// uknc.h
//
// USB HID to UKNC translation table
//

#define MISS          (0)
#define MATRIX(a,b)   (b*16+a)

static const unsigned char keymap_uknc[] = {
  MISS,         // 00: NoEvent
  MISS,         // 01: Overrun Error
  MISS,         // 02: POST fail
  MISS,         // 03: ErrorUndefined

  // characters
  072 , // 04: a
  076 , // 05: b
  050 , // 06: c
  057 , // 07: d
  033 , // 08: e
  047 , // 09: f
  055 , // 0a: g
  0156, // 0b: h
  073 , // 0c: i
  027 , // 0d: j
  052 , // 0e: k
  056 , // 0f: l
  0112, // 10: m
  054 , // 11: n
  075 , // 12: o
  053 , // 13: p
  067 , // 14: q
  074 , // 15: r
  0111, // 16: s
  0114, // 17: t
  051 , // 18: u
  0137, // 19: v
  071 , // 1a: w
  0115, // 1b: x
  070 , // 1c: y
  0157, // 1d: z

  // top number key row
  030 , // 1e: 1
  031 , // 1f: 2
  032 , // 20: 3
  013 , // 21: 4
  034 , // 22: 5
  035 , // 23: 6
  016 , // 24: 7
  017 , // 25: 8
  0177, // 26: 9
  0176, // 27: 0

  // other keys
  0153, // 28: return
  06  , // 29: esc
  0132, // 2a: backspace
  026 , // 2b: tab
  0113, // 2c: space

  025 , // 2d: -
  0175, // 2e: =
  036 , // 2f: [
  037 , // 30: ]
  0136, // 31: backslash
  077 , // 32: EUR-1
  07  , // 33: ;
  05  , // 34: '
  077 , // 35: `(~)
  0117, // 36: ,
  0135, // 37: .
  0173, // 38: /
  0107, // 39: caps lock FIX

  // function keys
  010 , // 3a: F1 - K1
  011 , // 3b: F2 - K2
  012 , // 3c: F3 - K3
  014 , // 3d: F4 - K4
  015 , // 3e: F5 - K5
  0172, // 3f: F6 - HELP (POM)
  0152, // 40: F7 - SET (UST)
  0151, // 41: F8 - EXEC (ISP)
  0171, // 42: F9 - RESET (SBROS)
  04  , // 43: F10 - STOP
  MISS, // 44: F11
  MISS, // 45: F12

  MISS, // 46: PrtScr -> KP-(
  MISS, // 47: Scroll Lock
  MISS, // 48: Pause 
  MISS, // 49: Insert
  MISS, // 4a: Home
  MISS, // 4b: PageUp -> HELP
  MISS, // 4c: Delete
  MISS, // 4d: End -> KP-)
  MISS, // 4e: PageDown -> UNDO

  // cursor keys
  0133, // 4f: right
  0116, // 50: left
  0134, // 51: down
  0154, // 52: up

  MISS,         // 53: Num Lock

  // keypad
  0173, // 54: KP /
  0174, // 55: KP *
  025 , // 56: KP -
  0131, // 57: KP +
  0166, // 58: KP Enter
  0127, // 59: KP 1
  0147, // 5a: KP 2
  0167, // 5b: KP 3
  0130, // 5c: KP 4
  0150, // 5d: KP 5
  0170, // 5e: KP 6
  0125, // 5f: KP 7
  0145, // 60: KP 8
  0165, // 61: KP 9
  0126, // 62: KP 0
  0146, // 63: KP .
  MISS  // 64: EUR-2
};

static const unsigned char modifier_uknc[] = {
  /* usb modifer bits:
     0     1      2    3    4     5      6    7
     LCTRL LSHIFT LALT LGUI RCTRL RSHIFT RALT RGUI
  */

  046 , // ctrl - UPR
  0105, // lshift
  0106, // alt - ALF
  MISS,
  046 , // ctrl (right)
  0105, // rshift
  0172, // alt (right) - GRAF
  MISS
};
