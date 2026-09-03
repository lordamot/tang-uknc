/*
  menu.c - MiSTeryNano menu based in u8g2
*/
  
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ff.h>

#include "sdc.h"
#include "menu.h"
#include "sysctrl.h"
#include "rt11sav.h"

#ifndef SDL
#include <queue.h>
extern QueueHandle_t xQueue;   // the OSD's event queue (main.c)
#endif

// this is the u8g2_font_helvR08_te with any trailing
// spaces removed
#include "font_helvR08_te.c"

#define MENU2U8G2(a)  (&(a->osd->u8g2))

#define MENU_ENTRY_INDEX_ID       0
#define MENU_ENTRY_INDEX_LABEL    1
#define MENU_ENTRY_INDEX_FORM     2
#define MENU_ENTRY_INDEX_OPTIONS  2
#define MENU_ENTRY_INDEX_VARIABLE 3
// ------------------------------------------------------------------
// ---------------------  Agat9 menu -----------------------------
// ------------------------------------------------------------------
static const char main_form_agat9[] =
  "nanoGAT9,;"                         // main form has no parent
  // --------
  "F,FDD840 A:,0|aim;"                    // fileselector for Disk 1:
  "S,System,1;"                         // System submenu is form 1
  "S,Drives,2;"                         // Storage submenu
  "S,Settings,3;"                       // Settings submenu is form 2
  "B,Reset,R;";                         // system reset

static const char system_form_agat9[] =
  "System,0|1;"                         // return to form 0, entry 3
  // --------
  "L,Video:,RGB|Mono,V;"
  "B,Cold Boot,B;";                     // system reset with memory reset

static const char storage_form_agat9[] =
  "Drives,0|2;"                         // return to form 0, entry 3
  // --------
  "F,Disk 840 A:,0|aim;"               // fileselector for Disk 0:
  "F,Disk 840 B:,1|aim;"               // fileselector for Disk 0:
  "F,Disk 140 A:,2|nib;"               // fileselector for Disk 1:
  "F,Disk 140 B:,3|nib;"               // fileselector for Disk 1:
  "L,Disk prot.:,None|0:|1:|2:|3:|All,P;";   // Enable/Disable Floppy write protection
  
static const char settings_form_agat9[] =
  "Settings,0|3;"                       // return to form 0, entry 4
  // --------
  "L,Volume:,Mute|33%|66%|100%,A;"
  "B,Save settings,S;";

static const char *forms_agat9[] = {
  main_form_agat9,
  system_form_agat9,
  storage_form_agat9,
  settings_form_agat9
};

// variable ids must match the ones in the menu string
menu_variable_t variables_agat9[] = {
  { 'V', { 0 }},    // default video = RGB
  { 'A', { 1 }},    // default volume = 33%
  { 'P', { 0 }},    // default no floppy write protected
  { '\0',{ 0 }}
};
// ------------------------------------------------------------------
// ---------------------  UKNC menu -----------------------------
// ------------------------------------------------------------------
// Restructured in Sep 2026 (v2.0.0): the main form is the disks, the
// reset, one "Hardware" form for everything the machine is made of, an
// "About" text and "Save settings".  Every hardware switch is a letter
// sysctrl.v decodes; a device that is off is not on the PPU bus at all.
//
// A form's title is "name,parent|entry": the parent form and the entry
// in it to return to.  The entry number is only a fallback now -
// menu_parent_entry() finds the 'S' entry that opened the form by its
// form number, so a form can move in its parent without renumbering
// (which is what used to go wrong here).
//
// The main form is built at run time: "HDD0:" is only there while the
// HDD controller is on.

#ifndef UKNC_VERSION
#define UKNC_VERSION ""                 // ../VERSION, through CMakeLists.txt
#endif

#define UKNC_FORM_MAIN     0
#define UKNC_FORM_HARDWARE 1
#define UKNC_FORM_ABERRANT 2
#define UKNC_FORM_FDD      3
#define UKNC_FORM_HDD      4
#define UKNC_FORM_RTC      5
#define UKNC_FORM_MISC     6

static char main_form_uknc[192];        // menu_uknc_main() writes it
static char sav_status[24];             // what "Run SAV:" shows instead of its label (menu_run_sav)

static const char hardware_form_uknc[] =
  "Hardware,0|5;"                       // return to the main form
  // --------
  "L,Volume:,Mute|33%|66%|100%,A;"
  "L,Beeper:,Mute|On,b;"                // a standard part: stays on the bus, leaves the mixer
  "S,Aberrant,2;"
  "L,Covox:,Off|Port 177372|Port 177100 LPT|Both,c;"   // bit 0 the Aberrant's DAC, bit 1 the printer port
  "S,FDD controller,3;"
  "S,HDD controller,4;"
  "L,Mouse:,Off|On,u;"                  // the Kakave+ mouse word 0177400
  "S,RTC clock,5;"
  "S,Misc,6;";

static const char aberrant_form_uknc[] =
  "Aberrant,1|3;"                       // return to Hardware
  // --------
  "L,AY1:,Off|On,1;"                    // 0177360
  "L,AY2:,Off|On,2;"                    // 0177362
  "L,AY3:,Off|On,3;";                   // 0177364

static const char fdd_form_uknc[] =
  "FDD controller,1|5;"
  // --------
  "L,FDD controller:,Off|On,f;"         // 0177130/0177132
  "F,FDD0:,0|dsk;"
  "L,FDD0 write prot.:,Off|On,p;"
  "F,FDD1:,1|dsk;"
  "L,FDD1 write prot.:,Off|On,q;"
  "F,FDD2:,2|dsk;"
  "L,FDD2 write prot.:,Off|On,r;"
  "F,FDD3:,3|dsk;"
  "L,FDD3 write prot.:,Off|On,s;";

static const char hdd_form_uknc[] =
  "HDD controller,1|6;"
  // --------
  "L,HDD controller:,Off|On,e;"         // the IDE cartridge; off also hides HDD0: on the main form
  "F,HDD0:,4|img;"                      // the cartridge's disk, SD slot 4
  "L,HDD write prot.:,Off|On,K;"
  "L,Image format:,Auto|Plain|Inversed,J;"   // how the image's bytes are read (see sdc.c); "HDD image format" does not fit beside "Inversed"
  "L,HDD delay:,0|25|50|75|100|125|150|175|200|225|250|275|300|325|350|375|400|425|450|475|500|525|550|575|600|625|650|675|700|725|750|775|800|825|850|875|900|925|950|975,D;";  // ~us added per sector, spread over its reads; sets a streamed demo's sample rate

// The Kakave+ real-time clock (kakave.v) has no battery behind it, so this
// is where its time comes from at power-up: every variable is sent to the
// core at start (below, "send initial values"), so the saved values land
// in the clock then, and changing one here sets that field at once -
// minutes also restart the seconds.  The letters are sysctrl.v's:
// 'y' year-2020, 'm' month-1, 'd' date-1, 'h' hours, 'n' minutes.  The
// machine can set the same clock itself through the cartridge's own
// protocol (RT-11's KKVRTC); the last line reads the clock back from the
// core (sysctrl CMD 6) once a second, so that shows too.
static const char rtc_form_uknc[] =
  "RTC clock,1|8;"
  // --------
  "L,RTC controller:,Off|On,t;"         // the clock word 0177410; the clock counts either way
  "L,Year:,2020|2021|2022|2023|2024|2025|2026|2027|2028|2029|2030|2031|2032|2033|2034|2035|2036|2037|2038|2039,y;"
  "L,Month:,1|2|3|4|5|6|7|8|9|10|11|12,m;"
  "L,Day:,1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31,d;"
  "L,Hour:,0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23,h;"
  "L,Minute:,0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31|32|33|34|35|36|37|38|39|40|41|42|43|44|45|46|47|48|49|50|51|52|53|54|55|56|57|58|59,n;"
  "I,rtc,;";                            // "2026-02-23 14:00:01 Thu", not selectable

static const char misc_form_uknc[] =
  "Misc,1|9;"
  // --------
  "L,Color:,RGB|BGR,V;"                 // swaps the red and blue planes (top.v)
  "B,Cold Boot,B;";                     // system reset with memory reset

static const char *forms_uknc[] = {
  main_form_uknc,
  hardware_form_uknc,
  aberrant_form_uknc,
  fdd_form_uknc,
  hdd_form_uknc,
  rtc_form_uknc,
  misc_form_uknc
};

// the "About" text, one paragraph a string, wrapped to the OSD's width
// when it is opened (menu_text_open); "" is an empty line
static const char *about_uknc[] = {
  "UKNC Nano author: Alex Gurov",
  "",
  "v2.x update authors: Sergei Lemeshev, ClaudeCode",
  "",
  "Greets and big thanks to:",
  "",
  "nzeemin - specially for his great UKNCBTL emulator and programs",
  "blairecas - specially for his programs and BadApple demo for UKNC",
  "reddie - heavy support with everything - programming, testing help, and lots of ideas and advices during this so-called-development",
  "xrust - specially for great efforts on creating and redesigining peripherals",
  "",
  "And all our community who made it real, after all",
  NULL
};

