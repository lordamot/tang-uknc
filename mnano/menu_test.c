/*
  menu_test.c - the OSD menu on the host (make menu-test).

  menu.c is compiled with -DSDL, which is its host switch: no FreeRTOS,
  menu_init() takes a u8g2 to draw into.  Everything else it calls is
  stubbed here - the card has three files a slot, the core takes the
  values into a log, the clock reads a fixed time - and the menu is driven
  through menu_do() with the events usb_host.c would send.  Each screen
  worth looking at is dumped as a 128x64 text bitmap under the directory
  given as the first argument (tools/osd_png.py makes PNGs of them), and
  the things that can be asserted are: which form is open and which entry
  is highlighted after a key, what the core was sent, what the main form
  offers, that the info line is never selected and is redrawn once a
  second, and that the text page scrolls and returns.
*/
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include "u8g2.h"
#include "ff.h"
#include "diskio.h"
#include "sysctrl.h"
#include "sdc.h"
#include "rt11sav.h"
#include "menu.h"

unsigned char core_id = CORE_ID_UKNC;

//------------------------------------------------------------------------
// stubs
//------------------------------------------------------------------------
void vTaskDelay(int ms) { (void)ms; }
void sdc_lock(void) {}
void sdc_unlock(void) {}
int  sdc_is_ready(void) { return 1; }
void osd_enable(osd_t *osd, char en) { (void)osd; (void)en; }

// FatFs never gets a volume here: f_open fails and the menu takes its
// defaults, which is the path a card without an .ini takes
DSTATUS disk_initialize(BYTE p) { (void)p; return STA_NOINIT; }
DSTATUS disk_status(BYTE p) { (void)p; return STA_NOINIT; }
DRESULT disk_read(BYTE p, BYTE *b, LBA_t s, UINT c) { (void)p; (void)b; (void)s; (void)c; return RES_NOTRDY; }
DRESULT disk_write(BYTE p, const BYTE *b, LBA_t s, UINT c) { (void)p; (void)b; (void)s; (void)c; return RES_NOTRDY; }
DRESULT disk_ioctl(BYTE p, BYTE c, void *b) { (void)p; (void)c; (void)b; return RES_NOTRDY; }

// what the core was told: a log of (id, value)
static char set_log[256][2];
static int  set_n;
void sys_set_val(spi_t *spi, char id, uint8_t v) {
  (void)spi;
  if(set_n < 256) { set_log[set_n][0] = id; set_log[set_n][1] = v; }
  set_n++;
}
static int set_last(char id) {
  for(int i=set_n-1;i>=0;i--) if(set_log[i][0] == id) return set_log[i][1];
  return -1;
}
static int set_count(char id) {
  int n = 0;
  for(int i=0;i<set_n;i++) if(set_log[i][0] == id) n++;
  return n;
}

static int rtc_reads;
void sys_get_rtc(spi_t *spi, sys_rtc_t *t) {
  (void)spi;
  rtc_reads++;
  t->year = 2026; t->month = 2; t->date = 23; t->hour = 14; t->min = 0; t->sec = rtc_reads % 60; t->dow = 5;
}

unsigned rt11sav_date(int y, int m, int d) { (void)y; (void)m; (void)d; return 0; }
int rt11sav_make(const char *dir, const char *name, unsigned date, char *err, int errlen) {
  (void)dir; (void)name; (void)date; (void)err; (void)errlen; return 0;
}

// the card: one directory a slot, three files each
static char *cwd[MAX_DRIVES + 1];
static char *image_name[MAX_DRIVES + 1];
char *sdc_get_image_name(int drive) { return image_name[drive]; }
char *sdc_get_cwd(int drive) { if(!cwd[drive]) cwd[drive] = strdup(CARD_MOUNTPOINT); return cwd[drive]; }
void sdc_set_default(int drive, const char *name) { (void)drive; (void)name; }
void sdc_set_image_name(int drive, const char *name) {
  if(image_name[drive]) free(image_name[drive]);
  image_name[drive] = name ? strdup(name) : NULL;
}
static int opened[MAX_DRIVES + 1];
int sdc_image_open(int drive, char *name) {
  sdc_set_image_name(drive, name);
  opened[drive]++;
  return 0;
}
sdc_dir_t *sdc_readdir(int drive, char *name, const char *exts) {
  static sdc_dir_entry_t files[4];
  static sdc_dir_t dir = { 4, files };
  static char n0[] = "/No Disk", n1[64], n2[64], n3[64];
  (void)drive; (void)name;
  char ext[8] = "dsk";
  sscanf(exts, "%7[a-z]", ext);
  files[0].name = n0; files[0].is_dir = 1;
  snprintf(n1, sizeof(n1), "GAME.%s", ext); files[1].name = n1; files[1].is_dir = 0;
  snprintf(n2, sizeof(n2), "SYSTEM.%s", ext); files[2].name = n2; files[2].is_dir = 0;
  snprintf(n3, sizeof(n3), "A rather long file name that has to scroll.%s", ext); files[3].name = n3; files[3].is_dir = 0;
  return &dir;
}

