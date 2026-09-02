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
          HDD image Auto|Plain|Inverted ('J'), HDD prot. Off|On ('K')
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
codes are octal and go straight into `R177702` in `xm2-01.v`; there is no
matrix scan anywhere in the FPGA.

The function-key row is where the machine's own keys live:

```
F1-F5   K1..K5          F6  ПОМ (help)    F7  УСТ (set)
F8  ИСП (exec)          F9  СБРОС (reset) F10 СТОП
```

`modifier_uknc[]` maps the USB modifier bits: ctrl → УПР (046), shift →
0105, left alt → АЛФ (0106), right alt → ГРАФ (0172).  Both ctrls and both
shifts map to the same code.

To change a key binding, this file is the only place to edit - and it means
rebuilding and reflashing the BL616, not the FPGA.

## Building it

`mnano/run_make` is the author's one-liner and it hardcodes his paths:

```sh
make CROSS_COMPILE=/home/alex/toolchain_gcc_t-head_linux/bin/riscv64-unknown-elf- \
     BL_SDK_BASE=/home/alex/bouffalo_sdk/
```

Neither directory exists on this host.  See `.claude/docs/build.md`.
