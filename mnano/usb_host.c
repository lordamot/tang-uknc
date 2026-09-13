// usb_host.c

#include <FreeRTOS.h>
#include <queue.h>
#include <hardware/bl616.h>

#include "usb.h"
#include "usbh_core.h"
#include "usbh_hid.h"
#include "bflb_gpio.h"
#include "hidparser.h"
#include "hid.h"

#include "sysctrl.h"   // for core_id

// Enabling RATE_CHECK will count the number of USB events per
// device and do an estimate in the effective event rate.
// #define RATE_CHECK

#include "menu.h"    // for event codes

// queue to send messages to OSD thread
extern QueueHandle_t xQueue;

#define MAX_REPORT_SIZE   8
#define XBOX_REPORT_SIZE 20

#define STATE_NONE      0 
#define STATE_DETECTED  1 
#define STATE_RUNNING   2
#define STATE_FAILED    3

extern struct bflb_device_s *gpio;

static struct usb_config {
  osd_t *osd;  
  spi_t *spi;
  unsigned js_map;   // map of joysticks
  
  struct xbox_info_S {
    int index;
    int state;
    struct usbh_hid *class;
    uint8_t *buffer;
    struct usb_config *usb;
    SemaphoreHandle_t sem;
    TaskHandle_t task_handle;    
    unsigned char last_state;
    unsigned char js_index;
#ifdef RATE_CHECK
    TickType_t rate_start;
    unsigned long rate_events;
#endif    
  } xbox_info[CONFIG_USBHOST_MAX_XBOX_CLASS];
    
  struct hid_info_S {
    int index;
    int state;
    struct usbh_hid *class;
    uint8_t *buffer;
    int nbytes;
    hid_report_t report;
    struct usb_config *usb;
    SemaphoreHandle_t sem;
    TaskHandle_t task_handle;    
    volatile int stop;           // the stack says the device is gone: the thread exits
#ifdef RATE_CHECK
    TickType_t rate_start;
    unsigned long rate_events;
#endif    
    union {
      struct hid_kbd_state_S keyboard;
      struct hid_mouse_state_S mouse;
      struct hid_joystick_state_S joystick;
    };
  } hid_info[CONFIG_USBHOST_MAX_HID_CLASS];
} usb_config;
  
USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX uint8_t hid_buffer[CONFIG_USBHOST_MAX_HID_CLASS][MAX_REPORT_SIZE];
USB_NOCACHE_RAM_SECTION USB_MEM_ALIGNX uint8_t xbox_buffer[CONFIG_USBHOST_MAX_XBOX_CLASS][XBOX_REPORT_SIZE];

// include the keyboard mappings
#include "atari_st.h"
#include "c64.h"
#include "uneon.h"
#include "amiga.h"
#include "uknc.h"
#include "agat9.h"

const unsigned char *keymap[] = {
  NULL,             // id 0: unknown core
  keymap_atarist,   // id 1: atari st
  keymap_c64,       // id 2: c64
  keymap_uneon,     // id 3: UNOEN
  keymap_amiga,     // id 4: amiga
  keymap_uknc,      // id 5: uknc
  keymap_agat9      // id 6: agat9
};

const unsigned char *modifier[] = {
  NULL,             // id 0: unknown core
  modifier_atarist, // id 1: atari st
  modifier_c64,     // id 2: c64
  modifier_uneon,   // id 3: UNEON
  modifier_amiga,   // id 4: amiga
  modifier_uknc,    // id 5: uknc
  modifier_agat9    // id 6: agat9
};

void kbd_tx(spi_t *spi, unsigned char byte) {
  printf("KBD: %02x\r\n", byte);

  spi_begin(spi);
  spi_tx_u08(spi, SPI_TARGET_HID);
  spi_tx_u08(spi, SPI_HID_KEYBOARD);
  spi_tx_u08(spi, byte);
  spi_end(spi);
}

