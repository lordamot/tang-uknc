# Video and memory

Both live in one file: **`tang/src/sdram2.v`**, ~780 lines, which is the
SDRAM controller, the two-processor arbiter and the display generator at
once.  Changing any of the three means reading all three.

## The display timing

```
// 640x576 @ 50.00 Hz (GTF) hsync: 29.65 kHz; pclk: 23.72 MHz
// Modeline "640x600_50.00" 25.00 640 656 710 800 600 601 604 618
HSYNC 64   HBP 80   HACTV 640   HFP 16   HSTR 800
VSYNC  3   VBP 14   VACTV 600   VFP  1   VSTR 618
```

`horz` counts to `800*2` on `clkram` (50.14 MHz), so the pixel rate is
`clk_25` = 25.07 MHz and the frame rate is `25.07e6 / (800 * 618)` ≈
**50.7 Hz**.  The comment block above it is a leftover modeline and does
not describe what the code does - trust the defines and the counter.

`visible` = `visible_x && visible_y` and goes to `hdmi_tx` as data-enable.
`visiblez` = `visible_x && visible_z`, where `visible_z` is `vert > 19 &&
vert < 594`, is what actually gates the pixel colour - so about twenty
lines at the top and six at the bottom of the 600 are deliberately blanked.

`visible_x` starts at `horz >= 16`, not at 0, because the first byte of a
line has to be fetched eight pixels early; `xs` is `x - 8`, the
display-space coordinate, and `x` is the fetch-space one.  Getting these
two confused is the classic way to shift the picture by a byte.

## Pixel format

The УКНЦ screen is planar and the plane widths are selectable per line.
`vga_regi[21:20]` picks the resolution and everything downstream keys off
it:

| `vga_regi[21:20]` | pixels per byte | byte index | bit within byte |
|---|---|---|---|
| 0 | 8 | `x[9:3]` | `xs[2:0]` |
| 1 | 4 | `x[9:4]` | `xs[3:1]` |
| 2 | 2 | `x[9:5]` | `xs[4:2]` |
| 3 | 1 | `x[9:6]` | `xs[5:3]` |

Three planes are fetched into `red_data`/`green_data`/`blue_data`, one bit
of each is taken at `tx` to make `tripl[2:0]`, and `tripl` indexes the
eight 4-bit fields of `vga_regc` to give `cvt[3:0]`.  So the palette is
eight entries of four bits, held in one 32-bit register.

`cvt[2:0]` are the R, G, B enables and `cvt[3]` is the intensity bit.  The
final level per channel is `vga_regi[18:16]` (a per-channel full-brightness
override), then `cvt[3]`, then base:

```
111  if vga_regi[18] (red) / [17] (green) / [16] (blue)
110  else if cvt[3]
100  else
000  if the channel bit in cvt is clear, or outside visiblez
```

Three bits per channel out of `sdram2`; `top.v` widens them to eight for
`hdmi_tx` by appending two zeros to the six bits that come back from the
OSD blender.

## Cursor

`vga_regi[14:8]` (narrowed by the resolution, as `xcursor`) is the cursor
column, compared against `indx`.  `vga_regi[4]` selects a whole-byte cursor
versus a single-bit one at `vga_regi[7:5]`.  `vga_regi[3:0]` are its
colour: bits 2/1/0 are R/G/B and bit 3 is bright.  It blinks off
`vga_curs`, toggled by:

```verilog
always @(posedge clkram) begin
    curs_set_d <= curs_set;
    if (new_scr)                      vga_curs <= 1'b0;
    else if (curs_set && !curs_set_d) vga_curs <= ~vga_curs;
end
```

Until Sep 2026 this was `always @(posedge curs_set or posedge new_scr)` -
a **data signal used as a clock**, which the timing analyser could only be
told was a 1 us clock.  Same toggle-on-rise, clear-at-frame behaviour, one
`clkram` later.

## Line control words

`vga_adst` is the address of the current line's data and `vga_adnx` the
address of the next line's control word - it starts at `16'o270`.  Each
line's control word carries the next address, so the display is a linked
list walked once a frame, which is how the real machine does it and why
scrolling costs nothing.  `vga_regi` and `vga_regc` are reloaded per line
from it.

## The SDRAM side

MT48LC16M16-compatible part, the 64 Mbit die inside the GW2AR.  Single
access, no bursts (`NO_WRITE_BURST 1`, `BURST_LENGTH` configured but the
state machine issues one access per cycle), `CAS_LATENCY 2`,
`RASCAS_DELAY 2`, an 8-state cycle (`STATE_LAST 3'd7`) at 50 MHz.

Only the low 16 bits of the 32-bit bus are used: `top.v` ties
`IO_sdram_dq[31:16]` to Z and `O_sdram_dqm[3:2]` high.  So half the chip's
width - and with `SDRAM_A` declared `[10:0]` rather than the part's 13,
some of its depth - is not wired up.  There is room here if a future change
needs more memory bandwidth, but it is a controller rewrite, not a
parameter.

Two request ports, `cpu_*` and `ppu_*`, each: 19-bit address, 32-bit data
in and out, 4-bit `dqm`, `read`/`wrte` request, `busy` and `asck`
(data-valid / ready for the next). The display's own fetches are
interleaved into the same 8-state cycle and take priority - the processors
wait, which is exactly how the real machine's video steals cycles.

## The OSD

`mister/osd_u8g2.v` sits between `sdram2`'s RGB output and `hdmi_tx`.  It
takes 8-bit R/G/B in and gives 6-bit out, overlaying the menu the BL616
renders into it a byte at a time over SPI.  `system_video` from the OSD
swaps red and green on the way in (`red_m`/`green_m` in `top.v`) - that is
the "Video: RGB|BGR" menu entry.

## What happens to the pixels after that

`top.v` widens the six bits to eight, registers them on `clkpix` along
with `hsync`, `vsync` and `visible`, and hands them to `hdmi_tx` - not to
Gowin's `dvi_tx` any more.  The encoder is described in
`.claude/docs/fpga.md`, and the part of it that matters here is that it
takes the video timing entirely from those three signals and imposes
nothing of its own, so this file is still the only place the display mode
is decided.

One thing it does need from the mode, and does not check: the data island
goes in the **back porch**, which is where the blanking is in this design -
`hsync` is active high and 176 clocks of blanking follow it before the
active period. Moving the sync or shortening the back porch below about
160 clocks would run the island into the video preamble. The encoder gives
the video priority if that ever happens, so the picture survives and the
sound stops rather than the other way round, but it is worth knowing the
coupling is there.