// variable ids must match the ones in the menu string, and sysctrl.v's
menu_variable_t variables_uknc[] = {
  { 'A', { 1 }},    // Volume 33%
  { 'b', { 1 }},    // Beeper on
  { '1', { 1 }},    // AY1 on
  { '2', { 1 }},    // AY2 on
  { '3', { 1 }},    // AY3 on
  { 'c', { 0 }},    // Covox off
  { 'f', { 1 }},    // FDD controller on
  { 'p', { 0 }},    // FDD0..3 not write protected
  { 'q', { 0 }},
  { 'r', { 0 }},
  { 's', { 0 }},
  { 'e', { 0 }},    // HDD controller off
  { 'K', { 0 }},    // HDD writable
  { 'J', { 0 }},    // HDD image form auto-detected from sector 0
  { 'D', { 30 }},   // HDD delay 750 us a sector: badapple's Covox right on the board (index x 25 us)
  { 'u', { 0 }},    // Mouse off
  { 't', { 0 }},    // RTC controller off
  { 'y', { 6 }},    // the clock, until it is set or saved: 2026-01-01 00:00 (year index 6 = 2026)
  { 'm', { 0 }},
  { 'd', { 0 }},
  { 'h', { 0 }},
  { 'n', { 0 }},
  { 'V', { 0 }},    // Color RGB
  { '\0',{ 0 }}
};

// the value of a variable by id, or -1
static int menu_var_value(menu_t *menu, char id) {
  for(int i=0;menu->vars[i].id;i++)
    if(menu->vars[i].id == id) return menu->vars[i].value;
  return -1;
}

// (re)build the main form: HDD0: only while the HDD controller ('e') is on
static void menu_uknc_main(menu_t *menu) {
  snprintf(main_form_uknc, sizeof(main_form_uknc),
	   "UKNC Nano,;"
	   "F,FDD0:,0|dsk;"
	   "%s"
	   "F,Run SAV:,5|sav;"               // a .SAV on the card -> RT11SAV.DSK in FDD0 (menu_run_sav, slot SDC_SLOT_SAV)
	   "B,Reset,R;"
	   "S,Hardware,1;"
	   "T,About,;"
	   "B,Save settings,S;",
	   menu_var_value(menu, 'e') > 0 ? "F,HDD0:,4|img;" : "");
}
// ------------------------------------------------------------------
// ---------------------  UNEON menu -----------------------------
// ------------------------------------------------------------------

static const char main_form_uneon[] =
  "UNEON Nano,;"                        // main form has no parent
  // --------
  "F,FDD 0:,0|dsk+img;"                 // fileselector for Disk 1:
  "F,FDD 1:,1|dsk+img;"                 // fileselector for Disk 2:
  "S,System,1;"                         // System submenu is form 1
  "S,Settings,2;"                       // Settings submenu is form 2
  "B,Reset,R;";                         // system reset

static const char system_form_uneon[] =
  "System,0|3;"                         // return to form 0, entry 3
  // --------
  "L,Chipset:,ST|Mega ST|STE,C;"        // selection stored in variable "C"
  "L,Memory:,4MB|8MB,M;"                // ...
  "L,Video:,Color|Mono,V;"
  "L,Cartridge:,None|Cubase 2&3,Q;"     // Cubase dongle support
  "L,Mouse:,USB|Atari ST|Amiga,J;"      // Mouse (DB9) mapping
  "L,TOS Slot:,Primary|Secondary,T;"    // Select TOS
  "B,Cold Boot,B;";                     // system reset with memory reset

static const char settings_form_uneon[] =
  "Settings,0|4;"                       // return to form 0, entry 4
  // --------
  "L,Screen:,Normal|Wide,W;"
  "L,Scanlines:,None|25%|50%|75%,S;"
  "L,Volume:,Mute|33%|66%|100%,A;"
  "B,Save settings,S;";

static const char *forms_uneon[] = {
  main_form_uneon,
  system_form_uneon,
  settings_form_uneon
};

// variable ids must match the ones in the menu string
menu_variable_t variables_uneon[] = {
  { 'C', { 0 }},    // default chipset = ST
  { 'M', { 0 }},    // default memory = 4MB
  { 'V', { 0 }},    // default video = color
  { 'S', { 0 }},    // default scanlines = none
  { 'A', { 1 }},    // default volume = 33%
  { 'W', { 0 }},    // default normal (4:3) screen
  { 'P', { 0 }},    // default no floppy write protected
  { 'Q', { 0 }},    // default cubase dongle not enabled
  { 'J', { 0 }},    // default mouse USB, DB9 connector joystick
  { 'T', { 0 }},    // default primary TOS slot
  { '\0',{ 0 }}
};
// ------------------------------------------------------------------
// ---------------------  Atari ST menu -----------------------------
// ------------------------------------------------------------------

static const char main_form_atari_st[] =
  "MiSTeryNano,;"                       // main form has no parent
  // --------
  "F,Disk A:,0|st;"                     // fileselector for Disk A:
  "S,System,1;"                         // System submenu is form 1
  "S,Drives,2;"                         // Storage submenu
  "S,Settings,3;"                       // Settings submenu is form 3
  "B,Reset,R;";                         // system reset

static const char system_form_atari_st[] =
  "System,0|2;"                         // return to form 0, entry 2
  // --------
  "L,Chipset:,ST|Mega ST|STE,C;"        // selection stored in variable "C"
  "L,Memory:,4MB|8MB,M;"                // ...
  "L,Video:,Color|Mono,V;"
  "L,Cartridge:,None|Cubase 2&3,Q;"     // Cubase dongle support
  "L,Mouse:,USB|Atari ST|Amiga,J;"      // Mouse (DB9) mapping
  "L,TOS Slot:,Primary|Secondary,T;"    // Select TOS
  "B,Cold Boot,B;";                     // system reset with memory reset

static const char storage_form_atari_st[] =
  "Drives,0|3;"                         // return to form 0, entry 3
  // --------
  "F,Disk A:,0|st;"                     // fileselector for Disk A:
  "F,Disk B:,1|st;"                     // fileselector for Disk B:
  "F,ACSI #0:,2|hd+img;"                // fileselector for ACSI 0
  "F,ACSI #1:,3|hd+img;"                // fileselector for ACSI 1
  "L,Disk prot.:,None|A:|B:|Both,P;";   // Enable/Disable Floppy write protection

static const char settings_form_atari_st[] =
  "Settings,0|4;"                       // return to form 0, entry 4
  // --------
  "L,Screen:,Normal|Wide,W;"
  "L,Scanlines:,None|25%|50%|75%,S;"
  "L,Volume:,Mute|33%|66%|100%,A;"
  "B,Save settings,S;";

static const char *forms_atari_st[] = {
  main_form_atari_st,
  system_form_atari_st,
  storage_form_atari_st,
  settings_form_atari_st
};

// variable ids must match the ones in the menu string
menu_variable_t variables_atari_st[] = {
  { 'C', { 0 }},    // default chipset = ST
  { 'M', { 0 }},    // default memory = 4MB
  { 'V', { 0 }},    // default video = color
  { 'S', { 0 }},    // default scanlines = none
  { 'A', { 1 }},    // default volume = 33%
  { 'W', { 0 }},    // default normal (4:3) screen
  { 'P', { 0 }},    // default no floppy write protected
  { 'Q', { 0 }},    // default cubase dongle not enabled
  { 'J', { 0 }},    // default mouse USB, DB9 connector joystick
  { 'T', { 0 }},    // default primary TOS slot
  { '\0',{ 0 }}
};

// ------------------------------------------------------------------
// ------------------------  C64 menu -------------------------------
// ------------------------------------------------------------------

static const char main_form_c64[] =
  "C64Nano,;"                           // main form has no parent
  // --------
  "F,Floppy 8:,0|d64+g64;"              // fileselector for Floppy 8:
  "S,System,1;"                         // System submenu is form 1
  "S,Storage,2;"                        // Storage submenu
  "S,Settings,3;"                       // Settings submenu is form 2
  "B,Reset,R;";                         // system reset

