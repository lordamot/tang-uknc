# The MCU half

`mnano/` is a fork of **MiSTeryNano's BL616 firmware** (Till Harbaum's),
carrying the УКНЦ core alongside the Atari ST, C64, Amiga, VIC-20, Agat-9
and "uneon" ones it came with.  It runs FreeRTOS on a Bouffalo **BL616**
and does four jobs the FPGA cannot: USB host for keyboard and mouse, the SD
card filesystem, the on-screen menu, and telling the core what the user
picked.

`mnano/u8g2/` is the vendored u8g2 graphics library, used to render the OSD
into a bitmap that is shipped to the FPGA a byte at a time.

## The SPI link

BL616 is the master.  `mnano/spi.c`, **20 MHz, SPI mode 1** (idle low,
sampled on the falling edge).  On the M0S-dock pinout the firmware is built
for - and which matches the README's wiring table:

```
CSN  GPIO 12     SCK  GPIO 13     MISO GPIO 10     MOSI GPIO 11
IRQ  GPIO 14     (an interrupt in from the FPGA)
```

`mnano/spi.c` is **byte-identical to upstream's**
`firmware/misterynano_fw/spi.c`, and always was: the MCU side of the link
was never the thing Alexey changed.  When the FPGA side was brought back
to stock wiring in August 2026 this file needed no edit at all, and the
`-DM0S_DOCK=1` the Makefile passes still selects the branch above.  The
`#else` branch is upstream's internal-BL616 build and is not what `make
fw` produces.

**SYS command 9** (Sep 2026): followed by A5h, it makes the core pulse
RECONFIG_N and the FPGA reload from the flash address in its header -
the core switch of `../tang-ultima`, whose firmware is the one that
sends it.  This tree's firmware does not.

Which five FPGA pins those GPIOs reach, and the second set that goes to
the Tang's own on-board BL616, are in `.claude/docs/fpga.md`.  The core
picks between the two by itself; nothing in the firmware knows or cares
which one it is.

Every transaction is `[target byte][command byte][payload…]`.
`mister/mcu_spi.v` splits the first byte into one of four strobes and hands
the rest to that block; `mnano/spi.h` and the four Verilog files agree on
the numbering:

| target | Verilog | commands |
|---|---|---|
| 0 SYS | `mister/sysctrl.v` | 0 status, 1 leds, 2 rgb, 3 buttons, 4 set value, 5 irq control |
| 1 HID | `mister/hid.v` | 0 status, 1 keyboard, 2 mouse (buttons, dx, dy - one report to `kakave.v`), 3 joystick, 4 get db9 |
| 2 OSD | `mister/osd_u8g2.v` | 1 enable, 2 write |
| 3 SDC | `mister/sd_card.v` | 1 status, 2 core read/write, 3 MCU read, 4 image inserted, 5 MCU write |

### Handshake at power-on

`main.c` polls `sys_status_is_valid()` for up to 5 seconds.  SYS command 0
returns three bytes, `5c 42 <core id>`; the firmware checks the first two
as a pattern that will not come off an unprogrammed device, then keeps the
third as `core_id`.  This build's `sysctrl.v` returns **`8'h05`**, and
`CORE_ID_UKNC` in `sysctrl.h` is `0x05`, so they match - but the comment
next to it in `sysctrl.v` still says "core id 1 = Atari ST" from upstream.
Ignore the comment.

Having identified the core, `main.c` immediately sends `sys_set_val(spi,
'R', 3)` - hold the machine in cold reset - so the settings can be applied
before anything runs, and lights the RGB LED blue (red if the FPGA never
answered).

