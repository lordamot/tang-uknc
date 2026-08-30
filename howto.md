# How to flash the МС0511 (УКНЦ) on a Tang Nano 20K

This is the whole procedure, from two bare boards to a running machine.
It covers **Windows, macOS and Linux**.

*По-русски: [howto-ru.md](howto-ru.md).*

You do not need either toolchain for this.  Both binaries are committed:

| file | size | date | what it is |
|---|---|---|---|
| `bin/tang.fs` | 7 262 008 | Aug 2026 | the FPGA bitstream, for the Tang Nano 20K |
| `bin/bl616.bin` | 430 512 | Aug 2026 | the MCU firmware, for the BL616 companion board |

### What is in them

Both are built from the sources in this repository as they stand, and both
are newer than the versions shipped before August 2026.

The bitstream carries the four upstream 1801BM1/cpu11 fixes to the VM2
processor core, an AY chipselect that no longer aliases into МХ2-01's
address range, stereo audio, and the first timing constraints this design
has ever had.  The firmware carries the settings-file fix, so it reads and
writes `/uknc.ini` on the card.

> **Neither has been tested on hardware.**  They are built and they pass
> what can be checked without a board - the design lints clean, boots in
> simulation, and meets every timing constraint - but nobody has run this
> exact pair on a real Tang Nano.  The previous versions of both are in
> git history (`git log -- bin/`) if you need to fall back.

Building either from source is a different document -
`.claude/docs/build.md`.

---

## 1. What you need

- **Tang Nano 20K** (Gowin GW2AR-18C)
- **BL616 companion board** - the firmware is built for the **Sipeed M0S
  Dock** pinout
- 7 jumper wires
- a micro SD card (FAT32)
- an HDMI display and cable
- a USB keyboard
- a PC with two USB ports

---

## 2. Wire the two boards together

**This is the stock MiSTeryNano wiring** as of August 2026.  It did not
used to be - Alexey had moved the five signals to pins 71-75 - so if you
are following an older copy of this document, or you have a board wired
from one, see section 2.1.

```
Tang Nano 20K        BL616 (M0S Dock)
    pin 42     <-->      io10        MISO, FPGA -> MCU
    pin 41     <-->      io11        MOSI, MCU -> FPGA
    pin 56     <-->      io12        CSN
    pin 54     <-->      io13        SCK
    pin 51     <-->      io14        IRQ, FPGA -> MCU
    GND        <-->      GND
    +5V        <-->      +5V
```

Five signals plus ground and +5 V.  Because +5 V is bridged, **one USB
cable powers both boards** in normal use.

Any MiSTeryNano wiring diagram, and any MiSTeryShield20k carrier board,
now matches this core.

### 2.1 If your board is wired the old way

Two things moved, and they moved onto each other's pins, so a board wired
for the old bitstream will not work with the new one and vice versa:

```
                     before (to Aug 2026)   now
    MCU link         71 72 73 74 75         42 41 56 54 51
    audio I2S        56 55 54 51            71 72 73 74
    serial           69 out  70 in          48 out  55 in
```

The MCU link had to move to match upstream, and it lands exactly where the
audio was, so the audio moved to the pins the MCU link vacated.  **Rewire
both** or you will get a machine that either says nothing or plays the SPI
traffic at you.

### 2.2 Using the Tang's own BL616 instead

The Tang Nano 20K carries a BL616 of its own - the one that presents the
USB-C port as a programmer and a serial console.  This core now also
listens on the five pins that reach it, exactly as MiSTeryNano does:

```
    spi_csn 86    spi_sclk 13    spi_dat 76    spi_dir 75    spi_irqn 69
```

so with the companion firmware flashed into *that* chip there is no wiring
between boards at all.  The core works out for itself which BL616 is
talking: the internal one is used until an external dock pulls its chip
select low for the first time, after which the external one owns the link
until power-off.

Two costs, and they are the reason this is not the default:

- flashing the on-board BL616 replaces the USB-JTAG bridge, so you lose
  the ordinary way of programming the FPGA over USB-C;
- it needs a Tang Nano 20K of assembly **3921 or later**.  Earlier boards
  do not route all five signals.

**Untested here.**  The pins are constrained and the mux is in the
bitstream, but this repository has never run that variant on hardware.

> While flashing, connect only the USB cable of the board you are
> flashing.  With +5 V bridged, two cables tie two host supplies together.

---

## 3. Prepare the SD card

The card goes in the **Tang Nano 20K's** slot (the FPGA reads sectors; the
MCU does the filesystem).