static const char system_form_c64[] =
  "System,0|2;"                         // return to form 0, entry 2
  // --------
  "L,Joyport 1:,Retro D9|USB #1|USB #2|NumPad|DualShock|Mouse|Paddle|Off,Q;"
  "L,Joyport 2:,Retro D9|USB #1|USB #2|NumPad|DualShock|Mouse|Paddle|Off,J;"
  "L,REU 1750:,Off|On,V;"
  "L,c1541 ROM:,Dolphin DOS|CBM DOS|Speed DOS P|Jiffy DOS,D;"
  "L,Turbo mode:,Off|C128|Smart,X;"
	"L,Turbo speed:,2x|3x|4x,Y;"
  "L,Video Std:,PAL|NTSC,E;"
  "L,Midi:,Off|Sequential|Passport|DATEL|Namesoft,N;"
  "L,Pause OSD:,Off|On,G;"
  "L,VIC-II:,656x|856x|Early 856x,C;"
  "L,CIA:,6526|8521,M;"
  "L,SID:,6581|8580,O;"
  "L,SID Digifix:,Off|On,U;"
  "L,SID Right:,Same|DE00|D420|D500|DF00,K;"
  "L,SID Filter:,Default|Custom 1|Custom 2|Custom 3|Adjustable,H;"
  "L,SID Fc Ofs:,0|1|2|3|4|5,>;"
  "L,RS232 mode:,VIC-1011|UP9600,<;"
  "L,GeoRAM:,Off|On,#;"
  "L,Tape Sound:,Off|On,I;"
  "B,C1541 Reset,Z;"
  "B,Cold Boot,B;"; 

static const char storage_form_c64[] =
  "Storage,0|3;"                        // return to form 0, entry 3
  // --------
  "F,Floppy 8:,0|d64+g64;"              // fileselector for Disk Drive 8:
  "F,CRT ROM:,1|crt;"                   // fileselector for CRT
  "F,PRG BASIC:,2|prg;"                 // fileselector for PRG
  "F,C64 Kernal:,3|bin;"                // fileselector for Kernal ROM
  "F,TAP Tape:,4|tap;"                  // fileselector for TAP
  "L,Disk prot.:,None|8:,P;";           // Enable/Disable Floppy write protection

static const char settings_form_c64[] =
  "Settings,0|4;"                       // return to form 0, entry 3
  // --------
  "L,Screen:,Normal|Wide,W;"
  "L,Scanlines:,None|25%|50%|75%,S;"
  "L,Volume:,Mute|33%|66%|100%,A;"
  "B,Save settings,S;";

static const char *forms_c64[] = {
  main_form_c64,
  system_form_c64,
  storage_form_c64,
  settings_form_c64
};

menu_variable_t variables_c64[] = {
  { 'U', { 0 }},    // default digifix = disabled
  { 'X', { 0 }},    // default turbo mode = off
  { 'Y', { 0 }},    // default turbo speed = 2x
  { 'D', { 0 }},    // default c1541 dos = dolphin
  { 'V', { 0 }},    // default reu = disabled
  { 'S', { 0 }},    // default scanlines = none
  { 'A', { 2 }},    // default volume = 66%
  { 'W', { 0 }},    // default normal (4:3) screen
  { 'P', { 0 }},    // default no floppy write protected
  { 'Q', { 7 }},    // Joystick port 1 mapping, OFF
  { 'J', { 0 }},    // Joystick port 2 mapping, DB9
  { 'E', { 0 }},    // default standard = PAL
  { 'N', { 0 }},    // default MIDI = Off
  { 'G', { 0 }},    // default OSD Pause = Off
  { 'C', { 0 }},    // default CIA 6526
  { 'M', { 0 }},    // default VIC-II 656x
  { 'O', { 0 }},    // default SID 6581
  { 'K', { 0 }},    // default right SID addr = same
  { 'I', { 1 }},    // default Tape sound = On
  { '>', { 0 }},    // default SID FC Offset
  { 'H', { 0 }},    // default SID Filter = default
  { '#', { 0 }},    // default GeoRAM = off
  { '<', { 0 }},    // default RS232 mode = standard
  { '\0',{ 0 }}
};

// ------------------------------------------------------------------
// ------------------------  VIC20 menu -------------------------------
// ------------------------------------------------------------------

static const char main_form_vic20[] =
  "VIC20Nano,;"                         // main form has no parent
  // --------
  "F,Floppy 8:,0|d64+g64;"              // fileselector for Floppy 8:
  "S,System,1;"                         // System submenu is form 1
  "S,Storage,2;"                        // Storage submenu
  "S,Settings,3;"                       // Settings submenu is form 2
  "B,Reset,R;";                         // system reset

static const char system_form_vic20[] =
  "System,0|2;"                         // return to form 0, entry 2
  // --------
  "L,Joyport:,Retro D9|USB #1|USB #2|NumPad|DualShock|Mouse|Paddle|Off,Q;" // Joystick port 1 mapping
  "L,c1541 ROM:,Dolphin DOS|CBM DOS|Speed DOS P|Jiffy DOS,D;"  // c1541 compatibility
  "L,RAM $04 3K:,Off|On,U;"
  "L,RAM $20 8K:,Off|On,X;"
  "L,RAM $40 8K:,Off|On,Y;"
  "L,RAM $60 8K:,Off|On,N;"
  "L,RAM $A0 8K:,Off|On,G;"
  "L,Video Std:,PAL|NTSC,E;"
  "L,Vid. cent:,Off|Both|Horz|Vert,J;"
  "L,CRT write:,Off|On,V;"
  "L,Tape Sound:,Off|On,I;"
  "B,c1541 Reset,Z;"
  "B,Cold Boot,B;"; 

static const char storage_form_vic20[] =
  "Storage,0|3;"                        // return to form 0, entry 3
  // --------
  "F,Floppy 8:,0|d64+g64;"              // fileselector for Disk Drive 8:
  "F,CRT ROM:,1|prg+crt;"               // fileselector for CRT (special VIC20 prg)
  "F,PRG BASIC:,2|prg;"                 // fileselector for PRG
  "F,VIC20 Kernal:,3|bin;"              // fileselector for Kernal ROM
  "F,TAP Tape:,4|tap;"                  // fileselector for TAP
  "L,Disk prot.:,None|8:,P;";           // Enable/Disable Floppy write protection

static const char settings_form_vic20[] =
  "Settings,0|4;"                       // return to form 0, entry 3
  // --------
  "L,Screen:,Normal|Wide,W;"
  "L,Scanlines:,None|25%|50%|75%,S;"
  "L,Volume:,Mute|33%|66%|100%,A;"
  "B,Save settings,S;";

static const char *forms_vic20[] = {
  main_form_vic20,
  system_form_vic20,
  storage_form_vic20,
  settings_form_vic20
};

menu_variable_t variables_vic20[] = {
  { 'U', { 0 }},    // default 3k, $0400
  { 'X', { 0 }},    // default 8k, $2000
  { 'Y', { 0 }},    // default 8k, $4000
  { 'N', { 0 }},    // default 8k, $6000
  { 'G', { 0 }},    // default 8k, $A000 Cartridge area
  { 'D', { 1 }},    // default c1541 dos = CBM
  { 'S', { 0 }},    // default scanlines = none
  { 'A', { 2 }},    // default volume = 66%
  { 'W', { 0 }},    // default normal (4:3) screen
  { 'P', { 0 }},    // default no floppy write protected
  { 'Q', { 0 }},    // Joystick port 1 mapping = DB9
  { 'E', { 0 }},    // default standard = PAL
  { 'J', { 1 }},    // Screen center = Both
  { 'V', { 1 }},    // Cartridge writable = On
  { 'I', { 1 }},    // default Tape sound = On
  { '\0',{ 0 }}
};

// ------------------------------------------------------------------
// -----------------------  Amiga menu ------------------------------
// ------------------------------------------------------------------

static const char main_form_amiga[] =
  "NanoMig,;"                           // main form has no parent
  // --------
  "F,Floppy DF0:,0|adf;"                // fileselector for DF0
  "F,Floppy DF1:,1|adf;"                // fileselector for DF1
  "B,Reset,R;";                         // system reset

static const char *forms_amiga[] = {
  main_form_amiga
};

menu_variable_t variables_amiga[] = {
  { '\0',{ 0 }}
};

static void menu_goto_form(menu_t *menu, int form, int entry) {
  menu->form = form;
  menu->entry = entry;
  menu->entries = -1;
  menu->offset = 0;
  menu->info_tick = 0;
}

// Indexed by core_id, so the order here has to match the CORE_ID_*
// defines in sysctrl.h and not the order the cores were written in.
// CORE_ID_VIC20 is 0x10 and cannot be an index into this - it is handled
// separately in settings_file_name() below.
static const char *settings_file[] = {
  NULL,                            // core id = 0  CORE_ID_UNKNOWN
  CARD_MOUNTPOINT "/atarist.ini",  // core id = 1  CORE_ID_ATARI_ST
  CARD_MOUNTPOINT "/c64.ini",      // core id = 2  CORE_ID_C64
  CARD_MOUNTPOINT "/uneon.ini",    // core id = 3  CORE_ID_UNEON
  CARD_MOUNTPOINT "/amiga.ini",    // core id = 4  CORE_ID_AMIGA
  CARD_MOUNTPOINT "/uknc.ini",     // core id = 5  CORE_ID_UKNC
  CARD_MOUNTPOINT "/agat9.ini"     // core id = 6  CORE_ID_AGAT9
};

// Returns NULL for a core with no settings file of its own, which both
// callers check: opening NULL would take FatFs down.
static const char *settings_file_name(void) {
  if(core_id == CORE_ID_VIC20) return CARD_MOUNTPOINT "/vic20.ini";
  if(core_id < sizeof(settings_file)/sizeof(settings_file[0]))
    return settings_file[core_id];
  return NULL;
}

