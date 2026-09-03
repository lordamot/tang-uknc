# How to flash the МС0511 (УКНЦ) on a Tang Nano 20K

This is the whole procedure, from two bare boards to a running machine.
It covers **Windows, macOS and Linux**.

*По-русски: [howto-ru.md](howto-ru.md).*

You do not need either toolchain for this.  Both binaries are committed:

| file | size | date | what it is |
|---|---|---|---|
| `bin/tang.fs` | 7 262 008 | 3 Sep 2026 | the FPGA bitstream, for the Tang Nano 20K |
| `bin/bl616.bin` | 442 016 | 3 Sep 2026 | the MCU firmware, for the BL616 companion board |

### What is in them

Both are **v2.0.0 alpha** (the `VERSION` file), built from the sources
in this repository as they stand.

The bitstream carries the two VM2 cores with the upstream cpu11 fixes,
the Aberrant's three AYs, a Covox at `177372` and another on the printer
port, the IDE cartridge with its WD ROM, the Kakave+ mouse and clock,
HDMI with sound, timing constraints on every crossing, and an OSD switch
for each of those devices.  The firmware carries the restructured menu
of section 7, the "Run SAV:" disk maker, the keyboard matrix filter and
the settings file `/uknc.ini`.

> **This pair was flashed on 3 Sep 2026 and the new menu came up.**  The
> individual pieces had been on a board before - the sound, the floppies,
> the keyboard, the hard disk, MKLAD - and every hardware switch has been
> checked in simulation; what has not been done on a board is running
> software against each switch in each position.  The previous versions
> of both are in git history (`git log -- bin/`) if you need to fall back.

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
    serial           69 out  70 in          69 out  70 in
```

The MCU link had to move to match upstream, and it lands exactly where the
audio was, so the audio moved to the pins the MCU link vacated.  **Rewire
both** or you will get a machine that either says nothing or plays the SPI
traffic at you.  The serial port did not move and needs nothing done to
it.

### 2.2 Why the Tang's own BL616 is not used

The Tang Nano 20K carries a BL616 of its own - the one that presents the
USB-C port as a programmer and a serial console.  MiSTeryNano can run the
companion firmware in *that* chip and talk to the FPGA over five dedicated
pins, with no wiring between boards at all:

```
    spi_csn 86    spi_sclk 13    spi_dat 76    spi_dir 75    spi_irqn 69
```

**This core does not do that, on purpose.**  Look at the last pin: 69 is
also the FPGA's TX into that BL616, which is what makes the УКНЦ's serial
port appear on the USB-C plug.  The interrupt line takes it, so you cannot
have both.  On top of that, flashing the on-board BL616 replaces the
USB-JTAG bridge, so you lose the ordinary way of programming the FPGA over
USB-C (see section 5.5 for what to do then), and it needs a Tang Nano 20K
of assembly **3921 or later** - earlier boards do not route all five
signals.

So this build keeps the console and uses an external BL616 board, which is
the only arrangement anyone here has actually run.

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

### 5.5 If USB-C will not program the FPGA

The USB-C port is a programmer because the Tang's **own** BL616 presents an
FTDI FT2232 to the host.  That is independent of every user pin, so no
bitstream can take it away - but flashing that BL616 with something else
can, because the program that serves the FTDI is gone.

First work out which half is missing.  Plug the Tang in on its own:

```sh
lsusb | grep 0403                        # 0403:6010 = the FT2232
openFPGALoader --detect -b tangnano20k   # should name a GW2AR-18C
```

- **FTDI present, device detected** - the port is fine and the trouble is
  elsewhere: the WinUSB driver on Windows (section 5.2), or the udev rules
  on Linux.
- **No FTDI, but a plain serial port appeared instead** - the on-board
  BL616 is running something that is not Sipeed's debugger.  That is what
  happens if the MiSTeryNano companion firmware was flashed into it.

**Nothing in this repository asks you to do that.**  `make flash-mcu`
targets the *external* BL616 board, and this core does not use the Tang's
own BL616 at all - see section 2.2.  So the second case only arises if
somebody flashed it deliberately.

#### Putting the debugger back

The BL616's bootloader lives in mask ROM and cannot be erased, so the chip
is always recoverable over the same USB-C plug.  No adapter, no soldering.

1. Fetch Sipeed's debugger firmware **for this board**:

   `https://api.dl.sipeed.com/TANG/Debugger/onboard/BL616/2025030317/bl616_fpga_partner_20kNano.bin`

   The file is board-specific.  The Tang Console 60K's is
   `bl616_fpga_partner_Console.bin` and the two are not interchangeable.