1. Format it **FAT32**.
2. Copy your `.dsk` floppy images to it.  They are raw 800 KB images -
   **819 200 bytes** - and the menu only lists files ending in `.dsk`.
3. Subdirectories are fine; the file selector browses.

The MCU also keeps its settings in an `.ini` at the card root.  The
firmware now in `bin/` writes **`/uknc.ini`**.  Anything flashed before
August 2026 wrote `/amiga.ini` instead, because of a table bug in
`menu.c` - so if your settings appear to have been forgotten after
updating the firmware, that is why, and the old file can simply be
renamed.

---

## 4. Flash the BL616 companion board

The BL616 is programmed over its **UART bootloader**.  You have to put it
into boot mode by hand.

### 4.1 Enter boot mode

1. Unplug the board.
2. Hold the **BOOT** button down.
3. Plug the USB cable in (or, if it is already powered, press and release
   **RST**).
4. Release **BOOT**.

The board now enumerates as a serial port and is waiting to be programmed.
It will not run the firmware until it is reset again.

### 4.2 Find the port

| OS | what to look for |
|---|---|
| Windows | `COM3`, `COM4`, ... - Device Manager, "Ports (COM & LPT)" |
| macOS | `/dev/cu.usbmodem*` - `ls /dev/cu.*` |
| Linux | `/dev/ttyACM0` - `ls /dev/ttyACM*`, or `dmesg \| tail` |

On Linux, `/dev/ttyACM0` is owned by `root:dialout`, so add yourself to
that group or you will get a permission error:

```sh
sudo usermod -aG dialout "$USER"
```

**Then log out and back in.**  A process that is already running keeps the
groups it was given at login, so the terminal you typed that in still
cannot open the port - `getent group dialout` will already list you while
`id -nG` does not.  That mismatch is the whole diagnosis.

If you would rather not log out, run the flashing command under `sg`,
which reads `/etc/group` instead of the credentials the shell started
with - no password, no relogin:

```sh
sg dialout -c 'make flash-mcu COMX=/dev/ttyACM0'
```

`newgrp dialout` does the same for an interactive shell.

Windows normally needs no driver - the BL616 presents a standard USB CDC
serial device.  If it comes up as an unknown device, install the CH340 or
the Bouffalo USB driver that ships with BLDevCube.

### 4.3 Flash it

The tool is **Bouffalo Lab's flasher**.  There are two forms of it and
either is fine.

**A. BLDevCube / BLFlashCube - the GUI, easiest on Windows and macOS**

1. Download BLDevCube (Bouffalo Lab Dev Cube) from Bouffalo Lab, or use
   `BLFlashCube.exe` / `BLFlashCube-macos` / `BLFlashCube-ubuntu` from a
   Bouffalo SDK checkout, under
   `tools/bflb_tools/bouffalo_flash_cube/`.
2. Choose chip **BL616/BL618**, then the **MCU** tab.
3. **Image file**: `bin/bl616.bin`
4. **Address**: `0x00000000`
5. **Port**: the port from 4.2.  **Baudrate**: `2000000` (drop to
   `115200` if it fails).
6. Click **Create & Download**.
7. Wait for success, then press **RST** on the board.

**B. BLFlashCommand - the command line**

The same tool without the window.  It is in the same directory of a
Bouffalo SDK checkout: `BLFlashCommand.exe` (Windows),
`BLFlashCommand-macos`, `BLFlashCommand-ubuntu`.

It reads an `.ini` that says what to write where, so put this next to it
as `uknc_flash.ini`:

```ini
[cfg]
erase = 1
skip_mode = 0x0, 0x0
boot2_isp_mode = 0

[FW]
filedir = ./bin/bl616.bin
address = 0x000000
```

Then, from the repository root:

```sh
# Linux
BLFlashCommand-ubuntu --interface=uart --baudrate=2000000 \
    --port=/dev/ttyACM0 --chipname=bl616 --config=uknc_flash.ini

# macOS
BLFlashCommand-macos --interface=uart --baudrate=2000000 \
    --port=/dev/cu.usbmodem1101 --chipname=bl616 --config=uknc_flash.ini
```

```bat
REM Windows
BLFlashCommand.exe --interface=uart --baudrate=2000000 ^
    --port=COM4 --chipname=bl616 --config=uknc_flash.ini
```

Press **RST** when it finishes.

**C. `make flash-mcu`** (Linux, with `make toolchain` already run)

`make toolchain` fetches the Bouffalo SDK, and `BLFlashCommand-ubuntu`
comes with it, so on this route you download nothing extra and write no
`.ini` - the Makefile generates one:

```sh
make flash-mcu COMX=/dev/ttyACM0
```

That flashes `bin/bl616.bin`.  To flash firmware you built yourself, add
`FW_BIN=build/fw/bl616.bin`; to slow it down, `BAUDRATE=115200`.  Press
**RST** when it finishes.

`make -C mnano flash COMX=/dev/ttyACM0` is the SDK's own equivalent and
runs the same program, but it flashes whatever is in
`mnano/build/build_out/` and needs a firmware build first.

> **You do not have to put anything on `PATH` for any of this.**
> `BLFlashCommand-ubuntu` is a self-contained bundle - no Python, no
> install, no `tools/env.sh`.  Give its full path and it runs:
> `tools/bouffalo_sdk/tools/bflb_tools/bouffalo_flash_cube/BLFlashCommand-ubuntu`.
> `tools/env.sh` is for *building*, not for flashing.

---

## 5. Flash the Tang Nano 20K

Two routes: **openFPGALoader** (free, all three systems) or the **Gowin
Programmer** (part of Gowin EDA).

### 5.1 SRAM or flash - decide first

| target | command | survives power-off |
|---|---|---|
| SRAM | `openFPGALoader -b tangnano20k bin/tang.fs` | no |
| flash | `openFPGALoader -b tangnano20k -f bin/tang.fs` | yes |

Try it in SRAM first.  Write it to flash once you are happy.

### 5.2 Install openFPGALoader

**Linux**

```sh
sudo apt install openfpgaloader        # Debian/Ubuntu
# or the version this repository fetches:
make toolchain && ./tools/oss-cad-suite/bin/openFPGALoader --Version
```

Install the udev rules so you do not need `sudo`:

```sh
sudo cp /usr/share/openFPGALoader/99-openfpgaloader.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
```

**macOS**

```sh
brew install openfpgaloader
```

**Windows**

