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
| 1 HID | `mister/hid.v` | 0 status, 1 keyboard, 2 mouse, 3 joystick, 4 get db9 |
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
'V'  system_video          bit 0     0 = RGB, 1 = BGR (swaps red and green)
'R'  system_reset          bits 1:0  0 run, 1 reset, 3 coldboot
'A'  system_volume         bits 1:0  0 mute, 1 33%, 2 66%, 3 100%
'P'  system_floppy_wprot   bits 3:0  one bit per drive
'S'  system_hdd_spt        bits 7:0  IDE image sectors per track  } sent by sdc.c
'H'  system_hdd_heads      bits 7:0  IDE image heads              } at mount, from
'I'  system_hdd_flags      bit 0     IDE image stored inverted    } the image's sector 0
'J'  system_hdd_mode       bits 1:0  0 use 'I', 1 read as plain, 2 as inverted (OSD "HDD image")
'C'  system_hdd_cyl[7:0]   bits 7:0  IDE image cylinders, low byte   } file size / 512 / spt / heads,
'Y'  system_hdd_cyl[15:8]  bits 7:0  IDE image cylinders, high byte  } for IDENTIFY
'K'  system_hdd_wprot      bit 0     IDE image write-protected (OSD "HDD prot.")
'D'  system_hdd_delay      bits 5:0  stretch of IDE data reads, ~25 us a sector per step (OSD "HDD delay")
```

Anything the menu offers has to have a letter here, in `variables_uknc[]`
in `menu.c`, and in the menu form string - three places.

## The menu

`menu.c`, four form strings for УКНЦ:

```
main      FDD 0: fileselector, HDD 0: fileselector (*.img, SD slot 4),
          System, Drives, Settings, Reset
System    Video RGB|BGR ('V'), Cold Boot
Drives    Disk 0:..3: fileselectors, Disk prot. None|0:|1:|2:|3:|All ('P'),
          HDD image Auto|Plain|Inverted ('J'), HDD prot. Off|On ('K'),
          HDD delay 0..975 us ('D', default 750 - right for badapple on the board; the value sent is us/25)
Settings  Volume Mute|33%|66%|100% ('A'), Save settings
```

`variables_uknc[]` gives the defaults: video RGB, volume 33%, no write
protection.  Note that "Disk prot." offers six choices onto a four-bit
field, so the values are an index into the list, not a bitmask - the FPGA
takes all four bits and the correspondence is whatever `menu.c` sends.

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