// The УКНЦ's keyboard is a scanned 16-row x 8-column matrix and its
// controller reports rows, not keys: a scan code is {column, row}, a
// press is reported only for the first key to go down in a row, and the
// release code is 0x80 | row, sent once the whole row is up again
// (UKNCBTL, Board.cpp, the keyboard scanner in SystemFrame).  The
// machine's firmware is written to that - one press, then one release,
// per row, and its autorepeat runs until the releases balance the
// presses - and both Shift keys (0105) share row 5 with the numeric
// keypad.  Forwarding every USB press and release as its own code broke
// it: a second key going down in a held row was a second press, its
// release said the row was up while the first key was still down, and
// the first key's release then arrived as the very same byte, which
// xm2-01.v took as no change at all.  Shift plus a key of the same row
// so left the firmware with a row it believed still held, and it
// autorepeated that key until another Shift press and release put the
// row right (Sep 2026).  So the matrix is tracked here, and the machine
// is handed a legal stream.  Not the machine's own, quite: on its
// keyboard the next key down in a held row is simply never reported,
// and a PC typist rolls from A to Backspace (both row 10) all day - so
// rollover inside a row is sent as a release of the row and a new
// press, and the older keys of that row are forgotten - the machine now
// believes the row is the new key, and would autorepeat it until the
// older ones were up if their releases were waited for.  Two keys with
// one code (the Shifts) are one key held twice: the row is released when
// the second is up.
// A press the OSD ate, or a key the machine lacks (MISS), is not
// tracked, so its release is dropped here rather than sent for a row
// that was never pressed; a release of a tracked key is sent even while
// the OSD is up, since the core heard the press.
static void kbd_tx_uknc_byte(spi_t *spi, unsigned char byte) {
  // hid.v holds one byte with no strobe and xm2-01.v takes a change of
  // it; consecutive bytes are kept 2 ms apart so that each is seen -
  // xm2-01.v queues them since Sep 2026, an older bitstream does not.
  static TickType_t last_tx;
  TickType_t gap = pdMS_TO_TICKS(2) ? pdMS_TO_TICKS(2) : 1;
  if(xTaskGetTickCount() - last_tx < gap) vTaskDelay(gap);
  kbd_tx(spi, byte);
  last_tx = xTaskGetTickCount();
}

static void kbd_tx_uknc(spi_t *spi, unsigned char hid, unsigned char code, char pressed) {
  static unsigned char held[32];     // HID usages forwarded as pressed (modifiers as 0xe0..0xe7)
  static unsigned char rows[16];     // keys the machine believes down, per matrix row
  static unsigned char code_of[16];  // the code it believes the row is held by
  static unsigned char gen[16];      // bumped when a rollover makes it forget the row's older keys
  static unsigned char key_gen[256]; // the row's generation when each key was forwarded
  unsigned char row = code & 0x0f;

  if(pressed) {
    if(osd_is_visible(usb_config.osd) || !code) return;
    if(held[hid >> 3] & (1 << (hid & 7))) return;
    held[hid >> 3] |= 1 << (hid & 7);
    if(rows[row] && code != code_of[row]) {   // rollover within the row: the machine gets a
      kbd_tx_uknc_byte(spi, 0x80 | row);      // release and a new press, and the older keys
      gen[row]++;                             // are forgotten - their releases mean nothing now
      rows[row] = 0;
    }
    if(!rows[row]) {                          // a second Shift is the same code: counted, not sent
      kbd_tx_uknc_byte(spi, code);
      code_of[row] = code;
    }
    rows[row]++;
    key_gen[hid] = gen[row];
  } else {
    if(!(held[hid >> 3] & (1 << (hid & 7)))) return;
    held[hid >> 3] &= ~(1 << (hid & 7));
    if(key_gen[hid] != gen[row]) return;      // forgotten in a rollover
    if(--rows[row] == 0) kbd_tx_uknc_byte(spi, 0x80 | row);
  }
}

// one key event - a modifier bit or a key slot of the report - to the core
static void kbd_key(spi_t *spi, unsigned char hid, unsigned char code, char pressed) {
  if(core_id == CORE_ID_UKNC) kbd_tx_uknc(spi, hid, code, pressed);
  else                        kbd_tx(spi, pressed ? code : (0x80 | code));
}

// the c64 core can use the numerical pad on the keyboard to
// emulate a joystick
void kbd_num2joy(spi_t *spi, char state, unsigned char code) {
  static unsigned char kbd_joy_state = 0;
  static unsigned char kbd_joy_state_last = 0;
  
  // mapping:
  // keycode 5a = KP 2 = down
  // keycode 5c = KP 4 = left
  // keycode 5e = KP 6 = right
  // keycode 60 = KP 8 = up
  // keycode 62 = KP 0 = fire
  // keycode 63 = KP . and delete = 2nd trigger button
  // keycode 44 = F11 = Restore Key
  // keycode 4b = Page Up = Tape Play Key
  
  if(state == 0)
    // start parsing a new set of keys
    kbd_joy_state = 0;
  else if(state == 1) {
    // collect key/btn states
    if(code == 0x5e) kbd_joy_state |= 0x01;
    if(code == 0x5c) kbd_joy_state |= 0x02;
    if(code == 0x5a) kbd_joy_state |= 0x04;
    if(code == 0x60) kbd_joy_state |= 0x08;
    if(code == 0x62) kbd_joy_state |= 0x10;
    if(code == 0x63) kbd_joy_state |= 0x20;
    if(code == 0x44) kbd_joy_state |= 0x40;
    if(code == 0x4b) kbd_joy_state |= 0x80;
  } else if(state == 2) {
    // submit if state has changed
    if(kbd_joy_state != kbd_joy_state_last) {
      
      printf("KP Joy: %02x\r\n", kbd_joy_state);
  
      spi_begin(spi);
      spi_tx_u08(spi, SPI_TARGET_HID);
      spi_tx_u08(spi, SPI_HID_JOYSTICK);
      spi_tx_u08(spi, 0x80);  // report this as joystick 0x80 as js0-x are USB joysticks
      spi_tx_u08(spi, kbd_joy_state);
      spi_end(spi);
      
      kbd_joy_state_last = kbd_joy_state;
    }
  }
}
  