The FPGA side of that ordering, as of Sep 2026: `sysctrl.v` is held in
reset by `sys_rst_n` from configuration until 335 ms after `sdram2.v`
reports its initialisation done, and while in reset it neither advances
its state machine nor answers, so the MCU's polling simply fails until
then and the 'R' that follows always lands on an initialised memory.
The PPU itself is held by `~init` as well as by 'R', so nothing executes
before the SDRAM is ready whatever the MCU does.  After the handshake the
FPGA's coldboot flag is still set and its interrupt line is low; the
first time the MCU services that interrupt it sees bit 0 and resets
itself through the watchdog (`sys_handle_event`), which is upstream's
way of re-running its own initialisation against a freshly configured
FPGA - so one MCU restart per power-up is normal, not a fault.

### Setting values

SYS command 4 takes a one-character id and a byte.  Both halves have to
agree on the letters; `sysctrl.v` decodes:

```
'V'  system_video          bit 0     0 = RGB, 1 = BGR (swaps the red and blue planes; it swapped
                                     red and GREEN until Sep 2026 - the OSD "Color")
'R'  system_reset          bits 1:0  0 run, 1 reset, 3 coldboot
'A'  system_volume         bits 1:0  0 mute, 1 33%, 2 66%, 3 100%
'b'  system_beeper         bit 0     0 mute, 1 on - the beeper leaves the mixer only, it is a standard part
'1'  system_ay_en[0]       bit 0     } the three AY-3-8912s of the Aberrant (OSD "Aberrant"): off, the
'2'  system_ay_en[1]       bit 0     } chip's word address is not acknowledged, the chip is held in
'3'  system_ay_en[2]       bit 0     } reset and adds nothing to the sum
'c'  system_covox          bits 1:0  0 off, 1 the DAC at 0177372, 2 a DAC on printer port A 0177100,
                                     3 both (OSD "Covox"); off, 0177372 is a bus timeout
'f'  system_fdd_en         bit 0     the floppy controller's 0177130/0177132 answer (OSD "FDD controller")
'p'  system_floppy_wprot[0] bit 0    } one letter a drive, 1 = write-protected (OSD "FDDn write prot.").
'q'  system_floppy_wprot[1] bit 0    } Until Sep 2026 one letter 'P' carried the INDEX of a six-entry
'r'  system_floppy_wprot[2] bit 0    } list as if it were the bitmask: "2:" protected 0 and 1, "All"
's'  system_floppy_wprot[3] bit 0    } protected 0 and 2 - progress.md's open question, answered
'e'  system_hdd_en         bit 0     the IDE cartridge exists (with an image in slot 4) - OSD "HDD controller";
                                     off also hides "HDD0:" on the main form
'u'  system_mouse_en       bit 0     the Kakave+ mouse word 0177400 answers (OSD "Mouse")
't'  system_rtc_en         bit 0     the Kakave+ clock word 0177410 answers (OSD "RTC controller"); the
                                     clock counts either way
'S'  system_hdd_spt        bits 7:0  IDE image sectors per track  } sent by sdc.c
'H'  system_hdd_heads      bits 7:0  IDE image heads              } at mount, from
'I'  system_hdd_flags      bit 0     IDE image stored inverted    } the image's sector 0
'J'  system_hdd_mode       bits 1:0  0 use 'I', 1 read as plain, 2 as inverted (OSD "HDD image")
'C'  system_hdd_cyl[7:0]   bits 7:0  IDE image cylinders, low byte   } file size / 512 / spt / heads,
'Y'  system_hdd_cyl[15:8]  bits 7:0  IDE image cylinders, high byte  } for IDENTIFY
'K'  system_hdd_wprot      bit 0     IDE image write-protected (OSD "HDD prot.")
'D'  system_hdd_delay      bits 5:0  stretch of IDE data reads, ~25 us a sector per step (OSD "HDD delay")
'M'  system_mouse          bit 0     a USB mouse is attached - sent by usb_host.c when the count changes
'y'  year - 2020           bits 7:0  } the Kakave+ clock (kakave.v), one field a letter,
'm'  month - 1             bits 7:0  } from the OSD "Clock" form; each is applied as it
'd'  date - 1              bits 7:0  } arrives, 'n' also zeroes the seconds.  sysctrl.v
'h'  hours                 bits 7:0  } passes them on as {field, value} with a toggle
'n'  minutes               bits 7:0  }
```