1. Download the openFPGALoader release zip and unpack it.
2. The Tang Nano 20K's on-board debugger needs a **WinUSB** driver on the
   JTAG interface.  Run [Zadig](https://zadig.akeo.ie/), tick
   *Options -> List All Devices*, select the Tang Nano's **Interface 0**,
   choose **WinUSB** and click Replace Driver.
3. Do **not** touch Interface 1 - that is the serial port.

### 5.3 Write it

Plug the Tang Nano 20K into USB (its own cable, per the note in section 2)
and run, from the repository root:

```sh
openFPGALoader -b tangnano20k bin/tang.fs        # to SRAM, for a try
openFPGALoader -b tangnano20k -f bin/tang.fs     # to flash, to keep
```

On Linux with this repository's fetched toolchain there are shortcuts:

```sh
make flash-fpga          # SRAM
make flash-fpga-flash    # flash
```

### 5.4 Or use the Gowin Programmer

If you have Gowin EDA installed (Windows or Linux):

1. Open **Programmer**.
2. It should find the cable by itself; if not, install the Gowin USB
   Cable driver.
3. Series **GW2AR**, device **GW2AR-18C**.
4. Access Mode **SRAM Program** with `bin/tang.fs`, or **Embedded Flash /
   exFlash Program** to keep it.
5. Program.

---

## 6. First boot

1. Card in the Tang Nano 20K, HDMI connected, USB keyboard in the BL616
   board's host port.
2. Power up - one USB cable is enough, since +5 V is bridged.
3. Give it a moment: the design holds itself in reset for about a third of
   a second after configuration, then the peripheral processor runs its
   power-on test before it starts the central one.

You should see the УКНЦ start-up screen on HDMI.

---

## 7. How to use it

### 7.1 The on-screen menu

**F12** opens and closes the menu.  While it is open:

| key | does |
|---|---|
| **Cursor up / down** | move between entries |
| **Space** or **Enter** | select, or step a value on |
| **ESC** | close the menu |
| **F12** | close the menu |

F12 never reaches the machine - it belongs to the menu.  Everything else
does, so close the menu before typing.

The menu is four screens:

```
UKNC Nano
  FDD 0:                 mount an image on drive 0 (the quick way in)
  System           >     Video: RGB / BGR
                         Cold Boot
  Drives           >     Disk 0:  Disk 1:  Disk 2:  Disk 3:
                         Disk prot.: None / 0: / 1: / 2: / 3: / All
  Settings         >     Volume: Mute / 33% / 66% / 100%
                         Save settings
  Reset
```

Entries marked `>` open a sub-screen; the top line of a sub-screen takes
you back.

### 7.2 Running a disk

1. **F12** to open the menu.
2. **Drives -> Disk 0:** and pick your `.dsk`.  The selector browses the
   card, so images can live in folders.
3. **ESC** back out, then **Reset** on the main screen.
4. The machine restarts and boots from drive 0.

Drives 0 to 3 are the machine's four МХ2-01 floppies.  Mounting an image
while the machine is running is fine - it is the same as changing a disk -
but software that has already booted will not notice a new system disk
until you reset.

**Reset** restarts the processors and leaves memory alone.  **Cold Boot**
(under *System*) is the power-on path and clears it.  Use Cold Boot when
something has wedged badly, or when a program has left the machine in a
state a plain reset does not clear.

**Disk prot.** write-protects drives: `None`, one of `0:` to `3:`, or
`All`.  Set it before you boot something you do not trust; the images on
the card are ordinary files and a running program can write to them.

### 7.3 Sound

**Settings -> Volume**: Mute, 33%, 66%, 100%.  It starts muted-ish until
the MCU sends its defaults, and the default for this core is 33%.

The machine has two AY-3-8910s and a one-bit beeper.  The AYs are panned
the usual ABC way - channel A left, C right, B in the middle - and the
beeper sits in the centre.  Output is I²S, on **Tang Nano 20K pins 71
(BCK), 72 (WS), 73 (DIN) and 74 (amplifier enable)** - they moved there in
August 2026 when the MCU link took back the pins upstream uses.  See
section 2.1.

### 7.4 Video

**System -> Video: RGB / BGR** swaps the red and blue components.  If the
colours look wrong on your display, this is the switch.  Output is HDMI
from the Tang Nano 20K.

### 7.5 Keyboard

A USB keyboard plugs into the **BL616** board's host port, and the BL616
translates HID to УКНЦ scan codes.  The УКНЦ has keys a PC does not, so:

| PC key | УКНЦ key |
|---|---|
| F1 - F5 | К1 - К5 |
| F6 | ПОМ (help) |
| F7 | УСТ (set) |
| F8 | ИСП (execute) |
| F9 | СБРОС (reset) |
| F10 | СТОП |
| Ctrl (either) | УПР |
| Left Alt | АЛФ |
| Right Alt | ГРАФ |
| Caps Lock | ФИКС |
| Esc | АР2 |
| Cursor keys, keypad | as marked |

F11 and F12 are not passed through - F12 is the menu.

Because the translation happens on the MCU, **changing a key binding means
editing `mnano/uknc.h` and reflashing the BL616**, not rebuilding the
FPGA.  The table is one entry per USB HID usage code, in order, so it is
easy to read and easy to change.

### 7.6 Keeping your setup

**Settings -> Save settings** writes an `.ini` at the root of the card
with the mounted images and the menu values in it, and it is read back at
the next power-up.  See section 3 for which name it uses - that depends on
which firmware you flashed.

### 7.7 Swapping cards

Power off before pulling the card.  The MCU holds the filesystem open, and
there is no eject in the menu.

## 8. If it does not work

**Nothing on HDMI at all.**  Check the bitstream actually went in - the
Tang Nano's LEDs change once it is configured.  If you wrote to SRAM,
remember it is gone after a power cycle.

**HDMI syncs but the screen stays black.**  The central processor is
started *by* the peripheral one, over `R177716`.  A black screen usually
means the PPU never got that far - almost always the SD card (wrong
format, or no card) or the wiring in section 2.

**Screen works, keyboard dead.**  That is the BL616 half: either the
firmware did not flash, the board is still sitting in boot mode (press
**RST**), or the five signal wires are wrong.  The keyboard must be in the
**BL616** board's USB host port, not the PC.

**The menu opens but mounting a disk does nothing.**  Check the image is
exactly 819 200 bytes and ends in `.dsk`.

**`Permission denied` on Linux.**  `dialout` group for the serial port,
udev rules for openFPGALoader.  See sections 4.2 and 5.2.

**The flasher cannot find the BL616.**  It is not in boot mode.  Repeat
4.1 - hold BOOT, reset, release BOOT - and check the port number again,
because it can change.

---

## 9. Notes

- `bin/tang.fs` is a copy of `tang/impl/pnr/test003.fs`, which is what
  `make bitstream` produces.  They are the same file now; before August
  2026 they were the same size and date but different contents, and which
  one was on anyone's board was never established.
- Both binaries can be rebuilt from source on Linux with `make toolchain`
  and then `make bitstream` / `make fw`; the toolchain, Gowin included,
  is fetched into `tools/` and nothing is installed on the host.  See
  `.claude/docs/build.md`.
- The hardware design is **Alexey Gurov's**.