void kbd_parse(spi_t *spi, hid_report_t *report, struct hid_kbd_state_S *state,
	       const unsigned char *buffer, int nbytes) {
  // we expect boot mode packets which are exactly 8 bytes long
  if(nbytes != 8) return;
  
  // check if modifier have changed
  // (the UKNC path sees modifier changes under the OSD too: it drops the
  // presses itself and needs the releases, see kbd_tx_uknc)
  if((buffer[0] != state->last_report[0]) &&
     (!osd_is_visible(usb_config.osd) || core_id == CORE_ID_UKNC)) {
    for(int i=0;i<8;i++) {
      if(modifier[core_id][i]) {      
	// modifier released?
	if((state->last_report[0] & (1<<i)) && !(buffer[0] & (1<<i)))
	  kbd_key(spi, 0xe0 + i, modifier[core_id][i], 0);
	// modifier pressed?
	if(!(state->last_report[0] & (1<<i)) && (buffer[0] & (1<<i)))
	  kbd_key(spi, 0xe0 + i, modifier[core_id][i], 1);
      }
    }
  }

  // prepare for parsing numpad joystick
  if(core_id == CORE_ID_C64||core_id == CORE_ID_VIC20) kbd_num2joy(spi, 0, 0);
  
  // check if regular keys have changed
  for(int i=0;i<6;i++) {
    // C64 uses some keys for joystick emulation
    if(core_id == CORE_ID_C64||core_id == CORE_ID_VIC20) kbd_num2joy(spi, 1, buffer[2+i]);
    
    if(buffer[2+i] != state->last_report[2+i]) {
      // key released?
      if(state->last_report[2+i] &&
	 (!osd_is_visible(usb_config.osd) || core_id == CORE_ID_UKNC))
	kbd_key(spi, state->last_report[2+i], keymap[core_id][state->last_report[2+i]], 0);
      
      // key pressed?
      if(buffer[2+i])  {
	static unsigned long msg;
	msg = 0;

	// F12 toggles the OSD state. Therefore F12 must never be forwarded
	// to the core and thus must have an empty entry in the keymap. ESC
	// can only close the OSD.

	// Caution: Since the OSD closes on the press event, the following
	// release event will be sent into the core. The core should thus
	// cope with release events that did not have a press event before
	if(buffer[2+i] == 0x45 || (osd_is_visible(usb_config.osd) && buffer[2+i] == 0x29))
	  msg = osd_is_visible(usb_config.osd)?MENU_EVENT_HIDE:MENU_EVENT_SHOW;
	else {
	  if(!osd_is_visible(usb_config.osd))
	    kbd_key(spi, buffer[2+i], keymap[core_id][buffer[2+i]], 1);
	  else {
	    // check if cursor up/down or space has been pressed
	    if(buffer[2+i] == 0x51) msg = MENU_EVENT_DOWN;      
	    if(buffer[2+i] == 0x52) msg = MENU_EVENT_UP;
	    // cursor left/right step a value entry back and forth (Sep 2026)
	    if(buffer[2+i] == 0x50) msg = MENU_EVENT_LEFT;
	    if(buffer[2+i] == 0x4f) msg = MENU_EVENT_RIGHT;
	    if(buffer[2+i] == 0x4e) msg = MENU_EVENT_PGDOWN;      
	    if(buffer[2+i] == 0x4b) msg = MENU_EVENT_PGUP;
	    if((buffer[2+i] == 0x2c) || (buffer[2+i] == 0x28))
	      msg = MENU_EVENT_SELECT;
	  }
	}
	  
	if(msg)
	  xQueueSendToBackFromISR(xQueue, &msg,  ( TickType_t ) 0);
      }
    }    
  }
  memcpy(state->last_report, buffer, 8);

  // check if numpad joystick has changed state and send message if so
  if(core_id == CORE_ID_C64||core_id == CORE_ID_VIC20) kbd_num2joy(spi, 2, 0);
}

// collect bits from byte stream and assemble them into a signed word
static uint16_t collect_bits(const uint8_t *p, uint16_t offset, uint8_t size, bool is_signed) {
  // mask unused bits of first byte
  uint8_t mask = 0xff << (offset&7);
  uint8_t byte = offset/8;
  uint8_t bits = size;
  uint8_t shift = offset&7;
  
  //  iprintf("0 m:%x by:%d bi=%d sh=%d ->", mask, byte, bits, shift);
  uint16_t rval = (p[byte++] & mask) >> shift;
  mask = 0xff;
  shift = 8-shift;
  bits -= shift;
  
  // first byte already contained more bits than we need
  if(shift > size) {
    // mask unused bits
    rval &= (1<<size)-1;
  } else {
    // further bytes if required
    while(bits) {
      mask = (bits<8)?(0xff>>(8-bits)):0xff;
      rval += (p[byte++] & mask) << shift;
      shift += 8;
      bits -= (bits>8)?8:bits;
    }
  }
  
  if(is_signed) {
    // do sign expansion
    uint16_t sign_bit = 1<<(size-1);
    if(rval & sign_bit) {
      while(sign_bit) {
	rval |= sign_bit;
	sign_bit <<= 1;
      }
    }
  }
  
  return rval;
}