//------------------------------------------------------------------------
// the screen
//------------------------------------------------------------------------
static u8g2_t u8g2;
static const char *outdir = ".";
static int shots;

static void shot(const char *name) {
  char path[256];
  snprintf(path, sizeof(path), "%s/%02d-%s.txt", outdir, ++shots, name);
  FILE *f = fopen(path, "w");
  if(!f) { perror(path); exit(1); }
  for(int y=0;y<64;y++) {
    for(int x=0;x<128;x++) fputc(u8x8_GetBitmapPixel(u8g2_GetU8x8(&u8g2), x, y) ? '#' : '.', f);
    fputc('\n', f);
  }
  fclose(f);
}

static int errors;
#define CHECK(cond, ...) do { if(!(cond)) { errors++; printf("FAIL: "); printf(__VA_ARGS__); printf("\n"); } } while(0)

int main(int argc, char **argv) {
  if(argc > 1) outdir = argv[1];

  u8g2_SetupBitmap(&u8g2, &u8g2_cb_r0, 128, 64);
  u8x8_InitDisplay(u8g2_GetU8x8(&u8g2));

  menu_t *menu = menu_init(&u8g2);
  menu_do(menu, 0);
  shot("main");

  //---- the main form: no HDD0 while the controller is off, the rest in order
  CHECK(menu->form == 0 && menu->entry == 1, "start: form %d entry %d", menu->form, menu->entry);
  CHECK(strstr(menu->forms[0], "HDD0:") == NULL, "main form offers HDD0 with the controller off");
  CHECK(strstr(menu->forms[0], "F,FDD0:") && strstr(menu->forms[0], "Run SAV:") && strstr(menu->forms[0], "B,Reset") &&
        strstr(menu->forms[0], "S,Hardware,1") && strstr(menu->forms[0], "T,About") && strstr(menu->forms[0], "B,Save settings,S"),
        "main form entries: %s", menu->forms[0]);
  CHECK(menu->entries == 7, "main form has %d entries, expected 7", menu->entries);

  //---- the defaults went to the core, every letter once
  const char *letters = "Ab123cfpqrseKJDuty mdhnV";
  for(const char *l = letters; *l; l++) if(*l != ' ')
    CHECK(set_count(*l) == 1, "letter %c sent %d times at start", *l, set_count(*l));
  CHECK(set_last('A') == 1 && set_last('b') == 1 && set_last('1') == 1 && set_last('c') == 0 && set_last('f') == 1 &&
        set_last('e') == 0 && set_last('u') == 0 && set_last('t') == 0 && set_last('D') == 30 && set_last('y') == 6 && set_last('V') == 0,
        "defaults wrong");
  CHECK(set_last('P') == -1, "the old 'P' letter is still sent");

  //---- Hardware
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 4, "after 3 downs entry %d, expected 4 (Hardware)", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 1 && menu->entry == 1, "Hardware: form %d entry %d", menu->form, menu->entry);
  shot("hardware");

  //---- left/right on Volume
  int n = set_n;
  menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_last('A') == 2 && set_n == n+1, "right on Volume: A=%d", set_last('A'));
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_LEFT);
  CHECK(set_last('A') == 0, "two lefts on Volume: A=%d", set_last('A'));
  menu_do(menu, MENU_EVENT_LEFT);
  CHECK(set_last('A') == 3, "left wraps to 100%%: A=%d", set_last('A'));
  menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_last('A') == 0, "right wraps to Mute: A=%d", set_last('A'));
  menu_do(menu, MENU_EVENT_RIGHT);   // back to 33%
  menu_do(menu, MENU_EVENT_SELECT);  // space steps on: 66%
  CHECK(set_last('A') == 2, "space on Volume: A=%d", set_last('A'));
  menu_do(menu, MENU_EVENT_LEFT);
  // left/right on a submenu entry do nothing
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN);   // Aberrant
  n = set_n;
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_n == n && menu->form == 1 && menu->entry == 3, "left/right on Aberrant did something (form %d entry %d, %d sets)", menu->form, menu->entry, set_n - n);

  //---- Covox's long value fits
  menu_do(menu, MENU_EVENT_DOWN);    // Covox
  menu_do(menu, MENU_EVENT_RIGHT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_last('c') == 2, "Covox to LPT: c=%d", set_last('c'));
  shot("hardware-covox-lpt");
  menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_last('c') == 3, "Covox to Both: c=%d", set_last('c'));

  //---- Aberrant and back to the entry that opened it
  menu_do(menu, MENU_EVENT_UP);      // Aberrant
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 2 && menu->entry == 1, "Aberrant: form %d entry %d", menu->form, menu->entry);
  shot("aberrant");
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_SELECT);   // AY2 off
  CHECK(set_last('2') == 0, "AY2 off: 2=%d", set_last('2'));
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(set_last('2') == 1, "AY2 on again: 2=%d", set_last('2'));
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP);   // the title
  CHECK(menu->entry == 0, "Aberrant title: entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 1 && menu->entry == 3, "back from Aberrant: form %d entry %d, expected 1/3", menu->form, menu->entry);

  //---- HDD controller: on adds HDD0 to the main form
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN);   // HDD controller
  CHECK(menu->entry == 6, "HDD controller entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 4 && menu->entry == 1, "HDD form %d entry %d", menu->form, menu->entry);
  shot("hdd-off");
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(set_last('e') == 1, "HDD controller on: e=%d", set_last('e'));
  CHECK(strstr(menu->forms[0], "F,HDD0:,4|img;") != NULL, "main form lacks HDD0 with the controller on: %s", menu->forms[0]);
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN);   // HDD image format
  shot("hdd-on");
  menu_do(menu, MENU_EVENT_RIGHT); menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_last('J') == 2, "HDD image Inversed: J=%d", set_last('J'));
  shot("hdd-inversed");
  menu_do(menu, MENU_EVENT_LEFT); menu_do(menu, MENU_EVENT_LEFT);
  menu_do(menu, MENU_EVENT_PGUP);
  CHECK(menu->entry == 1, "PGUP in HDD form: entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_UP);      // title
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 1 && menu->entry == 6, "back from HDD: form %d entry %d, expected 1/6", menu->form, menu->entry);

  //---- the main form now with HDD0, and its file selector
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP);
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP);   // title
  CHECK(menu->entry == 0, "Hardware title: entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0 && menu->entry == 5, "back from Hardware: form %d entry %d, expected 0/5 (Hardware moved down one)", menu->form, menu->entry);
  CHECK(menu->entries == 8, "main form has %d entries with HDD0, expected 8", menu->entries);
  shot("main-hdd");
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP);   // HDD0:
  CHECK(menu->entry == 2, "HDD0 entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == MENU_FORM_FSEL, "HDD0 file selector: form %d", menu->form);
  shot("fsel-hdd");
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_SELECT);   // GAME.img
  CHECK(menu->form == 0 && menu->entry == 2, "after mounting: form %d entry %d, expected 0/2", menu->form, menu->entry);
  CHECK(opened[4] == 1 && image_name[4] && !strcmp(image_name[4], "GAME.img"), "HDD0 mounted %s", image_name[4] ? image_name[4] : "(none)");
  shot("main-hdd-mounted");

  //---- About: a text page that scrolls and returns
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN);   // About
  CHECK(menu->entry == 6, "About entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == MENU_FORM_TEXT && menu->offset == 0, "About: form %d offset %d", menu->form, menu->offset);
  shot("about-0");
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->offset == 1, "About scrolled to %d", menu->offset);
  menu_do(menu, MENU_EVENT_PGDOWN); menu_do(menu, MENU_EVENT_PGDOWN);
  shot("about-9");
  for(int i=0;i<60;i++) menu_do(menu, MENU_EVENT_DOWN);
  int last = menu->offset;
  CHECK(last > 10 && last < 44, "About scrolled to the end at %d", last);
  shot("about-end");
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->offset == last, "About scrolls past its end");
  menu_do(menu, MENU_EVENT_UP);
  CHECK(menu->offset == last-1, "About does not scroll back");
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0 && menu->entry == 6, "back from About: form %d entry %d", menu->form, menu->entry);

  //---- FDD controller form and a file selector returning to its entry
  menu_do(menu, MENU_EVENT_UP);      // Hardware
  menu_do(menu, MENU_EVENT_SELECT);
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN);   // FDD controller
  CHECK(menu->entry == 5, "FDD controller entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 3 && menu->entry == 1, "FDD form %d entry %d", menu->form, menu->entry);
  shot("fdd");
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN);   // FDD1:
  CHECK(menu->entry == 4, "FDD1 entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == MENU_FORM_FSEL, "FDD1 file selector: form %d", menu->form);
  shot("fsel-fdd1");
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_SELECT);   // SYSTEM.dsk
  CHECK(menu->form == 3 && menu->entry == 4, "after mounting FDD1: form %d entry %d, expected 3/4", menu->form, menu->entry);
  CHECK(image_name[1] && !strcmp(image_name[1], "SYSTEM.dsk"), "FDD1 mounted %s", image_name[1] ? image_name[1] : "(none)");
  menu_do(menu, MENU_EVENT_DOWN);    // FDD1 write prot.
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(set_last('q') == 1 && set_last('p') == 0, "FDD1 write prot: q=%d p=%d", set_last('q'), set_last('p'));
  shot("fdd-1-prot");
  menu_do(menu, MENU_EVENT_PGDOWN); menu_do(menu, MENU_EVENT_PGDOWN);
  CHECK(menu->entry == 9, "PGDOWN in FDD form: entry %d", menu->entry);
  shot("fdd-end");
  menu_do(menu, MENU_EVENT_PGUP); menu_do(menu, MENU_EVENT_PGUP); menu_do(menu, MENU_EVENT_UP);
  CHECK(menu->entry == 0, "FDD title: entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 1 && menu->entry == 5, "back from FDD: form %d entry %d", menu->form, menu->entry);

  //---- RTC clock: the info line is skipped and redrawn on the timer
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_DOWN);   // RTC clock
  CHECK(menu->entry == 8, "RTC clock entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 5 && menu->entry == 1, "RTC form %d entry %d", menu->form, menu->entry);
  int reads = rtc_reads;
  menu_do(menu, MENU_EVENT_PGDOWN);
  CHECK(menu->entry == 5, "PGDOWN in RTC form: entry %d, expected 5 (Hour)", menu->entry);
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 6, "DOWN to Minute: entry %d", menu->entry);
  shot("rtc");
  menu_do(menu, MENU_EVENT_DOWN);
  CHECK(menu->entry == 0, "DOWN past Minute: entry %d, expected the title", menu->entry);
  menu_do(menu, MENU_EVENT_UP);
  CHECK(menu->entry == 6, "UP from the title: entry %d, expected 6 (Minute)", menu->entry);
  reads = rtc_reads;
  for(int i=0;i<24;i++) menu_do(menu, -1);
  CHECK(rtc_reads == reads, "info line redrawn before a second (%d reads)", rtc_reads - reads);
  menu_do(menu, -1);
  CHECK(rtc_reads == reads + 1, "info line not redrawn after a second (%d reads)", rtc_reads - reads);
  menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_last('n') == 1, "right on Minute: n=%d", set_last('n'));
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP);   // RTC controller
  CHECK(menu->entry == 1, "RTC controller entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(set_last('t') == 1, "RTC controller on: t=%d", set_last('t'));
  shot("rtc-on");
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 1 && menu->entry == 8, "back from RTC: form %d entry %d", menu->form, menu->entry);

  //---- Misc
  menu_do(menu, MENU_EVENT_DOWN);    // Misc
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 6 && menu->entry == 1, "Misc form %d entry %d", menu->form, menu->entry);
  menu_do(menu, MENU_EVENT_RIGHT);
  CHECK(set_last('V') == 1, "Color BGR: V=%d", set_last('V'));
  shot("misc");
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 1 && menu->entry == 9, "back from Misc: form %d entry %d", menu->form, menu->entry);

  //---- Mouse and Beeper
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP);   // Mouse
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(set_last('u') == 1, "Mouse on: u=%d", set_last('u'));
  menu_do(menu, MENU_EVENT_PGUP);
  CHECK(menu->entry == 3, "PGUP from Mouse: entry %d, expected 3 (Aberrant)", menu->entry);
  menu_do(menu, MENU_EVENT_UP);      // Beeper
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(set_last('b') == 0, "Beeper mute: b=%d", set_last('b'));
  shot("hardware-set");

  //---- Run SAV from the main form
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_SELECT);   // title -> main
  CHECK(menu->form == 0 && menu->entry == 5, "back to main: form %d entry %d", menu->form, menu->entry);
  menu_do(menu, MENU_EVENT_UP); menu_do(menu, MENU_EVENT_UP);   // Run SAV:
  CHECK(menu->entry == 3, "Run SAV entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == MENU_FORM_FSEL, "Run SAV selector: form %d", menu->form);
  menu_do(menu, MENU_EVENT_DOWN); menu_do(menu, MENU_EVENT_SELECT);   // GAME.sav
  CHECK(menu->form == 0 && menu->entry == 3, "after Run SAV: form %d entry %d, expected 0/3", menu->form, menu->entry);
  CHECK(set_last('R') == 0 && set_count('R') >= 4, "Run SAV did not reset the core");
  shot("main-sav-done");
  menu_do(menu, MENU_EVENT_HIDE);

  //---- Save settings is a button on the main form: it writes the card (fails here, no card)
  menu_do(menu, MENU_EVENT_SHOW);
  menu_do(menu, MENU_EVENT_PGDOWN); menu_do(menu, MENU_EVENT_PGDOWN);
  CHECK(menu->entry == 7, "Save settings entry %d", menu->entry);
  menu_do(menu, MENU_EVENT_SELECT);
  CHECK(menu->form == 0, "Save settings left the main form");
  shot("main-end");

  printf("menu-test: %d screens in %s, %d error(s)\n", shots, outdir, errors);
  return errors ? 1 : 0;
}
