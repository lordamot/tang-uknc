# Changelog

## Unreleased

- Reconfig support for `../tang-ultima` (three machines in one flash):
  SYS command 9 + A5h in `sysctrl.v` pulses `reconfig_n`, RECONFIG_N as a
  GPIO output on pin 9; `gowin_tcl.py --abs --multiboot-addr` and
  `timing_check.py <pnr dir>` for building out of this tree.  A build
  here is unchanged in behaviour: its header names address 0.

## 2.0.0 alpha - 3 September 2026

Hardware by Alexey Gurov; the 2.x line by Sergei Lemeshev and Claude Code.

### The machine
- Sound over HDMI, next to the I²S output: one mono mix of everything below.
- The Aberrant sound module: three AY-3-8912s at `177360/2/4`.
- Two Covox DACs: the Aberrant's at `177372` and the classic one on printer
  port A, `177100`.
- The IDE hard disk cartridge with its WD ROM: `.img` files on the SD card,
  CHS and LBA28, read-ahead, an adjustable data-read delay for streamed demos.
- The Kakave+ cartridge's mouse (a USB mouse on the BL616) and real-time clock.
- Four floppies from `.dsk` files, each with its own write protection.
- The keyboard as the machine sees it: matrix rows, rollover within a row.
- Stock MiSTeryNano wiring between the Tang Nano 20K and the BL616.

### The on-screen menu
- One "Hardware" page with a switch for every device above: a device that
  is off is not on the bus, as on a machine without that board.
- "Run SAV:" turns any `.SAV` on the card into a bootable RT-11 floppy.
- The clock as it runs, shown in the RTC page.
- Cursor left and right step a value; every page returns to where it was opened.
- The version in the caption, an "About" page, settings kept in `/uknc.ini`.

### For builders
- Both binaries build from the tree with `make bitstream` and `make fw`;
  lint, simulation of the whole machine, unit tests, a host build of the
  menu, and a timing gate that refuses a layout with an unanalysed crossing.
- An RT-11 base disk with test programs for the AYs, the Covox and the clock.
- Documentation: `howto.md` / `howto-ru.md`, and `.claude/docs/` for the design.

## 1.0 - March 2025

Alexey Gurov's original release: the two processors, the display over HDMI,
the floppies from `.dsk` files, the AY sound over I²S, the keyboard from USB
through the BL616, the menu.  `release/v1.0/`.