Anything the menu offers has to have a letter here, in `variables_uknc[]`
in `menu.c`, and in the menu form string - three places.

One command reads back: **SYS command 6** returns the Kakave+ clock as
`kakave.v` holds it - year low, year high, month, date, hour, minute,
second, weekday (1 = Sunday) - after the usual dummy byte, snapshotted at
the command byte so the eight bytes are one instant.  `sys_get_rtc()` in
`sysctrl.c`; the OSD's "RTC clock" form shows it once a second.

## The menu

`menu.c`, restructured in Sep 2026 (v2.0.0) around one "Hardware" form.
The caption of the main form carries the version from `../VERSION` at
its right (`UKNC_VERSION`, read by `CMakeLists.txt`).

```
main          FDD0: fileselector (*.dsk), HDD0: fileselector (*.img, SD slot 4 -
              shown only while the HDD controller is on), Run SAV: (*.sav,
              browse-only slot SDC_SLOT_SAV = 5), Reset, Hardware >, About >,
              Save settings
Hardware      Volume Mute|33%|66%|100% ('A'), Beeper Mute|On ('b'), Aberrant >,
              Covox Off|Port 177372|Port 177100 LPT|Both ('c'), FDD controller >,
              HDD controller >, Mouse Off|On ('u'), RTC clock >, Misc >
Aberrant      AY1 / AY2 / AY3 Off|On ('1' '2' '3')
FDD controller  FDD controller Off|On ('f'), then FDD0:..FDD3: fileselectors, each
              followed by "FDDn write prot." Off|On ('p' 'q' 'r' 's')
HDD controller  HDD controller Off|On ('e'), HDD0: fileselector, HDD write prot.
              Off|On ('K'), Image format Auto|Plain|Inversed ('J'), HDD delay
              0..975 us ('D', default 750 - right for badapple on the board; the value sent is us/25)
RTC clock     RTC controller Off|On ('t'), Year 2020..2039 ('y'), Month ('m'),
              Day ('d'), Hour ('h'), Minute ('n'), and an info line
              "2026-02-23 14:00:01 Thu" read back from the core (SYS command 6)
              once a second - not selectable
Misc          Color RGB|BGR ('V'), Cold Boot
About         a text page: authors and thanks, scrolled with the cursor keys
```

Defaults (`variables_uknc[]`): volume 33%, beeper on, the three AYs on,
Covox off, FDD controller on, nothing write-protected, HDD controller
off, mouse off, RTC controller off, colour RGB, the clock 2026-01-01.
Nothing is mounted until the settings file says so.

Three things about the engine that came with it:

- **Cursor left/right step a value entry** (`L`) back and forth, wrapping;
  Space and Enter still step it on.  `usb_host.c` maps HID 0x50/0x4f to
  `MENU_EVENT_LEFT/RIGHT`.
- **A form returns to the entry that opened it, found by form number**
  (`menu_parent_entry()`), so the `"parent|entry"` in a form's title is
  only a fallback now, and a file selector returns to its own entry.
  Until then every УКНЦ form named a fixed entry, and "Run SAV:" moving
  the submenus down one had them come back a line high.