2. Put the chip into DFU mode: hold the **UPDATE** button - it is behind
   the HDMI connector on the top side of the board, and it is neither of
   the buttons the core reads as `buts[0]`/`buts[1]` - and *then* plug the
   USB-C cable in.  Release it once the board is powered.

3. Find the port: `ls /dev/ttyACM*`, or `dmesg | tail`.

4. Write it at address 0, which is what this repository's target already
   does - only the file changes:

```sh
make flash-mcu COMX=/dev/ttyACM0 \
     FW_BIN=~/Downloads/bl616_fpga_partner_20kNano.bin
```

   If you are not in the `dialout` group yet, wrap it:
   `sg dialout -c 'make flash-mcu COMX=... FW_BIN=...'`.  Section 4.2.

   On Windows or macOS the same job is BLDevCube: chip **BL616/618**,
   single-download, that file, address **0x0**, Open UART, Create &
   Download.

5. Unplug and plug back in.  `lsusb` should show `0403:6010` again and
   `make flash-fpga` should work.

> Watch which chip you are talking to.  Both BL616s enumerate as serial
> ports in their bootloaders and both are flashed by the same tool.  Have
> only the board you are flashing plugged in.

#### If the on-board BL616 is dead rather than reprogrammed

Sipeed reserve JTAG test points on the Tang Nano 20K "for those who want to
use their own debugger", so an external adapter can drive the FPGA with the
on-board chip out of the picture entirely; `openFPGALoader -c <cable>`
takes any adapter it knows instead of `-b tangnano20k`.  Which pads those
are is on the board's schematic on the Sipeed wiki - **this repository has
not identified them and cannot test them**, so that is a direction, not an
instruction.

> None of section 5.5 has been performed here.  Steps 1-4 are Sipeed's
> published procedure plus this repository's own flashing target; the
> `make flash-mcu` invocation is the one that has been run, against the
> external board, with a different file.

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
| **Cursor left / right** | step a value back or forth |
| **Space** or **Enter** | select, or step a value on |
| **Page up / down** | four entries at a time |
| **ESC** | close the menu |
| **F12** | close the menu |

F12 never reaches the machine - it belongs to the menu.  Everything else
does, so close the menu before typing.

The version of the firmware sits at the right of the caption.  The
screens (v2.0.0, September 2026):

```
UKNC Nano                              2.0.0 alpha
  FDD0:                  mount an image on drive 0
  HDD0:                  the hard disk image - only shown while the HDD controller is on
  Run SAV:               pick a .SAV: it becomes a bootable RT-11 disk in FDD0
  Reset
  Hardware         >     Volume: Mute / 33% / 66% / 100%
                         Beeper: Mute / On
                         Aberrant        >  AY1: AY2: AY3:  Off / On
                         Covox: Off / Port 177372 / Port 177100 LPT / Both
                         FDD controller  >  FDD controller: Off / On
                                            FDD0:  FDD0 write prot.: Off / On
                                            ... the same for FDD1 to FDD3
                         HDD controller  >  HDD controller: Off / On
                                            HDD0:
                                            HDD write prot.: Off / On
                                            Image format: Auto / Plain / Inversed
                                            HDD delay: 0 .. 975
                         Mouse: Off / On
                         RTC clock       >  RTC controller: Off / On
                                            Year: Month: Day: Hour: Minute:
                                            2026-02-23 14:00:01 Thu   (the clock as it runs)
                         Misc            >  Color: RGB / BGR
                                            Cold Boot
  About            >     who made it, and thanks
  Save settings
```