void mouse_parse(spi_t *spi, hid_report_t *report, struct hid_mouse_state_S *state,
		 const unsigned char *buffer, int nbytes) {
  // we expect at least three bytes:
  if(nbytes < 3) return;
  
  //  printf("MOUSE:"); for(int i=0;i<nbytes;i++) printf(" %02x", buffer[i]); printf("\r\n");
  
  // collect info about the two axes
  int a[2];
  for(int i=0;i<2;i++) {  
    bool is_signed = report->joystick_mouse.axis[i].logical.min > 
      report->joystick_mouse.axis[i].logical.max;

    a[i] = collect_bits(buffer, report->joystick_mouse.axis[i].offset, 
			report->joystick_mouse.axis[i].size, is_signed);
  }

  // ... and two buttons
  uint8_t btns = 0;
  for(int i=0;i<2;i++)
    if(buffer[report->joystick_mouse.button[i].byte_offset] & 
       report->joystick_mouse.button[i].bitmask)
      btns |= (1<<i);

  spi_begin(spi);
  spi_tx_u08(spi, SPI_TARGET_HID);
  spi_tx_u08(spi, SPI_HID_MOUSE);
  spi_tx_u08(spi, btns);
  spi_tx_u08(spi, a[0]);
  spi_tx_u08(spi, a[1]);
  spi_end(spi);
}

void joystick_parse(spi_t *spi, hid_report_t *report, struct hid_joystick_state_S *state,
		    const unsigned char *buffer, int nbytes) {
  //  printf("joystick: %d %02x %02x %02x %02x\r\n", nbytes,
  //  	 buffer[0]&0xff, buffer[1]&0xff, buffer[2]&0xff, buffer[3]&0xff);

  // collect info about the two axes
  int a[2];
  for(int i=0;i<2;i++) {  
    bool is_signed = report->joystick_mouse.axis[i].logical.min > 
      report->joystick_mouse.axis[i].logical.max;
    
    a[i] = collect_bits(buffer, report->joystick_mouse.axis[i].offset, 
			report->joystick_mouse.axis[i].size, is_signed);
  }

  // ... and four buttons
  unsigned char joy = 0;
  for(int i=0;i<4;i++)
    if(buffer[report->joystick_mouse.button[i].byte_offset] & 
       report->joystick_mouse.button[i].bitmask)
      joy |= (0x10<<i);
  
  // map directions to digital
  if(a[0] > 0xc0) joy |= 0x01;
  if(a[0] < 0x40) joy |= 0x02;
  if(a[1] > 0xc0) joy |= 0x04;
  if(a[1] < 0x40) joy |= 0x08;

  if(joy != state->last_state) {  
    state->last_state = joy;
    printf("JOY%d: %02x\r\n", state->js_index, joy);
  
    spi_begin(spi);
    spi_tx_u08(spi, SPI_TARGET_HID);
    spi_tx_u08(spi, SPI_HID_JOYSTICK);
    spi_tx_u08(spi, state->js_index);
    spi_tx_u08(spi, joy);
    spi_end(spi);
  }
}

void rii_joy_parse(struct hid_info_S *hid, const unsigned char *buffer) {
  unsigned char b = 0;
  if(buffer[0] == 0xcd && buffer[1] == 0x00) b = 0x10;      // cd == play/pause  -> center
  if(buffer[0] == 0xe9 && buffer[1] == 0x00) b = 0x08;      // e9 == V+          -> up
  if(buffer[0] == 0xea && buffer[1] == 0x00) b = 0x04;      // ea == V-          -> down
  if(buffer[0] == 0xb6 && buffer[1] == 0x00) b = 0x02;      // b6 == skip prev   -> left
  if(buffer[0] == 0xb5 && buffer[1] == 0x00) b = 0x01;      // b5 == skip next   -> right

  printf("RII Joy: %02x %02x\r\n", 0, b);
  
  spi_t *spi = hid->usb->spi;  
  spi_begin(spi);
  spi_tx_u08(spi, SPI_TARGET_HID);
  spi_tx_u08(spi, SPI_HID_JOYSTICK);
  spi_tx_u08(spi, 0);  // Rii joystick always report as joystick 0
  spi_tx_u08(spi, b);
  spi_end(spi);
}

void usbh_hid_callback(void *arg, int nbytes) {
  struct hid_info_S *hid = (struct hid_info_S *)arg;

  xSemaphoreGiveFromISR(hid->sem, NULL);
  hid->nbytes = nbytes;
}  

void usbh_xbox_callback(void *arg, int nbytes) {
  struct xbox_info_S *xbox = (struct xbox_info_S *)arg;
  if(nbytes == XBOX_REPORT_SIZE)
    xSemaphoreGiveFromISR(xbox->sem, NULL);
}  