- **Two entry types were added**: `T` opens a text page (`MENU_FORM_TEXT`,
  paragraphs wrapped to the OSD's width in the menu font when opened),
  and `I` is a computed, unselectable line that the 25 Hz OSD timer
  redraws once a second (`info_tick`; the timer is started on a form
  that has one).  A value that does not fit the right half of the line
  moves right of its label and left as far as the screen needs.
- **The main form is built at run time** (`menu_uknc_main()`), because
  "HDD0:" is only there while 'e' is on.

`make menu-test` runs all of this on the host: `mnano/menu_test.c`
builds `menu.c` under its `SDL` host switch with u8g2 drawing into a
bitmap and everything else stubbed, walks every form with the events
`usb_host.c` would send, asserts what the core was told and where the
cursor landed, and leaves each screen under `build/menu/` as text and
PNG (`tools/osd_png.py`).  It is the only place the layout can be seen
without a board.

**Run SAV:** (Sep 2026) is the one entry that mounts nothing itself.
It browses the card for `.sav` files through `SDC_SLOT_SAV`, a sixth
slot in `sdc.c` that has a working directory and a remembered name
like a drive but no open image and no line in the settings file.
Picking a file runs `menu_run_sav()`: the entry's label becomes
`making DSK` and the OSD is redrawn, FDD 0 is ejected, and
`rt11sav_make()` (`rt11sav.c`) copies `/sd/RT11BASE.DSK` (or
`BASERT11.DSK`) to `/sd/RT11SAV.DSK`, adds the program under a
six-letter RT-11 name and appends `R NAME` to `STARTS.COM`; then the
label reads `err: <reason>` or `done: RT11SAV.DSK`, in which case the
new disk is mounted in FDD 0 and the core is reset to boot it.  The
whole thing runs inside the OSD task, so the menu is blocked until
the label changes, and the event queue is emptied afterwards so keys
pressed during the copy do nothing.  The label goes back to
"Run SAV:" when the OSD is closed.  `make sav-test` runs the same
image code on the host; `.claude/docs/soft.md` has the RT-11 side.
The first board run (3 Sep 2026) said `err: disk full`: `sdc.c`'s
FatFs sector callbacks moved one sector whatever count they were
given, so the 4 KB copy left seven of every eight sectors unwritten.
They loop now; the settings file, under 512 bytes, had never shown it.

The old "Disk prot." entry offered six choices onto the four-bit `'P'`
field as an index; the FPGA read it as a bitmask, so "2:" protected
drives 0 and 1 and "All" protected 0 and 2.  Gone with the restructure:
one letter a drive.

Disk images are `.dsk`, 819200 bytes (see `.claude/docs/platform.md`).
`sdc.c` mounts them and `mister/sd_card.v` serves sectors on request.

## The keyboard table

`mnano/uknc.h` is a USB HID usage code → УКНЦ scan code table, one entry
per HID code, `MISS` (0) for keys the machine does not have.  The scan
codes are octal and go into `R177702` in `xm2-01.v`; there is no matrix
scan anywhere in the FPGA.  UKNCBTL's `qkeyboardview.cpp` is the
reference for which code is which key.

The function-key row is where the machine's own keys live:

```
F1-F5   K1..K5          F6  ПОМ (help)    F7  УСТ (set)
F8  ИСП (exec)          F9  СБРОС (reset) F10 СТОП
```

`modifier_uknc[]` maps the USB modifier bits: ctrl → УПР (046), shift →
0105, left alt → АЛФ (0106), right alt → ГРАФ (066; it was 0172, which is
ПОМ, until Sep 2026).  Both ctrls and both shifts map to the same code.

### The matrix rows

The real keyboard is a scanned 16-row × 8-column matrix and the machine
never sees keys, only rows: a scan code is `{column[6:4], row[3:0]}`, a
press is reported for the first key to go down in a row and for no other
key in that row until the whole row is up, and the release code is
`0200 | row`, sent once when it is.  UKNCBTL's scanner in `Board.cpp`
(`SystemFrame`, the `m_kbd_matrix[].processed` flag) is the model, and
the ROM's keyboard driver is written to it: one press, then one release,
per row, and its autorepeat runs until the releases balance the presses.

Until Sep 2026 `usb_host.c` forwarded every USB press and release as its
own code (`hid.v` truncates a release to `0200 | row`, so the release
side already looked right).  Two keys of one row broke it: the second
key was a second press, its release said the row was up while the first
was still held, and the first key's release then arrived as the same
byte, which `xm2-01.v` takes as no change and never latches.  Both
Shifts are 0105, row 5, and PC `'` was mapped to 05 - the numeric-keypad
comma, row 5 - so Shift+`'` typed `,` and left the ROM one release
short, and it repeated the comma until another Shift press and release
put the count right.  Shift with `-` (025, keypad minus, row 5) did the
same with `/`.  Reproduced against the real ROM: `.claude/docs/progress.md`
defect 15 has the byte streams.

`kbd_tx_uknc()` in `usb_host.c` now keeps the matrix - which HID usages
it has forwarded as pressed, how many of them are down in each row, and
which code the machine believes each row is held by - and sends only
row transitions.  It ignores a press while the OSD is up and a press of
a `MISS` key, and then ignores their releases too, rather than
announcing a row the core never heard go down; a release of a key it did
forward goes out even while the OSD is up, because the core is waiting
for it.  Two Shifts held are one code held twice, and the row is
released when the second one goes up.

One deliberate departure from the machine's own keyboard: **rollover
inside a row**.  On the real matrix the next key down in a held row is
never reported, and a PC typist rolls from A to Backspace (both row 10,
with K, M and 3) all day - so the filter sends the machine a release of
the row and a new press, and forgets the older keys of that row (their
releases now mean nothing; a per-row generation counter tells the two
apart).  Shift plus a keypad key becomes "Shift up, key" the same way
- `7` rather than nothing.  Consecutive bytes are kept 2 ms apart
(`kbd_tx_uknc_byte()`), because `hid.v` holds one byte with no strobe
and an older bitstream's `xm2-01.v` took only a change of it.

Row 5 is Shift plus the keypad (05, 025, 0125, 0145, 0165), so PC `-`
was moved from the keypad minus to the machine's `- =` key (0175, row
13) and Shift+`-` gives `=`.  PC `'` is now 0155, the key with Э on it.
0110 (`Ч ^`) is still not reachable from a PC keyboard.

