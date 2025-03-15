//
// uneon.h
//
// USB HID to Souyz Neon PK 11/16 key matrix translation table
//

#define MISS          (0)
#define MATRIX(a,b)   (b*16+a)

static const unsigned char keymap_uneon[] = {
  MISS,         // 00: NoEvent
  MISS,         // 01: Overrun Error
  MISS,         // 02: POST fail
  MISS,         // 03: ErrorUndefined

  // characters
  MATRIX( 5,3), // 04: a
  MATRIX( 9,3), // 05: b
  MATRIX( 3,2), // 06: c
  MATRIX(10,2), // 07: d
  MATRIX( 6,1), // 08: e
  MATRIX( 2,2), // 09: f
  MATRIX( 8,2), // 0a: g
  MATRIX( 9,6), // 0b: h
  MATRIX( 6,3), // 0c: i
  MATRIX( 2,1), // 0d: j
  MATRIX( 5,2), // 0e: k
  MATRIX( 9,2), // 0f: l
  MATRIX( 5,4), // 10: m
  MATRIX( 7,2), // 11: n
  MATRIX( 8,3), // 12: o
  MATRIX( 6,2), // 13: p
  MATRIX( 2,3), // 14: q
  MATRIX( 7,3), // 15: r
  MATRIX( 4,4), // 16: s
  MATRIX( 7,4), // 17: t
  MATRIX( 4,2), // 18: u
  MATRIX(10,5), // 19: v
  MATRIX( 4,3), // 1a: w
  MATRIX( 8,4), // 1b: x
  MATRIX( 3,3), // 1c: y
  MATRIX(10,6), // 1d: z

  // top number key row
  MATRIX( 3,1), // 1e: 1
  MATRIX( 4,1), // 1f: 2
  MATRIX( 5,1), // 20: 3
  MATRIX( 6,0), // 21: 4
  MATRIX( 7,1), // 22: 5
  MATRIX( 8,1), // 23: 6
  MATRIX( 9,0), // 24: 7
  MATRIX(10,0), // 25: 8
  MATRIX(10,7), // 26: 9
  MATRIX( 9,7), // 27: 0

  // other keys
  MATRIX( 6,6), // 28: return
  MATRIX( 1,0), // 29: esc
  MATRIX( 5,5), // 2a: backspace
  MATRIX( 1,1), // 2b: tab
  MATRIX( 6,4), // 2c: space

  MATRIX( 8,6), // 2d: -
  MATRIX( 8,7), // 2e: =
  MATRIX( 9,1), // 2f: [
  MATRIX(10,1), // 30: ]
  MATRIX( 9,5), // 31: backslash
  MISS,         // 32: EUR-1
  MATRIX( 2,0), // 33: ;
  MATRIX( 6,7), // 34: '
  MATRIX(10,3), // 35: `
  MATRIX(10,4), // 36: ,
  MATRIX( 8,5), // 37: .
  MATRIX( 7,7), // 38: /
  MATRIX( 1,4), // 39: caps lock

  // function keys
  MATRIX( 3,0), // 3a: F1 - K1
  MATRIX( 4,0), // 3b: F2 - K2
  MATRIX( 5,0), // 3c: F3 - K3
  MATRIX( 7,0), // 3d: F4 - K4
  MATRIX( 8,0), // 3e: F5 - K5
  MATRIX( 5,7), // 3f: F6 - HELP (POM)
  MATRIX( 5,6), // 40: F7 - SET (UST)
  MATRIX( 4,6), // 41: F8 - EXEC (ISP)
  MATRIX( 4,7), // 42: F9 - RESET (SBROS)
  MATRIX( 0,2), // 43: F10 - STOP
  MISS, //MATRIX(10,0), // 44: F11
  MISS, //MATRIX(10,0), // 45: F12

  MISS, //MATRIX(13,0), // 46: PrtScr -> KP-(
  MISS,         // 47: Scroll Lock
  MISS,         // 48: Pause
  MATRIX( 3,4), //MATRIX(11,3), // 49: Insert
  MISS, //MATRIX(12,2), // 4a: Home
  MISS, //MATRIX(11,0), // 4b: PageUp -> HELP
  MISS, //MATRIX(11,2), // 4c: Delete
  MISS, //MATRIX(13,1), // 4d: End -> KP-)
  MISS, //MATRIX(12,0), // 4e: PageDown -> UNDO

  // cursor keys
  MATRIX( 6,5), // 4f: right
  MATRIX( 9,4), // 50: left
  MATRIX( 7,5), // 51: down
  MATRIX( 7,6), // 52: up

  MISS,         // 53: Num Lock

  // keypad
  MISS, //MATRIX(14,0), // 54: KP /
  MATRIX(14,1), // 55: KP *
  MATRIX( 0,1), // 56: KP -
  MATRIX( 4,5), // 57: KP +
  MATRIX( 1,7), // 58: KP Enter
  MATRIX( 2,5), // 59: KP 1
  MATRIX( 2,6), // 5a: KP 2
  MATRIX( 2,7), // 5b: KP 3
  MATRIX( 3,5), // 5c: KP 4
  MATRIX( 3,6), // 5d: KP 5
  MATRIX( 3,7), // 5e: KP 6
  MATRIX( 0,5), // 5f: KP 7
  MATRIX( 0,6), // 60: KP 8
  MATRIX( 0,7), // 61: KP 9
  MATRIX( 1,5), // 62: KP 0
  MATRIX( 1,6), // 63: KP .
  MISS //MATRIX( 4,6), // 64: EUR-2
};

static const unsigned char modifier_uneon[] = {
  /* usb modifer bits:
     0     1      2    3    4     5      6    7
     LCTRL LSHIFT LALT LGUI RCTRL RSHIFT RALT RGUI
  */

  MATRIX( 1,2), // ctrl - UPR
  MATRIX( 0,4), // lshift
  MATRIX( 2,4), // alt - FIX
  MISS,
  MATRIX( 1,2), // ctrl (right)
  MATRIX( 0,4), // rshift
  MATRIX( 1,3), // alt (right) - GRAF
  MISS
};