// ---------------------------------------------------------------------
// HID devices come and go on the stack's say-so, not by polling.
//
// This used to look for /dev/inputN every 100 ms and start a reader
// thread when one appeared, delete it when it went.  A keyboard with a
// power-saving mode drops off the bus and re-attaches when it wakes,
// often within those 100 ms: the stack freed the old instance and made
// a new one under the same name, the poll saw "still there", and the
// old thread stayed blocked for ever on a URB the stack had killed
// without a callback (usb_hc_ehci.c, usbh_kill_urb) - a keyboard dead
// until a power cycle, its LED still on.  CherryUSB calls
// usbh_hid_run() at every attach and usbh_hid_stop() at every detach,
// so those are the events now, the thread exits on a flag, and its
// URB has a timeout so it can never block for ever (Sep 2026, seen on
// Tang Ultima; upstream FPGA-Companion made the same move in Feb 2026).
// ---------------------------------------------------------------------

static void usbh_hid_client_thread(void *argument);

void usbh_hid_run(struct usbh_hid *hid_class) {
  struct usb_config *usb = &usb_config;
  int i = hid_class->minor;
  if(i < 0 || i >= CONFIG_USBHOST_MAX_HID_CLASS) return;
  struct hid_info_S *hid = &usb->hid_info[i];

  if(hid->state != STATE_NONE) {
    // a re-attach before the last thread has gone: let it go first
    printf("HID %d: attach while %d still running\r\n", i, hid->state);
    for(int n=0;n<100 && hid->task_handle;n++) vTaskDelay(pdMS_TO_TICKS(1));
    hid->state = STATE_NONE;
  }

  hid->class = hid_class;
  hid->stop = 0;
  hid->nbytes = 0;
  printf("NEW HID %d\r\n", i);
  printf("Interval: %d\r\n", hid_class->intin ? hid_class->intin->bInterval : -1);
  printf("Interface %d\r\n", hid_class->intf);
  printf("  class %d\r\n", hid_class->hport->config.intf[hid_class->intf].altsetting[0].intf_desc.bInterfaceClass);
  printf("  subclass %d\r\n", hid_class->hport->config.intf[hid_class->intf].altsetting[0].intf_desc.bInterfaceSubClass);
  printf("  protocol %d\r\n", hid_class->hport->config.intf[hid_class->intf].altsetting[0].intf_desc.bInterfaceProtocol);

  // parse report descriptor ...
  if(!hid_class->intin ||
     !parse_report_descriptor(hid_class->report_desc, 128, &hid->report, NULL)) {
    printf("HID %d: unusable, ignored\r\n", i);
    hid->state = STATE_FAILED;   // parsing failed, don't use
    return;
  }

  if(hid->report.type == REPORT_TYPE_JOYSTICK) {
    // search for free joystick slot
    hid->joystick.js_index = 0;
    while(usb->js_map & (1<<hid->joystick.js_index))
      hid->joystick.js_index++;
    printf("  -> joystick %d\r\n", hid->joystick.js_index);
    usb->js_map |= 1<<hid->joystick.js_index;
  }

#ifdef RATE_CHECK
  hid->rate_start = xTaskGetTickCount();
  hid->rate_events = 0;
#endif

  hid->state = STATE_RUNNING;
  xTaskCreate(usbh_hid_client_thread, (char *)"hid_task", 1024,
	      hid, configMAX_PRIORITIES-3, &hid->task_handle);
}

void usbh_hid_stop(struct usbh_hid *hid_class) {
  struct usb_config *usb = &usb_config;
  int i = hid_class->minor;
  if(i < 0 || i >= CONFIG_USBHOST_MAX_HID_CLASS) return;
  struct hid_info_S *hid = &usb->hid_info[i];
  if(hid->class != hid_class) return;

  printf("HID LOST %d\r\n", i);
  hid->stop = 1;
  xSemaphoreGive(hid->sem);      // in case the thread waits on a URB the stack has killed

  // the stack frees hid_class the moment this returns, so the thread
  // must be out of it by then: it clears task_handle as it exits
  for(int n=0;n<1200 && hid->task_handle;n++) vTaskDelay(pdMS_TO_TICKS(1));   // past a control transfer's 500 ms
  if(hid->task_handle) printf("HID %d: thread did not stop\r\n", i);

  if(hid->state == STATE_RUNNING && hid->report.type == REPORT_TYPE_JOYSTICK) {
    printf("Joystick %d gone\r\n", hid->joystick.js_index);
    usb->js_map &= ~(1<<hid->joystick.js_index);
  }
  hid->class = NULL;
  hid->state = STATE_NONE;
}