static int iswhite(char c) {
  return c == ' ' || c == '\r' || c == '\n' || c == '\t';
}

static int menu_settings_load(menu_t *menu) {
  printf("Read settings\r\n");

  sdc_lock();  // get exclusive access to the file system

  FIL fil;
  const char *fname = settings_file_name();
  if(!fname) { sdc_unlock(); return 0; }
  if(f_open(&fil, fname, FA_OPEN_EXISTING | FA_READ) == FR_OK) {    
    char buffer[FF_LFN_BUF+10];

    printf("Settings file opened\r\n");
    
    // read file line by line
    while(f_gets(buffer, sizeof(buffer), &fil) != NULL) {
      // ignore everything after semicolon
      char *pos = strchr(buffer, ';');
      if(pos) *pos = '\0';

      // also skip all trailing white space
      while(strlen(buffer) > 0 && iswhite(buffer[strlen(buffer)-1]))
	buffer[strlen(buffer)-1] = 0;

      // printf("Line = '%s'\n", buffer);
	
      // check for old style entries which were just two characters long
      if(strlen(buffer) == 2) {
	int value = atoi(buffer+1);
	printf("  %c:%d\r\n", buffer[0], value);

	for(int i=0;menu->vars[i].id;i++)
	  if(menu->vars[i].id == buffer[0])
	    menu->vars[i].value = value;
      } else {
	// check for drives
	if(strncasecmp(buffer, "drive", 5) == 0) {
	  char * p = buffer+5;  // skip 'drive'
	  while(*p && iswhite(*p)) p++;
	  if(*p) {
	    int drive = *p-'0';
	    // skip after '='
	    while(*p && *p != '=') p++;
	    p++;
	    if(*p) {
	      // skip to begin of filename
	      while(*p && iswhite(*p)) p++;
	      if(*p) {
		// tell SDC layer what images to use as default
		printf("drive %d = %s\r\n", drive, p);		
		sdc_set_default(drive, p);
	      }
	    }
	  }
	}
	  
	// check for variables
	if(strncasecmp(buffer, "var ", 4) == 0) {
	  
	  // --- parse 'var x=0` style lines ---
	  // skip "var"
	  char *p = buffer+4;
	  // skip to first char
	  while(*p && iswhite(*p)) p++;
	  if(*p) {	  
	    char id = *p++;
	    // skip until '='
	    while(*p && *p != '=') p++;
	    p++;  // skip =
	    if(*p) {
	      // skip all whites
	      while(*p && iswhite(*p)) p++;
	      if(*p) {
		int value = atoi(p);
		printf("var %c = %d\r\n", id, value);
		
		for(int i=0;menu->vars[i].id;i++)
		  if(menu->vars[i].id == id)
		    menu->vars[i].value = value;
	      }
	    }
	  }
	}
	
      }
    }
    f_close(&fil);
  } else {
    printf("Error opening file %s\r\n", fname);
    sdc_unlock();
    return -1;
  }
  
  sdc_unlock();
  return 0;
}

static void menu_settings_save(menu_t *menu) {
  printf("Write settings\r\n");
  
  sdc_lock();  // get exclusive access to the file system
  
  // saving does not work, yet, as there is no SD card write support by now
  FIL file;
  const char *fname = settings_file_name();
  if(!fname) { sdc_unlock(); return; }
  if(f_open(&file, fname, FA_WRITE | FA_CREATE_ALWAYS) == FR_OK) {
    f_puts("; MiSTeryNano settings\n", &file);

    // write variable values
    f_puts("\n; variables\n", &file);
    for(int i=0;menu->vars[i].id;i++) {
      char str[10];
      sprintf(str, "var %c=%d\n", menu->vars[i].id, menu->vars[i].value);
      f_puts(str, &file);
    }

    // write image file names
    f_puts("\n; image files\n", &file);

    for(int drive=0;drive<MAX_DRIVES;drive++) {
      char *cwd = sdc_get_cwd(drive);
      char *image = sdc_get_image_name(drive);

      if(cwd && image) {
	char str[strlen(cwd) + strlen(image) + 12];
	sprintf(str, "drive%d=%s/%s\n", drive, cwd, image);
	f_puts(str, &file);
      }      
    }
    
    f_puts("\n", &file);
    
    f_close(&file);  
  } else
    printf("Error opening file\r\n");
  
  sdc_unlock();
}

#ifndef SDL
menu_t *menu_init(spi_t *spi)
#else
menu_t *menu_init(u8g2_t *u8g2)
#endif
{
  static menu_t menu;
  memset(&menu, 0, sizeof(menu));

  if(core_id == CORE_ID_ATARI_ST) {
    menu.vars = variables_atari_st;
    menu.forms = forms_atari_st;
  } else if(core_id == CORE_ID_C64) {
    menu.vars = variables_c64;
    menu.forms = forms_c64;
  } else if(core_id == CORE_ID_UNEON) {
    menu.vars = variables_uneon;
    menu.forms = forms_uneon;
  } else if(core_id == CORE_ID_VIC20) {
    menu.vars = variables_vic20;
    menu.forms = forms_vic20;
  } else if(core_id == CORE_ID_AMIGA) {
    menu.vars = variables_amiga;
    menu.forms = forms_amiga;
  } else if(core_id == CORE_ID_UKNC) {
    menu.vars = variables_uknc;
    menu.forms = forms_uknc;
  } else if(core_id == CORE_ID_AGAT9) {
    menu.vars = variables_agat9;
    menu.forms = forms_agat9;
  } else {
    menu.vars = NULL;
    menu.forms = NULL;
  }
  
  menu_goto_form(&menu, 0, 1); // first form selected at start
      
#ifndef SDL
  menu.osd = osd_init(spi);
#else
  static osd_t losd;
  menu.osd = &losd;
  menu.osd->u8g2 = *u8g2;
#endif

  // give sd card 2 seconds to become ready
  int timeout = 200;
  while(timeout && !sdc_is_ready()) {
    vTaskDelay(pdMS_TO_TICKS(10));
    timeout--;
  }

  // load data from sd card if available
  if(timeout) {
    printf("SD ready after %dms\r\n", (200-timeout)*10);
    
    // try to restore variables from eeprom
    if(menu_settings_load(&menu) != 0) {
      // if no settings could be loaded, then set default
      // image names

      if(core_id == CORE_ID_ATARI_ST) {
	static const char *default_names[] = {
	  CARD_MOUNTPOINT "/disk_a.st",
	  CARD_MOUNTPOINT "/disk_b.st",
	  CARD_MOUNTPOINT "/acsi_0.hd",
	  CARD_MOUNTPOINT "/acsi_1.hd" };
	
	for(int drive=0;drive<4;drive++)
	  sdc_set_default(drive, default_names[drive]);
      } else if(core_id == CORE_ID_C64) {
    // C64 core
	static const char *c64_default_names[] = {
	  CARD_MOUNTPOINT "/disk8.d64",
	  CARD_MOUNTPOINT "/c64crt.crt",
	  CARD_MOUNTPOINT "/c64prg.prg",
	  CARD_MOUNTPOINT "/c64kernal.bin",
	  CARD_MOUNTPOINT "/c64tap.tap"};

	for(int drive=0;drive<MAX_DRIVES;drive++)
	  sdc_set_default(drive, c64_default_names[drive]);
    } else if(core_id == CORE_ID_VIC20) {
	// VIC20 core
	static const char *vic20_default_names[] = {
	  CARD_MOUNTPOINT "/disk8.d64",
	  CARD_MOUNTPOINT "/vic20crt.crt",
	  CARD_MOUNTPOINT "/vic20prg.prg",
	  CARD_MOUNTPOINT "/vic20kernal.bin",
	  CARD_MOUNTPOINT "/vic20tap.tap"};

	for(int drive=0;drive<MAX_DRIVES;drive++)
	  sdc_set_default(drive, vic20_default_names[drive]);
    } else if(core_id == CORE_ID_AMIGA) {
	// Amiga core
	static const char *amiga_default_names[] = {
	  CARD_MOUNTPOINT "/df0.adf",
	  CARD_MOUNTPOINT "/df1.adf",
	  CARD_MOUNTPOINT "/df2.adf",
	  CARD_MOUNTPOINT "/df3.adf" };

	for(int drive=0;drive<4;drive++)
	  sdc_set_default(drive, amiga_default_names[drive]);
    }
    }
  
  // try to mount (default) images
  for(int drive=0;drive<MAX_DRIVES;drive++) {
    char *name = sdc_get_image_name(drive);
    
    if(name) {
      // create a local copy as sdc_image_open frees its own copy
      char local_name[strlen(name)+1];
      strcpy(local_name, name);
      
      sdc_image_open(drive, local_name);
    }
  }
  } else
    printf("SD wasn't ready, not loading settings\r\n");

  // the UKNC's main form depends on a setting, so it is built now
  if(core_id == CORE_ID_UKNC) menu_uknc_main(&menu);
   
  // send initial values for all variables
  for(int i=0;menu.vars[i].id;i++)
    sys_set_val(menu.osd->spi, menu.vars[i].id, menu.vars[i].value);

  // release the core's reset, so it can start
  // and cold reset the core, just in case ...
  sys_set_val(menu.osd->spi, 'R', 3);
  sys_set_val(menu.osd->spi, 'R', 0);

  if(core_id == CORE_ID_C64||core_id == CORE_ID_VIC20) {  // c64 core, c1541 reset at power-up
    sys_set_val(menu.osd->spi, 'Z', 1);
    sys_set_val(menu.osd->spi, 'Z', 0);
  }
  return &menu;
}