The FPGA side has a queue since the same day: `xm2-01.v` holds up to
seven bytes and loads `R177702` from it only after the PPU has read the
previous one, as the real controller does with its ready bit (UKNCBTL,
`m_Port177700 & 0200`).  `make kbd-test` runs `sim/tb/tb_kbd.v` against
it: bursts 1.5 us apart against a PPU that looks every 40 or 400 us, all
bytes out in order.

To change a key binding, `uknc.h` is the only place to edit - and it
means rebuilding and reflashing the BL616, not the FPGA.

### Testing a key sequence without a board

The ROM's reaction to a byte stream can be measured: the headless
UKNCBTL runner in the neighbouring `mc0511-dicewars/tools/uknc-headless`
builds against `ukncbtl-qt`'s `emubase`, and one added script command
that writes `m_Port177702`, sets bit 7 of `m_Port177700` and raises VIRQ
0300 injects a byte exactly as `xm2-01.v` presents one (the members are
`protected`; a `#define protected public` around the include reaches
them).  An RT-11 prompt that echoes is `mc0511test/toolchain/rt11.dsk`,
booted with `press 030`, `press 153`, then АР2 (`press 06`) out of the
music player it autostarts; `build/moutst.dsk` (not in git) comes up at
the prompt directly, with `SET TT NOSCOPE`, in which RT-11 echoes a
rubout as `\` and the deleted characters rather than erasing them - that
is RT-11, not the keyboard.  That is how the streams above were checked,
and the fixed firmware's own `kbd_tx_uknc()` was compiled on the host
around a stub `kbd_tx()` to generate them.

## Building it

`mnano/run_make` is the author's one-liner and it hardcodes his paths:

```sh
make CROSS_COMPILE=/home/alex/toolchain_gcc_t-head_linux/bin/riscv64-unknown-elf- \
     BL_SDK_BASE=/home/alex/bouffalo_sdk/
```

Neither directory exists on this host.  See `.claude/docs/build.md`.