static void usbh_update(struct usb_config *usb) {
  // check for active xbox devices
  for(int i=0;i<CONFIG_USBHOST_MAX_XBOX_CLASS;i++) {
    char *dev_str = "/dev/xboxX";
    dev_str[9] = '0' + i;
    usb->xbox_info[i].class = (struct usbh_hid *)usbh_find_class_instance(dev_str);
    
    if(usb->xbox_info[i].class && usb->xbox_info[i].state == STATE_NONE) {
      printf("NEW XBOX %d\r\n", i);

      printf("Interval: %d\r\n", usb->xbox_info[i].class->hport->config.intf[i].altsetting[0].ep[0].ep_desc.bInterval);
	 
      printf("Interface %d\r\n", usb->xbox_info[i].class->intf);
      printf("  class %d\r\n", usb->xbox_info[i].class->hport->config.intf[i].altsetting[0].intf_desc.bInterfaceClass);
      printf("  subclass %d\r\n", usb->xbox_info[i].class->hport->config.intf[i].altsetting[0].intf_desc.bInterfaceSubClass);
      printf("  protocol %d\r\n", usb->xbox_info[i].class->hport->config.intf[i].altsetting[0].intf_desc.bInterfaceProtocol);
	
      usb->xbox_info[i].state = STATE_DETECTED;
    }
    
    else if(!usb->xbox_info[i].class && usb->xbox_info[i].state != STATE_NONE) {
      printf("XBOX %d\r\n", i);
      vTaskDelete( usb->xbox_info[i].task_handle );
      usb->xbox_info[i].state = STATE_NONE;
      
      printf("Joystick %d gone\r\n", usb->xbox_info[i].js_index);
      usb->js_map &= ~(1<<usb->xbox_info[i].js_index);
    }
  }

  // check for number of mice and keyboards and update leds
  int mice = 0, keyboards = 0;  
  for(int i=0;i<CONFIG_USBHOST_MAX_HID_CLASS;i++) {
    if(usb->hid_info[i].state == STATE_RUNNING) {
      if(usb->hid_info[i].report.type == REPORT_TYPE_MOUSE)    mice++;
      if(usb->hid_info[i].report.type == REPORT_TYPE_KEYBOARD) keyboards++;      
    }
  }

  extern void set_led(int pin, int on);
  set_led(GPIO_PIN_27, mice);
  set_led(GPIO_PIN_28, keyboards);

  // The UKNC core's Kakave+ mouse register answers "who are you" with a
  // PS/2 mouse only while one is attached (kakave.v, sysctrl 'M'); tell
  // it when that changes.  The static starts at -1 so the first pass
  // after every MCU start sends the state whatever the FPGA holds.
  static int mice_last = -1;
  if(core_id == CORE_ID_UKNC && mice != mice_last) {
    mice_last = mice;
    sys_set_val(usb->spi, 'M', mice ? 1 : 0);
  }
}

static void hid_parse(struct hid_info_S *hid) {
#if 0
  USB_LOG_RAW("HID%d: ", hid->index);
  
  // just dump the report
  for (size_t i = 0; i < hid->nbytes; i++) 
    USB_LOG_RAW("0x%02x ", hid->buffer[i]);
  USB_LOG_RAW("\r\n");
#endif
  
  // the following is a hack for the Rii keyboard/touch combos to use the
  // left top multimedia pad as a joystick. These special keys are sent
  // via the mouse/touchpad part
  if(hid->report.report_id_present &&
     hid->report.type == REPORT_TYPE_MOUSE &&
     hid->nbytes == 3 &&
     hid->buffer[0] != hid->report.report_id) {
    rii_joy_parse(hid, hid->buffer+1);
    return;
  }
  
  // check and skip report id if present
  unsigned char *buffer = hid->buffer;
  if(hid->report.report_id_present) {
    if(!hid->nbytes || (buffer[0] != hid->report.report_id))
      return;
    
    // skip report id
    buffer++; hid->nbytes--;
  }
  
  if(hid->nbytes == hid->report.report_size) {
    if(hid->report.type == REPORT_TYPE_KEYBOARD)
      kbd_parse(hid->usb->spi, &hid->report, &hid->keyboard, buffer, hid->nbytes);
    
    if(hid->report.type == REPORT_TYPE_MOUSE)
      mouse_parse(hid->usb->spi, &hid->report, &hid->mouse, buffer, hid->nbytes);
    
    if(hid->report.type == REPORT_TYPE_JOYSTICK)
      joystick_parse(hid->usb->spi, &hid->report, &hid->joystick, buffer, hid->nbytes);
  }
}

static void xbox_parse(struct xbox_info_S *xbox) {
#if 0
  USB_LOG_RAW("XBOX%d: ", xbox->index);
  
  // just dump the report
  for (size_t i = 0; i < 20; i++) 
    USB_LOG_RAW("0x%02x ", xbox->buffer[i]);
  USB_LOG_RAW("\r\n");
#endif

  // verify length field
  if(xbox->buffer[0] != 0 || xbox->buffer[1] != 20)
    return;

  // the xbox controller sends the direction bits in exactly the
  // reversed order than we expect ...
  unsigned char state =
    ((xbox->buffer[2] & 0x01)<<3) | ((xbox->buffer[2] & 0x02)<<1) |
    ((xbox->buffer[2] & 0x04)>>1) | ((xbox->buffer[2] & 0x08)>>3) |
    (xbox->buffer[3] & 0xf0);
  
  // submit if state has changed
  if(state != xbox->last_state) {
    
    printf("XBOX Joy%d: %02x\r\n", xbox->js_index, state);
  
    spi_t *spi = xbox->usb->spi;  
    spi_begin(spi);
    spi_tx_u08(spi, SPI_TARGET_HID);
    spi_tx_u08(spi, SPI_HID_JOYSTICK);
    spi_tx_u08(spi, xbox->js_index);
    spi_tx_u08(spi, state);
    spi_end(spi);
    
    xbox->last_state = state;
  }
}