// find first occurence of any char in chrs within str
const char *strchrs(const char *str, char *chrs) {
  while(*str) {
    for(int i=0;i<strlen(chrs);i++)
      if(*str == chrs[i]) return str;
    str++;
  }
  return NULL;
}

// get the n'th substring in colon separated string
static const char *menu_get_str(menu_t *menu, const char *s, int n) {
  while(n--) {
    s = strchr(s, ',');   // skip n substrings
    if(!s) return NULL;
    s = s + 1;
  }
  return s;
}

// get the n'th char in colon separated string
static char menu_get_chr(menu_t *menu, const char *s, int n) {
  while(n--) {
    s = strchr(s, ',');   // skip n substrings
    if(!s) return '\0';
    s = s + 1;
  }
  return s[0];
}

// get the n'th substring in | separated string in a colon string
static const char *menu_get_substr(menu_t *menu, const char *s, int n, int m) {
  while(n--) {
    s = strchr(s, ',');   // skip n substrings
    if(!s) return NULL;
    s = s + 1;
  }
  
  while(m--) {
    s = strchr(s, '|');   // skip m subsubstrings
    if(!s) return NULL;
    s = s + 1;
  }
  return s;
}
  
static int menu_get_int(menu_t *menu, const char *s, int n) {
  const char *str = menu_get_str(menu, s, n);
  if(!str) return(-1);

  // The string may not be 0 terminated, but rather ; or : terminated.
  // This is fine as atoi stops parsing at the first non-digit
  return atoi(str);
}

static int menu_get_subint(menu_t *menu, const char *s, int n, int m) {
  const char *str = menu_get_substr(menu, s, n, m);
  if(!str) return(-1);
  return atoi(str);
}

static int menu_variable_get(menu_t *menu, const char *s) {
  char id = menu_get_chr(menu, s, MENU_ENTRY_INDEX_VARIABLE);
  if(id == -1) return -1;

  for(int i=0;menu->vars[i].id;i++)
    if(menu->vars[i].id == id)
      return menu->vars[i].value;    

  return -1;
}

static void menu_variable_set(menu_t *menu, const char *s, int val) {
  char id = menu_get_chr(menu, s, MENU_ENTRY_INDEX_VARIABLE);
  if(id == -1) return;
  
  for(int i=0;menu->vars[i].id;i++) {
    if(menu->vars[i].id == id) {
      menu->vars[i].value = val;

      // also set this in the core
      sys_set_val(menu->osd->spi, id, val);

      // the UKNC's HDD controller switch adds or removes HDD0: on the main form
      if(core_id == CORE_ID_UKNC && id == 'e') menu_uknc_main(menu);

      if(core_id == CORE_ID_ATARI_ST) {      
	// trigger cold reset if memory, chipset or TOS have been changed a
	// video change will also trigger a reset, but that's handled by
	// the ST itself
	if((id == 'C') || (id == 'M') || (id == 'T')) {
	  sys_set_val(menu->osd->spi, 'R', 3);
	  sys_set_val(menu->osd->spi, 'R', 0);
	}
      }
  if(core_id == CORE_ID_C64||core_id == CORE_ID_VIC20){
    // c64 core, trigger core reset if Video mode / PLL changes
    if(id == 'E') {
      sys_set_val(menu->osd->spi, 'R', 3);
      sys_set_val(menu->osd->spi, 'R', 0); }
    // c64 core, trigger c1541 reset in case DOS ROM changed
    if(id == 'D') {  
        sys_set_val(menu->osd->spi, 'Z', 1);
        sys_set_val(menu->osd->spi, 'Z', 0); }
    }
    }
  }
}
  
static int menu_get_options(menu_t *menu, const char *s, int n) {
  // get possible number of values
  int num = 1;
  const char *v = menu_get_str(menu, s, n);
  // count all '|' before next ';', ',' or '\0'
  while(*v && *v != ';' && *v != ',') {
    if(*v == '|') num++;
    v++;
  }
  return num;
}

// the n'th entry of a form (1 = the first after the title), or NULL
static const char *menu_entry_at(menu_t *menu, const char *form, int n) {
  const char *s = form;
  for(int i=0;i<n;i++) {
    s = strchr(s, ';');
    if(!s) return NULL;
    s++;
  }
  return *s ? s : NULL;
}

// the entry in `parent` whose submenu is `form`, for returning to it;
// the number the form's title names is the fallback
static int menu_parent_entry(menu_t *menu, int parent, int form, int fallback) {
  for(int n=1;;n++) {
    const char *e = menu_entry_at(menu, menu->forms[parent], n);
    if(!e) return fallback;
    if(e[0] == 'S' && menu_get_int(menu, e, MENU_ENTRY_INDEX_FORM) == form) return n;
  }
}

// width of a ';', ',' or '|' terminated string in the current font
static int menu_strw(menu_t *menu, const char *s) {
  int n = 0;
  while(s[n] && s[n] != ';' && s[n] != ',' && s[n] != '|') n++;
  char buffer[n+1];
  strncpy(buffer, s, n);
  buffer[n] = '\0';
  return u8g2_GetStrWidth(MENU2U8G2(menu), buffer);
}

// various 8x8 icons
const static unsigned char icn_right_bits[]  = { 0x00,0x04,0x0c,0x1c,0x3c,0x1c,0x0c,0x04 };
const static unsigned char icn_left_bits[]   = { 0x00,0x20,0x30,0x38,0x3c,0x38,0x30,0x20 };
const static unsigned char icn_floppy_bits[] = { 0xff,0x81,0x83,0x81,0xbd,0xad,0x6d,0x3f };
const static unsigned char icn_empty_bits[] =  { 0xc3,0xe7,0x7e,0x3c,0x3c,0x7e,0xe7,0xc3 };

void u8g2_DrawStrT(u8g2_t *u8g2, u8g2_uint_t x, u8g2_uint_t y, const char *s) {
  // get length of string
  int n = 0;
  while(s[n] && s[n] != ';' && s[n] != ',' && s[n] != '|') n++;

  // create a 0 terminated copy in the stack
  char buffer[n+1];
  strncpy(buffer, s, n);
  buffer[n] = '\0';
  
  u8g2_DrawStr(u8g2, x, y, buffer);
}

// Draw menu title. Submenu titles are selectable and can be used to return to the
// parent menu.
static void menu_draw_title(menu_t *menu, const char *s) {
  int x = 1;

  // draw left arrow for submenus
  if(menu->form) {
    u8g2_DrawXBM(MENU2U8G2(menu), 0, 1, 8, 8, icn_left_bits);    
    x = 8;
  }

  // the version (../VERSION) at the right of the main form's caption
  if(!menu->form && core_id == CORE_ID_UKNC && UKNC_VERSION[0]) {
    u8g2_SetFont(MENU2U8G2(menu), font_helvR08_te);
    int w = u8g2_GetStrWidth(MENU2U8G2(menu), UKNC_VERSION);
    u8g2_DrawStr(MENU2U8G2(menu), u8g2_GetDisplayWidth(MENU2U8G2(menu)) - w - 1, 9, UKNC_VERSION);
  }

  // draw title in bold and seperator line
  u8g2_SetFont(MENU2U8G2(menu), u8g2_font_helvB08_tr);
  u8g2_DrawStrT(MENU2U8G2(menu), x, 9, menu_get_str(menu, s, 0));
  u8g2_DrawHLine(MENU2U8G2(menu), 0, 13, u8g2_GetDisplayWidth(MENU2U8G2(menu)));

  if(x > 0 && menu->entry == 0)
    u8g2_DrawButtonFrame(MENU2U8G2(menu), 0, 9, U8G2_BTN_INV, u8g2_GetDisplayWidth(MENU2U8G2(menu)), 1, 1);
  
  // draw the rest with normal font
  u8g2_SetFont(MENU2U8G2(menu), font_helvR08_te);
}

