# Changelog

## 2.0.0 alpha - 3 September 2026

The first release of the v2.x line.  Hardware by Alexey Gurov; the update
by Sergei Lemeshev and Claude Code.

### OSD
- Restructured: main / Hardware / Aberrant / FDD controller /
  HDD controller / RTC clock / Misc, an About page, Save settings.  The
  version from `VERSION` at the right of the caption.
- Cursor left and right step a value either way; a form returns to the
  entry that opened it.
- Every add-on is a switch: the three AYs, the Covox (off, at 177372, on
  the printer port 177100, or both), the floppy controller, the IDE
  cartridge (HDD0: shown only while it is on), the Kakave+ mouse and
  clock.  Off means the device is not on the bus.  The beeper can be muted.
- Write protection per floppy drive; the old six-entry list sent an index
  the FPGA read as a bitmask.
- The RTC clock form shows the core's clock once a second.
- Color: RGB / BGR now swaps red and blue; it swapped red and green.

### FPGA
- A DAC on port A of the printer port, the older Covox players fall back to.
- The switches above in `sysctrl.v` and each peripheral; a clock read-back
  command for the OSD.

### Before 2.0.0 (August - September 2026, unnumbered)
- VM2 cores with the upstream cpu11 fixes; the AY chip select aliasing;
  HDMI with sound at exactly 48 kHz and the spec subpacket layout; the AY
  pitch (SEL); timing constraints on every crossing and a gate that refuses
  a layout without them; power-up ordering (SDRAM, PLLs, the PPU); the IDE
  cartridge with LBA28 and read-ahead; the Covox at 177372; the Kakave+
  mouse and clock; the keyboard matrix filter and byte queue; the
  interrupt-vector chain; "Run SAV:"; the RT-11 base disk and test programs.