// A stalled interrupt endpoint stays stalled until the host clears it,
// and the device's data toggle starts over at DATA0 when it does; the
// stack has already zeroed the URB's toggle to match (ehci_check_qh).
static int hid_clear_halt(struct hid_info_S *hid) {
  struct usb_setup_packet *setup = hid->class->hport->setup;
  setup->bmRequestType = USB_REQUEST_DIR_OUT | USB_REQUEST_STANDARD | USB_REQUEST_RECIPIENT_ENDPOINT;
  setup->bRequest = USB_REQUEST_CLEAR_FEATURE;
  setup->wValue = USB_FEATURE_ENDPOINT_HALT;
  setup->wIndex = hid->class->intin->bEndpointAddress;
  setup->wLength = 0;
  return usbh_control_transfer(hid->class->hport, setup, NULL);
}

// each HID client gets its own thread which submits urbs and waits for
// the interrupt to succeed.  The URB is synchronous with a timeout: a
// report completes it at once, silence times it out and it is simply
// submitted again, and the thread is never blocked past HID_URB_MS - so
// a detach (hid->stop) is noticed, and so is a device that has gone
// quiet for good.  The thread deletes itself; nobody deletes it.
#define HID_URB_MS 1000

static void usbh_hid_client_thread(void *argument) {
  struct hid_info_S *hid = (struct hid_info_S *)argument;
  int errors = 0;

  printf("HID client #%d: thread started\r\n", hid->index);

  while(!hid->stop) {
    struct usbh_hubport *hport = hid->class->hport;
    if(!hport || !hport->connected) break;

    usbh_int_urb_fill(&hid->class->intin_urb, hport, hid->class->intin, hid->buffer,
		      hid->report.report_size + (hid->report.report_id_present ? 1:0),
		      HID_URB_MS, usbh_hid_callback, hid);
    // a URB the timeout killed keeps errorcode = -USB_ERR_BUSY, and
    // usbh_submit_urb() refuses such a URB out of hand: clear it, or the
    // first idle second is the last
    hid->class->intin_urb.errorcode = 0;
    int ret = usbh_submit_urb(&hid->class->intin_urb);
    if(hid->stop) break;

    if(ret == -USB_ERR_TIMEOUT) {
      errors = 0;                      // an idle device, the normal case
      continue;
    }
    if(ret == -USB_ERR_NODEV || ret == -USB_ERR_NOTCONN || ret == -USB_ERR_SHUTDOWN)
      break;                           // gone; usbh_hid_stop() is on its way or done
    if(ret < 0) {
      if(!(errors++ % 100))
	printf("HID client #%d: submit failed %d\r\n", hid->index, ret);
      if(ret == -USB_ERR_STALL) {
	int r = hid_clear_halt(hid);
	printf("HID client #%d: endpoint halted, cleared: %d\r\n", hid->index, r);
      }
      vTaskDelay(pdMS_TO_TICKS(10));   // never spin on a broken endpoint
      continue;
    }

    // a report: the callback has given the semaphore and set nbytes
    if(xSemaphoreTake(hid->sem, pdMS_TO_TICKS(10)) == pdTRUE && !hid->stop) {
      errors = 0;
      if(hid->nbytes > 0) hid_parse(hid);
      hid->nbytes = 0;
    }

#ifdef RATE_CHECK
    hid->rate_events++;
    if(!(hid->rate_events % 100)) {
     float ms_since_start = (xTaskGetTickCount() - hid->rate_start) * portTICK_PERIOD_MS;
     printf("Rate = %f events/sec\r\n",  1000 * hid->rate_events /  ms_since_start);
    }    
#endif
  }

  printf("HID client #%d: stopping\r\n", hid->index);
  hid->task_handle = NULL;
  vTaskDelete(NULL);
}

// ... and XBOX clients as well
static void usbh_xbox_client_thread(void *argument) {
  struct xbox_info_S *xbox = (struct xbox_info_S *)argument;

  printf("XBOX client #%d: thread started\r\n", xbox->index);

  while(1) {
    int ret = usbh_submit_urb(&xbox->class->intin_urb);
    if (ret < 0)
      printf("XBOX client #%d: submit failed\r\n", xbox->index);
    else {
      // Wait for result
      xSemaphoreTake(xbox->sem, 0xffffffffUL);
      xbox_parse(xbox);
    }      

#ifdef RATE_CHECK
    xbox->rate_events++;
    if(!(xbox->rate_events % 100)) {
     float ms_since_start = (xTaskGetTickCount() - xbox->rate_start) * portTICK_PERIOD_MS;
     printf("Rate = %f events/sec\r\n",  1000 * xbox->rate_events /  ms_since_start);
    }    
#endif
  }
}