// An 'I' (info) entry shows a value the menu computes rather than a
// label, and cannot be selected.  The label names what: "rtc" is the
// UKNC core's clock, read back over SPI and redrawn once a second.
static void menu_info_text(menu_t *menu, const char *s, char *buf, int len) {
  const char *what = menu_get_str(menu, s, MENU_ENTRY_INDEX_LABEL);
  if(!strncmp(what, "rtc", 3)) {
    static const char *dow_name[] = { "---", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
    sys_rtc_t t;
    sys_get_rtc(menu->osd->spi, &t);
    snprintf(buf, len, "%04d-%02d-%02d %02d:%02d:%02d %s",
	     t.year, t.month, t.date, t.hour, t.min, t.sec,
	     dow_name[(t.dow >= 1 && t.dow <= 7) ? t.dow : 0]);
  } else
    strncpy(buf, what, len);
}

static void menu_draw_entry(menu_t *menu, int y, const char *s) {
  const char *buf = menu_get_str(menu, s, MENU_ENTRY_INDEX_LABEL);
  char info[32];

  // the "Run SAV:" line carries its progress instead of its label
  if(s[0] == 'F' && sav_status[0] && menu_get_subint(menu, s, 2, 0) == SDC_SLOT_SAV)
    buf = sav_status;

  // an info line is computed
  if(s[0] == 'I') {
    menu_info_text(menu, s, info, sizeof(info));
    buf = info;
  }

  int ypos = 13 + 12 * y;
  int width = u8g2_GetDisplayWidth(MENU2U8G2(menu));

  // all menu entries are a plain text
  u8g2_DrawStrT(MENU2U8G2(menu), 1, ypos, buf);
    
  // prepare highlight
  int hl_x = 0;
  int hl_w = width;
  
  // handle second string for 'L'ist entries
  if(s[0] == 'L') {
    // get variable
    int value = menu_variable_get(menu, s);
    const char *val = menu_get_substr(menu, s, MENU_ENTRY_INDEX_OPTIONS, value);

    // The value sits in the right half unless the label or the value is
    // too wide for that: then it moves right of the label, and left as
    // far as it needs to fit the screen, never over the label.
    int lw = menu_strw(menu, buf) + 5;
    int vw = val ? menu_strw(menu, val) + 1 : 0;
    int vx = width/2;
    if(vx < lw) vx = lw;
    if(vx + vw > width) vx = width - vw;
    if(vx < lw) vx = lw;

    if(val) u8g2_DrawStrT(MENU2U8G2(menu), vx, ypos, val);
		  
    hl_x = vx;
    hl_w = width - vx;
  }
  
  // some entries have a small icon to the right    
  if(s[0] == 'S' || s[0] == 'T')
    u8g2_DrawXBM(MENU2U8G2(menu), hl_w-8, ypos-8, 8, 8, icn_right_bits);    
  if(s[0] == 'F' && menu_get_subint(menu, s, 2, 0) != SDC_SLOT_SAV) {
    // icon depends if floppy is inserted; the "Run SAV:" browser mounts
    // nothing, so it shows neither
    u8g2_DrawXBM(MENU2U8G2(menu), hl_w-9, ypos-8, 8, 8,
	sdc_get_image_name(menu_get_subint(menu, s, 2, 0))?icn_floppy_bits:icn_empty_bits);
  }
  
  if(y+menu->offset == menu->entry && s[0] != 'I')
    u8g2_DrawButtonFrame(MENU2U8G2(menu), hl_x, ypos, U8G2_BTN_INV, hl_w, 1, 1);
}

static const int icon_skip = 10;

static void menu_fs_scroll_entry(menu_t *menu, sdc_dir_entry_t *entry) {
  int row = menu->entry - menu->offset - 1;
  int y =  13 + 12 * (row+1);
  int width = u8g2_GetDisplayWidth(MENU2U8G2(menu));
  int swid = u8g2_GetStrWidth(MENU2U8G2(menu), entry->name) + 1;

  // fill the area where the scrolling entry would show
  u8g2_SetClipWindow(MENU2U8G2(menu), icon_skip, y-9, width, y+12-9);  
  u8g2_DrawBox(MENU2U8G2(menu), icon_skip, y-9, width-icon_skip, 12);
  u8g2_SetDrawColor(MENU2U8G2(menu), 0);
  
  int scroll = menu->fs_scroll_cur++ - 25;   // 25 means 1 sec delay
  if(menu->fs_scroll_cur > swid-width+icon_skip+50) menu->fs_scroll_cur = 0;
  if(scroll < 0) scroll = 0;
  if(scroll > swid-width+icon_skip) scroll = swid-width+icon_skip;
  
  u8g2_DrawStr(MENU2U8G2(menu), icon_skip-scroll, y, entry->name);      

  // restore previous draw mode
  u8g2_SetDrawColor(MENU2U8G2(menu), 1);
  u8g2_SetMaxClipWindow(MENU2U8G2(menu));
  u8g2_SendBuffer(MENU2U8G2(menu));
}

static void menu_fs_draw_entry(menu_t *menu, int row, sdc_dir_entry_t *entry) {      
  static const unsigned char folder_icon[] = { 0x70,0x8e,0xff,0x81,0x81,0x81,0x81,0x7e };
  static const unsigned char up_icon[] =     { 0x04,0x0e,0x1f,0x0e,0xfe,0xfe,0xfe,0x00 };
  static const unsigned char empty_icon[] =  { 0xc3,0xe7,0x7e,0x3c,0x3c,0x7e,0xe7,0xc3 };
  
  char str[strlen(entry->name)+1];
  int y =  13 + 12 * (row+1);

  // ignore leading / used by special entries
  if(entry->name[0] == '/') strcpy(str, entry->name+1);
  else                      strcpy(str, entry->name);
  
  int width = u8g2_GetDisplayWidth(MENU2U8G2(menu));
  
  // properly ellipsize string
  int dotlen = u8g2_GetStrWidth(MENU2U8G2(menu), "...");
  if(u8g2_GetStrWidth(MENU2U8G2(menu), str) > width-icon_skip) {
    // the entry is too long to fit the menu.    
    if(menu->entry == row+menu->offset+1) {
      menu->fs_scroll_cur = 0;
      menu->fs_scroll_entry = entry;
#ifndef SDL
      // enable timer, to allow animations
      xTimerStart(menu->osd->timer, 0);
#endif
    }
    
    while(u8g2_GetStrWidth(MENU2U8G2(menu), str) > width-icon_skip-dotlen) str[strlen(str)-1] = 0;
    if(strlen(str) < sizeof(str)-4) strcat(str, "...");
  }
  u8g2_DrawStr(MENU2U8G2(menu), icon_skip, y, str);      
  
  // draw folder icon in front of directories
  if(entry->is_dir)
    u8g2_DrawXBM(MENU2U8G2(menu), 1, y-8, 8, 8,
		 (entry->name[0] == '/')?empty_icon:
		 strcmp(entry->name, "..")?folder_icon:
		 up_icon);

  if(menu->entry == row+menu->offset+1)
    u8g2_DrawButtonFrame(MENU2U8G2(menu), 0, y, U8G2_BTN_INV, width, 1, 1);     
}

// ------------------------------------------------------------------
// The text view: a 'T' entry opens a page of text (the UKNC's "About")
// that scrolls with the cursor keys and returns on Space, Enter or the
// title.  The paragraphs are wrapped to the OSD's width in the menu font
// when the page is opened; MENU_TEXT_LINES lines of MENU_TEXT_COLS at most.
// ------------------------------------------------------------------
#define MENU_TEXT_LINES 48
#define MENU_TEXT_COLS  40
#define MENU_TEXT_ROWS  4               // lines under the title

static char  text_lines[MENU_TEXT_LINES][MENU_TEXT_COLS];
static int   text_nlines;
static int   text_parent, text_entry;   // where to return to
static const char *text_title;

static void menu_text_add(menu_t *menu, const char *line) {
  if(text_nlines >= MENU_TEXT_LINES) return;
  strncpy(text_lines[text_nlines], line, MENU_TEXT_COLS-1);
  text_lines[text_nlines][MENU_TEXT_COLS-1] = 0;
  text_nlines++;
}

// wrap one paragraph on spaces; a word wider than the screen is cut
static void menu_text_wrap(menu_t *menu, const char *para) {
  int width = u8g2_GetDisplayWidth(MENU2U8G2(menu)) - 2;
  char line[MENU_TEXT_COLS];
  int len = 0;
  line[0] = 0;

  if(!*para) { menu_text_add(menu, ""); return; }

  while(*para) {
    // the next word
    const char *w = para;
    while(*para && *para != ' ') para++;
    int wl = para - w;
    while(*para == ' ') para++;

    char cand[MENU_TEXT_COLS];
    int cl = 0;
    if(len) { memcpy(cand, line, len); cand[len++] = ' '; }
    cl = len;
    int take = wl;
    if(cl + take >= MENU_TEXT_COLS) take = MENU_TEXT_COLS - 1 - cl;
    if(take < 0) take = 0;
    memcpy(cand+cl, w, take); cand[cl+take] = 0;

    if(take == wl && u8g2_GetStrWidth(MENU2U8G2(menu), cand) <= width) {
      memcpy(line, cand, cl+take+1); len = cl+take;
      continue;
    }
    // the word does not fit after what is there: flush the line
    if(len) { menu_text_add(menu, line); len = 0; line[0] = 0; }
    // and start a new one with as much of the word as fits
    take = wl < MENU_TEXT_COLS-1 ? wl : MENU_TEXT_COLS-1;
    memcpy(line, w, take); line[take] = 0;
    while(take > 1 && u8g2_GetStrWidth(MENU2U8G2(menu), line) > width) line[--take] = 0;
    len = take;
    if(take < wl) { menu_text_add(menu, line); len = 0; line[0] = 0; }   // the rest of a giant word is dropped
  }
  if(len) menu_text_add(menu, line);
}

static void menu_text_open(menu_t *menu, const char *title, const char **paras) {
  u8g2_SetFont(MENU2U8G2(menu), font_helvR08_te);
  text_nlines = 0;
  for(int i=0;paras[i];i++) menu_text_wrap(menu, paras[i]);
  text_title  = title;
  text_parent = menu->form;
  text_entry  = menu->entry;
  menu_goto_form(menu, MENU_FORM_TEXT, 0);
}

static void menu_text_draw(menu_t *menu) {
  menu_draw_title(menu, text_title);
  for(int i=0;i<MENU_TEXT_ROWS && i+menu->offset<text_nlines;i++)
    u8g2_DrawStr(MENU2U8G2(menu), 1, 13 + 12 * (i+1), text_lines[i+menu->offset]);
}

static void menu_text_scroll(menu_t *menu, int step) {
  int max = text_nlines - MENU_TEXT_ROWS;
  if(max < 0) max = 0;
  menu->offset += step;
  if(menu->offset < 0) menu->offset = 0;
  if(menu->offset > max) menu->offset = max;
}

// ------------------------------------------------------------------
// "Run SAV:" - a .SAV picked in the file selector becomes a bootable
// RT-11 floppy in FDD 0 (rt11sav.c).  The main-form entry shows the
// progress in place of its label: "making DSK" while the card is being
// written, then "err: ..." or "done: RT11SAV.DSK", until the OSD is
// closed.  The work runs right here in the OSD task, so no other menu
// event is served until it is over, and whatever was typed meanwhile
// is dropped; the picked name is remembered in SDC_SLOT_SAV only, which
// the settings file never sees - FDD 0's new image is what "Save
// settings" would record, if asked.
// ------------------------------------------------------------------
static void menu_draw_form(menu_t *menu, const char *s);
static int fsel_entry = 1;   // the entry the file selector was opened from, to return to it

static unsigned menu_rt11_date(menu_t *menu) {
  int y = 0, m = 0, d = 0;
  for(int i=0;menu->vars[i].id;i++) {
    if(menu->vars[i].id == 'y') y = menu->vars[i].value;
    if(menu->vars[i].id == 'm') m = menu->vars[i].value;
    if(menu->vars[i].id == 'd') d = menu->vars[i].value;
  }
  return rt11sav_date(2020 + y, m + 1, d + 1);
}

static void menu_run_sav(menu_t *menu, int parent, const char *name) {
  // the directory listing that owns 'name' is rebuilt by the next
  // readdir, so keep a copy
  char fname[strlen(name)+1];
  strcpy(fname, name);
  sdc_set_image_name(SDC_SLOT_SAV, fname);

  // back on the "Run SAV:" line, saying what is going on, before the
  // long part starts
  menu_goto_form(menu, parent, fsel_entry);
  strcpy(sav_status, "making DSK");
  menu_draw_form(menu, menu->forms[menu->form]);

  // FDD 0 is about to be overwritten (it may be RT11SAV.DSK itself)
  sdc_image_open(0, NULL);

  char err[16];
  if(rt11sav_make(sdc_get_cwd(SDC_SLOT_SAV), fname, menu_rt11_date(menu), err, sizeof(err)) < 0)
    snprintf(sav_status, sizeof(sav_status), "err: %s", err);
  else {
    strcpy(sav_status, "done: " RT11SAV_DISK);
    char disk[] = RT11SAV_DISK;
    sdc_set_default(0, RT11SAV_DIR "/" RT11SAV_DISK);
    sdc_image_open(0, disk);
    // and boot it
    sys_set_val(menu->osd->spi, 'R', 1);
    sys_set_val(menu->osd->spi, 'R', 0);
  }

#ifndef SDL
  // keys pressed while the card was being written are not commands
  xQueueReset(xQueue);
#endif
}

// file selector events
#define FSEL_INIT   0
#define FSEL_DRAW   1
#define FSEL_DOWN   2
#define FSEL_UP     3
#define FSEL_SELECT 4

// process file selector events
static void menu_fileselector(menu_t *menu, int event) {
  static sdc_dir_t *dir = NULL;
  const static char *s;
  static int parent;
  static int drive;
  static const char *exts;
  
  if(event == FSEL_INIT) {
    // init
    s = menu->forms[menu->form];
    for(int i=0;i<menu->entry;i++) s = strchr(s, ';')+1;
    fsel_entry = menu->entry;

    // get extensions
    exts = menu_get_substr(menu, s, 2, 1);

    // scan files
    drive = menu_get_subint(menu, s, 2, 0);
    
    dir = sdc_readdir(drive, NULL, exts);

    menu->entry = 1;               // start by highlighting first file entry
    menu->entries = dir->len + 1;  // incl. title
    menu->offset = 0;
    parent = menu->form;
    menu->form = MENU_FORM_FSEL;

    // try to jump to current file. Get the current image name and path
    char *name = sdc_get_image_name(drive);
    if(name) {
      // try to find name in file list
      for(int i=0;i<dir->len;i++) {
	if(strcmp(dir->files[i].name, name) == 0) {
	  // file found, adjust entry and offset
	  menu->entry = i+1;
	  
	  if(menu->entries > 5 && menu->entry > 3) {
	    if(menu->entry < menu->entries-2) menu->offset = menu->entry - 3;
	    else                              menu->offset = menu->entries-5;
	  }
	}
      }
    }
  } else if(event == FSEL_DRAW) {
    // draw
    menu_draw_title(menu, menu_get_str(menu, s, MENU_ENTRY_INDEX_LABEL));
    
    // draw up to four files
    menu->fs_scroll_entry = NULL;  // assume no scrolling needed
#ifndef SDL
    xTimerStop(menu->osd->timer, 0);
#endif
    
    for(int i=0;i<((dir->len<4)?dir->len:4);i++)
      menu_fs_draw_entry(menu, i, &(dir->files[i+menu->offset]));
  } else if(event == FSEL_SELECT) {

    if(!menu->entry)
      menu_goto_form(menu, parent, fsel_entry);
    else {
      sdc_dir_entry_t *entry = &(dir->files[menu->entry - 1]);

      if(entry->is_dir) {
	if(entry->name[0] == '/') {
	  // User selected the "No Disk" entry
	  // Eject it and return to parent menu
	  menu_goto_form(menu, parent, fsel_entry);
	  if(drive == SDC_SLOT_SAV) sdc_set_image_name(drive, NULL);  // nothing mounted there to eject
	  else                      sdc_image_open(drive, NULL);
	} else {	
	  // check if we are going up one dir and try to select the
	  // directory we are coming from
	  char *prev = NULL; 
	  if(strcmp(entry->name, "..") == 0) {
	    prev = strrchr(sdc_get_cwd(drive), '/');
	    if(prev) prev++;
	  }
	  
	  menu->entry = 1;               // start by highlighting '..'
	  menu->offset = 0;
	  dir = sdc_readdir(drive, entry->name, exts);	
	  menu->entries = dir->len + 1;  // incl. title
	  
	  // prev is still valid, since sdc_readdir doesn't free the old string when going
	  // up one directory. Instead it just terminates it in the middle	
	  if(prev) {	
	    // try to find previous dir entry in current dir	  
	    for(int i=0;i<dir->len;i++) {
	      if(dir->files[i].is_dir && strcmp(dir->files[i].name, prev) == 0) {
		// file found, adjust entry and offset
		menu->entry = i+1;
		
		if(menu->entries > 5 && menu->entry > 3) {
		  if(menu->entry < menu->entries-2) menu->offset = menu->entry - 3;
		  else                              menu->offset = menu->entries-5;
		}
	      }
	    }
	  }
	}
      } else if(drive == SDC_SLOT_SAV) {
	// not a disk to mount: a program to build a disk around
	menu_run_sav(menu, parent, entry->name);
      } else {
	// request insertion of this image
	sdc_image_open(drive, entry->name);
	// return to parent form
	menu_goto_form(menu, parent, fsel_entry);
      }
    }
  }   
}

static void menu_draw_form(menu_t *menu, const char *s) {
  u8g2_ClearBuffer(MENU2U8G2(menu));

  // regular entry?
  if(menu->form >= 0) {
    // count menu entries if not done yet
    if(menu->entries < 0) {
      menu->entries = 0;

      for(const char *p = s;*p && strchr(p, ';');p=strchr(p, ';')+1)
	menu->entries++;

      // this is a newly opened form and we just determined the number
      // of menu entries. Therefore, adjust the scroll offset if needed
      if(menu->entries > 5 && menu->entry > 3) {
	if(menu->entry < menu->entries-2) menu->offset = menu->entry - 3;
	else                              menu->offset = menu->entries-5;
      }
    }

    // -------- draw title -----------
    menu_draw_title(menu, s);
    s = strchr(s, ';')+1;

    // ------- draw menu entries ------

    // skip 'offset' entries
    for(int i=0;i<menu->offset;i++)
      s = strchr(s, ';')+1;      // skip to next entry
    
    // walk over menu string
    int y = 1;
    int has_info = 0;
    while(*s) {
      if(s[0] == 'I') has_info = 1;
      menu_draw_entry(menu, y++, s);    
      s = strchr(s, ';')+1;      // skip to next entry
    }

#ifndef SDL
    // a form with an info line is redrawn on the timer (menu_do); the
    // timer does not exist yet at the very first draw (osd_task)
    if(menu->osd->timer) {
      if(has_info) xTimerStart(menu->osd->timer, 0);
      else         xTimerStop(menu->osd->timer, 0);
    }
#endif
  } else if(menu->form == MENU_FORM_FSEL)
    menu_fileselector(menu, FSEL_DRAW);
  else if(menu->form == MENU_FORM_TEXT)
    menu_text_draw(menu);
  
  u8g2_SendBuffer(MENU2U8G2(menu));
}

// does the form being shown carry an info line?
static int menu_form_has_info(menu_t *menu) {
  if(menu->form < 0) return 0;
  for(int n=1;;n++) {
    const char *e = menu_entry_at(menu, menu->forms[menu->form], n);
    if(!e) return 0;
    if(e[0] == 'I') return 1;
  }
}

// step an 'L' entry's value by +-1, wrapping (Space steps on; the cursor
// keys step either way)
static void menu_step_value(menu_t *menu, const char *s, int step) {
  int max_value = menu_get_options(menu, s, MENU_ENTRY_INDEX_OPTIONS)-1;
  int value = menu_variable_get(menu, s) + step;
  if(value > max_value) value = 0;
  if(value < 0) value = max_value;
  menu_variable_set(menu, s, value);
}

static void menu_select(menu_t *menu) {
  if(menu->form == MENU_FORM_FSEL) {
    menu_fileselector(menu, FSEL_SELECT);
    return;
  }

  // the text view returns on select
  if(menu->form == MENU_FORM_TEXT) {
    menu_goto_form(menu, text_parent, text_entry);
    return;
  }
    
  const char *s = menu->forms[menu->form];
  // skip to current entry (incl. title)
  for(int i=0;i<menu->entry;i++) s = strchr(s, ';')+1;
  
  printf("Selected: %s\r\n", s);

  // if the title was selected, then goto parent form - to the entry
  // that opened this one, found by form number
  if(!menu->entry) {
    printf("parent\n");
    int parent = menu_get_subint(menu, s, 1,0);
    menu_goto_form(menu, parent, menu_parent_entry(menu, parent, menu->form, menu_get_subint(menu, s, 1,1)));
    return;
  }
  
  switch(*s) {
  case 'F':
    // user has choosen a file selector
    menu_fileselector(menu, FSEL_INIT);
    break;
    
  case 'S':
    // user has choosen a submenu
    menu_goto_form(menu, menu_get_int(menu, s, MENU_ENTRY_INDEX_FORM), 1);
    break;

  case 'T':
    // a page of text
    if(core_id == CORE_ID_UKNC) menu_text_open(menu, menu_get_str(menu, s, MENU_ENTRY_INDEX_LABEL), about_uknc);
    break;

  case 'L':
    // user has choosen a selection list
    menu_step_value(menu, s, 1);
    break;

  case 'B': {
    // user has choosen a button
    char id = menu_get_chr(menu, s, 2);
    
    if(id == 'S')
      menu_settings_save(menu);

    // normal reset
    if(id == 'R') {    
      sys_set_val(menu->osd->spi, 'R', 1);
      sys_set_val(menu->osd->spi, 'R', 0);
      osd_enable(menu->osd, OSD_INVISIBLE);  // hide OSD
    }

    // cold boot
    if(id == 'B') {    
      sys_set_val(menu->osd->spi, 'R', 3);
      sys_set_val(menu->osd->spi, 'R', 0);
      osd_enable(menu->osd, OSD_INVISIBLE);  // hide OSD
    }

    // c64 and vic20 core, c1541 reset
    if(id == 'Z') {    
      sys_set_val(menu->osd->spi, 'Z', 1);
      sys_set_val(menu->osd->spi, 'Z', 0);
      osd_enable(menu->osd, OSD_INVISIBLE);  // hide OSD
    }
  } break;
	
  default:
    printf("unknown %c\r\n", *s);    
  }
}

static int menu_entry_is_usable(menu_t *menu) {
  // check if the current entry in the menu is actually selectable:
  // the title of the start form is not, and neither is an info line

  if(menu->form >= 0 && menu->entry > 0) {
    const char *e = menu_entry_at(menu, menu->forms[menu->form], menu->entry);
    if(e && e[0] == 'I') return 0;
  }

  // not start form? -> ok
  if(menu->form) return 1;

  return (menu->entry == 0)?0:1;
}

static void menu_entry_go(menu_t *menu, int step) {
  // the text view scrolls instead
  if(menu->form == MENU_FORM_TEXT) {
    menu_text_scroll(menu, step);
    return;
  }

  do {
    menu->entry += step;

    // single step wraps top/bottom, paging does not
    if(abs(step) == 1) {    
      if(menu->entry < 0) menu->entry = menu->entries + menu->entry;
      if(menu->entry >= menu->entries) menu->entry = menu->entry - menu->entries;
    } else {
      // limit to top/bottom. Afterwards step 1 in opposite direction to skip unusable entries
      if(menu->entry < 1) { menu->entry = 1; step = 1; }	
      if(menu->entry >= menu->entries) { menu->entry = menu->entries - 1; step = -1; }
    }

    // scrolling needed?
    if(step > 0) {
      if(menu->entries <= 5)                   menu->offset = 0;
      else {
	if(menu->entry <= 3)                   menu->offset = 0;
	else if(menu->entry < menu->entries-2) menu->offset = menu->entry - 3;
	else                                   menu->offset = menu->entries-5;
      }
    }

    if(step < 0) {
      if(menu->entries <= 5)                   menu->offset = 0;
      else {
	if(menu->entry <= 2)                   menu->offset = 0;
	else if(menu->entry < menu->entries-3) menu->offset = menu->entry - 2;
	else                                   menu->offset = menu->entries-5;
      }
    }
    
    // give file selector a chance to adjust scroll
    if(menu->form == MENU_FORM_FSEL)
      menu_fileselector(menu, (step>0)?FSEL_DOWN:FSEL_UP);
    
  } while(!menu_entry_is_usable(menu));
}

// the cursor keys on an 'L' entry step its value back or forth
static void menu_left_right(menu_t *menu, int step) {
  if(menu->form < 0 || !menu->entry) return;
  const char *e = menu_entry_at(menu, menu->forms[menu->form], menu->entry);
  if(e && e[0] == 'L') menu_step_value(menu, e, step);
}

void menu_do(menu_t *menu, int event) {
  // -1 is a timer event used to scroll the current file name if it's to long
  // for the OSD, and to redraw a form with an info line once a second
  if(event < 0) {
    if((menu->form == MENU_FORM_FSEL) && (menu->fs_scroll_entry))
      menu_fs_scroll_entry(menu, menu->fs_scroll_entry);
    else if(menu_form_has_info(menu) && ++menu->info_tick >= 25) {
      menu->info_tick = 0;
      menu_draw_form(menu, menu->forms[menu->form]);
    }
    
    return;
  }
  
  if(event)  {
    if(event == MENU_EVENT_SHOW)   osd_enable(menu->osd, OSD_VISIBLE);
    if(event == MENU_EVENT_HIDE) {
      osd_enable(menu->osd, OSD_INVISIBLE);
      sav_status[0] = 0;    // "Run SAV:" reads as itself again next time
    }
    
    if(event == MENU_EVENT_UP)     menu_entry_go(menu, -1);
    if(event == MENU_EVENT_DOWN)   menu_entry_go(menu,  1);

    if(event == MENU_EVENT_PGUP)   menu_entry_go(menu, -4);
    if(event == MENU_EVENT_PGDOWN) menu_entry_go(menu,  4);

    if(event == MENU_EVENT_LEFT)   menu_left_right(menu, -1);
    if(event == MENU_EVENT_RIGHT)  menu_left_right(menu,  1);

    if(event == MENU_EVENT_SELECT) menu_select(menu);
  }  
  menu_draw_form(menu, menu->form >= 0 ? menu->forms[menu->form] : NULL);
}

