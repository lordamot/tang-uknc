//
// uknc.h
//
// USB HID to AGAT9 translation table
//

#define MISS          (0)
#define MATRIX(a,b)   (b*16+a)

static const unsigned char keymap_agat9[] = {
  MISS,         // 00: NoEvent
  MISS,         // 01: Overrun Error
  MISS,         // 02: POST fail
  MISS,         // 03: ErrorUndefined

  // characters
  0x41 , // 04: a
  0x42 , // 05: b
  0x43 , // 06: c
  0x44 , // 07: d
  0x45 , // 08: e
  0x46 , // 09: f
  0x47 , // 0a: g
  0x48 , // 0b: h
  0x49 , // 0c: i
  0x4A , // 0d: j
  0x4B , // 0e: k
  0x4C , // 0f: l
  0x4D , // 10: m
  0x4E , // 11: n
  0x4F , // 12: o
  0x50 , // 13: p
  0x51 , // 14: q
  0x52 , // 15: r
  0x53 , // 16: s
  0x54 , // 17: t
  0x55 , // 18: u
  0x56 , // 19: v
  0x57 , // 1a: w
  0x58 , // 1b: x
  0x59 , // 1c: y
  0x5A , // 1d: z

  // top number key row
  0x31 , // 1e: 1
  0x32 , // 1f: 2
  0x33 , // 20: 3
  0x34 , // 21: 4
  0x35 , // 22: 5
  0x36 , // 23: 6
  0x37 , // 24: 7
  0x38 , // 25: 8
  0x39 , // 26: 9
  0x30 , // 27: 0

  // other keys
  0x0D , // 28: return
  0x1B , // 29: esc
  0x08 , // 2a: backspace
  MISS , // 2b: tab
  0x20 , // 2c: space

  0x2D , // 2d: -
  0x3D , // 2e: =
  0x5B , // 2f: [
  0x5D , // 30: ]
  0x5C , // 31: backslash
  MISS , // 32: EUR-1
  0x3A , // 33: ;
  0x27 , // 34: '
  0x3B , // 35: `(~)
  0x2C , // 36: ,
  0x2E , // 37: .
  0x2F , // 38: /
  0x61 , // 39: caps lock rus/lat

  // function keys
  0x04 , // 3a: F1 - K1
  0x05 , // 3b: F2 - K2
  0x06 , // 3c: F3 - K3
  MISS , // 3d: F4 - K4
  MISS , // 3e: F5 - K5
  MISS , // 3f: F6 - HELP (POM)
  MISS , // 40: F7 - SET (UST)
  MISS , // 41: F8 - EXEC (ISP)
  MISS , // 42: F9 - RESET (SBROS)
  MISS , // 43: F10 - STOP
  MISS , // 44: F11
  MISS , // 45: F12

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
  0x15 , // 4f: right
  0x08 , // 50: left
  0x1A , // 51: down
  0x19 , // 52: up

  MISS,         // 53: Num Lock

  // keypad
  0x2F, // 54: KP /
  0x03, // 55: KP *
  0x2D, // 56: KP -
  0x3D, // 57: KP +
  0x0D, // 58: KP Enter
  0x1D , // 59: KP 1
  0x1E , // 5a: KP 2
  0x1F , // 5b: KP 3
  0x13 , // 5c: KP 4
  0x14 , // 5d: KP 5
  0x1C , // 5e: KP 6
  0x10 , // 5f: KP 7
  0x11 , // 60: KP 8
  0x12 , // 61: KP 9
  0x01 , // 62: KP 0
  0x02 , // 63: KP .
  MISS  // 64: EUR-2
};

static const unsigned char modifier_agat9[] = {
  /* usb modifer bits:
     0     1      2    3    4     5      6    7
     LCTRL LSHIFT LALT LGUI RCTRL RSHIFT RALT RGUI
  */

  0x5E , // ctrl - UPR
  0x5F , // lshift
  0x60 , // alt - ALF
  MISS ,
  0x5E , // ctrl (right)
  0x5F , // rshift
  0x60 , // alt (right) - GRAF
  MISS
};