static void usbh_hid_thread(void *argument) {
  printf("Starting usb host task...\r\n");

  struct usb_config *usb = (struct usb_config *)argument;

  // request status (currently only dummy data, will return 0x5c, 0x42)
  // in the long term the core is supposed to return its HID demands
  // (keyboard matrix type, joystick type and number, ...)
  
  spi_begin(usb->spi);
  spi_tx_u08(usb->spi, SPI_TARGET_HID);
  spi_tx_u08(usb->spi, SPI_HID_STATUS);
  spi_tx_u08(usb->spi, 0x00);
  printf("HID status #0: %02x\r\n", spi_tx_u08(usb->spi, 0x00));
  printf("HID status #1: %02x\r\n", spi_tx_u08(usb->spi, 0x00));
  spi_end(usb->spi);

  while (1) {
    usbh_update(usb);

    // HID devices are started by usbh_hid_run() as the stack finds
    // them; this loop is left the LEDs, the UKNC's mouse flag and the
    // (never seen here) xbox class

    for(int i=0;i<CONFIG_USBHOST_MAX_XBOX_CLASS;i++) {
      if(usb->xbox_info[i].state == STATE_DETECTED) {
	printf("NEW XBOX device %d\r\n", i);
	usb->xbox_info[i].state = STATE_RUNNING; 

	// search for free joystick slot
	usb->xbox_info[i].js_index = 0;
	while(usb->js_map & (1<<usb->xbox_info[i].js_index))
	  usb->xbox_info[i].js_index++;

	printf("  -> joystick %d\r\n", usb->xbox_info[i].js_index);
	usb->js_map |= 1<<usb->xbox_info[i].js_index;
	
	// setup urb
	usbh_int_urb_fill(&usb->xbox_info[i].class->intin_urb,
			  usb->xbox_info[i].class->hport,
			  usb->xbox_info[i].class->intin, usb->xbox_info[i].buffer,
			  XBOX_REPORT_SIZE,
			  0, usbh_xbox_callback, &usb->xbox_info[i]);
	
#ifdef RATE_CHECK
	usb->xbox_info[i].rate_start = xTaskGetTickCount();
	usb->xbox_info[i].rate_events = 0;
#endif

	// start a new thread for the new device
	xTaskCreate(usbh_xbox_client_thread, (char *)"xbox_task", 2048,
		    &usb->xbox_info[i], configMAX_PRIORITIES-3, &usb->xbox_info[i].task_handle );
      }
    }

    // this thread only handles new devices and thus doesn't have to run very
    // often
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

void usb_register_osd(osd_t *osd) {
  usb_config.osd = osd;
}

void usb_host(spi_t *spi) {
  TaskHandle_t usb_handle;

  printf("init usb hid host\r\n");

  //usbh_initialize(0, USB_BASE);
  usbh_initialize();
  
  usb_config.spi = spi;
  usb_config.osd = NULL;
  usb_config.js_map = 0;   // no joysticks yet
  
  // initialize all HID info entries
  for(int i=0;i<CONFIG_USBHOST_MAX_HID_CLASS;i++) {
    usb_config.hid_info[i].index = i;
    usb_config.hid_info[i].state = 0;
    usb_config.hid_info[i].buffer = hid_buffer[i];      
    usb_config.hid_info[i].usb = &usb_config;
    usb_config.hid_info[i].sem = xSemaphoreCreateBinary();
    usb_config.hid_info[i].stop = 0;
    usb_config.hid_info[i].task_handle = NULL;
  }
  
  // initialize all XBOX info entries
  for(int i=0;i<CONFIG_USBHOST_MAX_XBOX_CLASS;i++) {
    usb_config.xbox_info[i].index = i;
    usb_config.xbox_info[i].state = 0;
    usb_config.xbox_info[i].buffer = xbox_buffer[i];      
    usb_config.xbox_info[i].usb = &usb_config;
    usb_config.xbox_info[i].sem = xSemaphoreCreateBinary();
  }

  xTaskCreate(usbh_hid_thread, (char *)"usb_task", 2048, &usb_config, configMAX_PRIORITIES-3, &usb_handle);
}

// hid event triggered by FPGA
void hid_handle_event(void) {
  spi_t *spi = usb_config.spi;
  
  spi_begin(spi);
  spi_tx_u08(spi, SPI_TARGET_HID);
  spi_tx_u08(spi, SPI_HID_GET_DB9);
  spi_tx_u08(spi, 0x00);
  uint8_t db9 = spi_tx_u08(spi, 0x00);
  spi_end(spi);

  printf("DB9: %02x\r\n", db9);
}