Entries marked `>` open a sub-screen; the top line of a sub-screen takes
you back to the entry you came from.

**A device that is *Off* is not in the machine.**  Its addresses answer
nothing - a bus timeout, as on a real УКНЦ without that board - so a
program that probes for it finds it absent.  That is what the switches
are for: a program that misbehaves with a Covox or a mouse present can be
run without one.  The defaults are a plain machine with the Aberrant's
three AYs: floppy controller on, everything else that is an add-on off,
and nothing mounted.

### 7.2 Running a disk

1. **F12** to open the menu.
2. **FDD0:** and pick your `.dsk`.  The selector browses the card, so
   images can live in folders.  Drives 1 to 3 are under **Hardware ->
   FDD controller**.
3. **ESC** back out, then **Reset** on the main screen.
4. The machine restarts and boots from drive 0.

Drives 0 to 3 are the machine's four МХ2-01 floppies.  Mounting an image
while the machine is running is fine - it is the same as changing a disk -
but software that has already booted will not notice a new system disk
until you reset.

**Reset** restarts the processors and leaves memory alone.  **Cold Boot**
(under *Hardware -> Misc*) is the power-on path and clears it.  Use Cold
Boot when something has wedged badly, or when a program has left the
machine in a state a plain reset does not clear.

**FDDn write prot.** (under *Hardware -> FDD controller*) write-protects
one drive.  Set it before you boot something you do not trust; the images
on the card are ordinary files and a running program can write to them.

**HDD0:** is the IDE cartridge's disk, an `.img` file.  It appears on the
main screen once *Hardware -> HDD controller* is on, and the cartridge
exists only while both are true.

### 7.3 Sound

**Hardware -> Volume**: Mute, 33%, 66%, 100%.  It starts muted-ish until
the MCU sends its defaults, and the default for this core is 33%.

The machine has the Aberrant sound module's three AY-3-8912s, a one-bit
beeper, and two places a Covox can hang: the Aberrant's own DAC at
`177372` and port A of the printer port at `177100`, the older one that
players fall back to.  All of it is one mono sum to both channels.  Each
AY can be switched off (*Hardware -> Aberrant*), the beeper can be muted
(*Beeper*; it stays in the machine, it only leaves the sound), and
*Covox* picks which of the two DACs exist - *Off* is the default, and a
player that probes `177372` then finds nothing there.

There are two outputs, and they carry the same thing:

- **Over the HDMI cable**, since August 2026.  Nothing to wire and nothing
  to set: if your display or receiver plays HDMI audio it should just come
  out.  Two channels, 16-bit, at 48.97 kHz.
- **I²S**, on **Tang Nano 20K pins 71 (BCK), 72 (WS), 73 (DIN) and 74
  (amplifier enable)** - they moved there in August 2026 when the MCU link
  took back the pins upstream uses.  See section 2.1.

The Volume setting works on both.

The HDMI audio has played on a television since 1 Sep 2026 (the AYs,
at every volume setting).  The Covox and the printer-port DAC have been
checked in simulation only.

### 7.4 Video

**Hardware -> Misc -> Color: RGB / BGR** swaps the red and blue planes.
If the colours look wrong on your display, this is the switch.  (Until
v2.0.0 it swapped red and green, whatever its label said.)  Output is
HDMI from the Tang Nano 20K.

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

**Save settings** on the main screen writes an `.ini` at the root of the
card with the mounted images and the menu values in it - every hardware
switch, the write protections, the clock - and it is read back at the
next power-up.  See section 3 for which name it uses - that depends on
which firmware you flashed.

### 7.7 The clock and the mouse

*Hardware -> RTC clock* is the Kakave+ cartridge's real-time clock.  There
is no battery: the time you set here (or save) is where the clock starts
at power-up, and the last line of that screen shows it running.  *RTC
controller* puts the clock's register into the machine; *Mouse* does the
same for the cartridge's mouse register, fed from a USB mouse on the
BL616.

### 7.8 Swapping cards

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
