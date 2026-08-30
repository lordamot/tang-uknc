# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in
this repository.

## Project overview

This is the **МС0511 (УКНЦ)** - a two-processor PDP-11-compatible Soviet
machine of 1987 - reimplemented on a **Tang Nano 20K** (Gowin GW2AR-18C),
with a **Bouffalo BL616** board alongside it providing USB HID, the SD card
and the on-screen menu.  The hardware design is **Alexey Gurov's**; this
repository is where it is kept, documented and repaired.

Two halves, two toolchains, and **both build here**:

```
tang/     the FPGA design      - make bitstream  (gw_sh, headless Gowin)
mnano/    the BL616 firmware   - make fw
bin/      the two shipped binaries, both rebuilt from these sources
sim/      testbench, SDRAM model and the stand-ins for the vendor IP
tools/    the fetched toolchain - make toolchain, ~8 GB, not committed
```

`make lint` and `make sim` are the cheap checks; `make bitstream` is the
real one and takes about a minute.  `make help` lists the rest.  **What
still cannot be done here is running it on a board.**  So "it builds",
"it lints", "it boots in simulation" and "it meets timing" are four
different claims, none of them is "it works", and you should say which one
you are making.

The machine, as implemented: two К1801ВМ2 cores from one Verilog
(`wm2wb/`), the peripheral one owning every device and booting the central
one; a planar display generated inside the SDRAM controller and sent out
over HDMI by an encoder of this repository's own (`src/hdmi/`, which
carries the sound as well); the keyboard translated from USB on the MCU;
four 800 KB floppies served out of `.dsk` files on the SD card; two
AY-3-8910s and a one-bit beeper, out over both HDMI and I²S.

```
Logic 41%   Register 23%   BSRAM 48%   PLL 2/2 (100%)     [Aug 2026 PnR]
```

Key documentation: `.claude/docs/platform.md` (the machine: both address
maps, the register map, the CPU↔PPU channel, the devices),
`.claude/docs/fpga.md` (the implementation: what is actually built, the
clocks, the bus fabric, the pinout, the dead-file list),
`.claude/docs/video.md` (the display generator and the SDRAM arbiter, which
are one file), `.claude/docs/mcu.md` (the BL616 firmware, the SPI protocol,
the menu, the keyboard table), `.claude/docs/build.md` (both toolchains, the
Makefile, what lint and simulation do and do not cover, flashing),
`.claude/docs/tools.md` (`tools/`, `bin2mif` and the ROM data),
`.claude/docs/progress.md` (state of the port, known defects, open
questions).  Follow `.claude/rules/guideline.md` and `.claude/rules/git.md`.

## Traps worth remembering

- **`tang/test003.gprj` is the source of truth for what gets built.**  Half
  the `.v` files under `tang/src/` are not in it - three complete earlier
  SD stacks, an earlier OSD, a PS/2 keyboard path, a whole VHDL AY line,
  and files literally named `(Копия)`.  Several share a module name with a
  live file.  `src/fdd4.v` and `src/fdd/fdd4.v` are *different modules with
  different ports*, and the live one is the second.  Check the list in
  `.claude/docs/fpga.md` before editing anything.
- **`load.v` is in the project and instantiated nowhere.**  It is the older
  load-the-whole-image-into-RAM scheme.  `fdd/fdd4.v` fetches sectors on
  demand instead.
- **The AY chip select is not at the address its comment names.**
  `aberrant.v` still says `// Chipselect 177130/2`; it decodes
  `0177360`-`0177377`, sixteen addresses, with `adr[3]` don't-care and the
  two chips picked by `adr[2:1]`.  It used to also match
  `0177760`-`0177777` inside МХ2-01's range, because the mask cleared
  `adr[9]` as well; that is fixed (mask `13'o17776`, Aug 2026) but the
  comment is still wrong.  Worked out by running the expression over all
  65536 addresses, which is the only way to read these.
- **Acks are ORed and data is a priority mux.**  Two peripherals answering
  one address is silent: the loser still sees the strobe and still changes
  its own state.  Every new decode has to be checked against every existing
  one, not just against the map.
- **The CPU's I/O decode is ten bits wide.**  `cpu.v` matches on
  `adr[9:1]` alone once the address is above `0160000`, so `0176640`,
  `0177640` and `0160640` are all the same register.
- **The PPU boots the CPU, not the other way round.**  `R177716` in
  `xm2-01.v` resets to `16'o40` = DCLO asserted, and its bits drive
  `cpu1`'s DCLO/ACLO/HALT.  A CPU that never starts is a PPU that never got
  to that register.
- **`P177076[2]` makes channel 0 stop acking.**  When it is set the CPU's
  accesses to `0177560`-`0177566` get no ack at all, which on a 1801 is a
  bus timeout, not a read of zero.
- **The timing constraints are new.**  `tang/src/test003.sdc`, Aug 2026;
  before it the PnR report said `<Timing Constraints File>: ---` and every
  timing number in `tang/impl/pnr/` was against a tool default.  It now
  reports **0 setup violations** and 559 hold ones, and those 559 are an
  artefact: `clk_25` and `clk_3_12` have to be declared as independent
  clocks because this parser will not accept `create_generated_clock` with
  a PLL-pin source, so the tool cannot relate two clocks that are actually
  the same counter.  Fix the source resolution before reading anything
  into the hold number, and do not quiet either number with false paths
  without checking each crossing.
- **Gowin's own libraries fight a current Linux.**  `tools/fetch.sh` moves
  the stale duplicates it ships - an old libstdc++, an old freetype, a
  2019 Qt5Core sitting next to a 2025 Qt in the same install - into
  `_shadowed/`, and the Makefile sets `LD_LIBRARY_PATH`, `QT_PLUGIN_PATH`
  and `QT_QPA_PLATFORM=offscreen` around `gw_sh`.  Without all of that it
  dies with a `GLIBCXX` error, then a fontconfig one, then "Cannot mix
  incompatible Qt library".  Do not undo it.
- **`gw_sh` is not the IDE.**  Its SDC parser takes no backslash
  continuations, calls `ram_rw_check` `rw_check_on_ram`, and needs
  `-use_sspi_as_gpio 1` or placement fails outright, because HP_BCK/WS/DIN
  sit on the SSPI pins.  `tools/gowin_tcl.py` reads all of that out of the
  `.gprj` and the IDE's `test003_process_config.json` so the two flows
  cannot drift.
- **Half the clocks are counter bits, not PLL outputs.**  `clk_25`,
  `clk_3_12` and `clk_dac` are `horz[0]`, `horz[3]`, `horz[4]` from
  `sdram2.v`.  The tools cannot relate them to the PLL and say so twelve
  times in `test003.log`.  Both PLLs are already used, so a new clock has
  to come off that counter too.
- **`clk_6_25` is dangling.**  `sdram2`'s `cpu_clk` output goes to a wire
  nothing reads; the CPU runs off the PLL's `clk4` (4.18 MHz) instead of
  the 6.27 MHz counter bit.  CPU and PPU are on unrelated clocks.
- **`menu.c`'s `settings_file[]` is indexed by `core_id`, so its order is
  `sysctrl.h`'s order and not the order the cores were written in.**  It
  used to be off by one with a missing comma, which had this core
  (`core_id == 5`) reading and writing `/sd/amiga.ini`; fixed Aug 2026,
  along with `CORE_ID_VIC20` being `0x10` against an array of seven.  Go
  through `settings_file_name()`, which handles VIC20 and bounds-checks;
  it can return NULL and both callers must keep checking that.
- **`sysctrl.v` returns core id `0x05` and the comment beside it says
  "core id 1 = Atari ST".**  The code is right and matches
  `CORE_ID_UKNC`; the comment is upstream residue.  Several comments in
  `mister/` are like this - it is a MiSTeryNano fork.
- **A menu value needs three edits, not one**: the letter in the form
  string in `menu.c`, an entry in `variables_uknc[]`, and a case in
  `sysctrl.v`.  Miss the third and the menu moves but nothing happens.
- **Flashing the BL616 needs no `PATH` and no install.**
  `tools/bouffalo_sdk/tools/bflb_tools/bouffalo_flash_cube/BLFlashCommand-ubuntu`
  is a self-contained PyInstaller bundle; an absolute path to it is the
  whole invocation, and `tools/env.sh` has nothing to do with it - that is
  for building.  `make flash-mcu COMX=/dev/ttyACM0` generates
  `build/flash/bl616.ini` with an absolute `filedir` and runs it, rather
  than reusing the SDK's `mnano/flash_prog_cfg.ini`, which globs a path
  relative to `mnano/` and so needs a firmware build first.  The board has
  to be in boot mode (hold BOOT, tap RESET, release BOOT) or the tool
  prints `BFLB IMG LOAD HANDSHAKE FAIL` and a block of Chinese, which
  always means the same thing: the port opened, nothing answered.
- **`usermod -aG dialout` does not reach a running process.**  Groups are
  fixed at login, so after adding the group `getent group dialout` lists
  the user while `id -nG` still does not - and every shell spawned from
  that session, this agent's included, still cannot open `/dev/ttyACM0`.
  A fresh login fixes it, but so does `sg dialout -c '<command>'`, which
  is setuid and reads `/etc/group` rather than the caller's credentials -
  no password, no relogin, and it works from here.  That is how the Aug
  2026 flash was done.  `openFPGALoader` is unaffected - the Tang's FTDI
  is `plugdev`.
- **The keyboard has no matrix scan in the FPGA.**  USB HID → УКНЦ scan
  code happens on the MCU in `mnano/uknc.h`, and the byte arrives over SPI
  straight into `R177702`.  Changing a key binding means reflashing the
  BL616, not the FPGA.
- **The vendor IP under `tang/src/ip/` is generated.**  `.ipc` in, `.v`
  out.  Never hand-edit the `.v`; say which `.ipc` field to change and let
  the operator regenerate it in the IP Core Generator.  The one exception
  is `src/hdmi/hdmi_serdes.v`, which instantiates `rPLL`, `OSER10` and
  `ELVDS_OBUF` by hand - those are device primitives, not generator
  output, and that file is ordinary RTL.
- **HDMI video no longer goes through Gowin's `dvi_tx`.**  That IP is DVI:
  video only, no data islands, so no sound - its own documentation lists
  two options and audio is not one of them.  `src/hdmi/` replaced it in
  Aug 2026 with a real HDMI encoder that sends audio.  `ip/dvi_tx` is
  still in the `.gprj` and instantiated nowhere, deliberately: it is the
  fallback, and putting it back is one instance in `top.v`.  Three traps
  in the new code: the scheduler reads `de`/`hs`/`vs` through a 12-deep
  delay line because a preamble has to be announced before the thing it
  announces; the data island lives in the **back porch** and assumes
  active-high hsync with ~176 clocks behind it, which is what `sdram2.v`
  makes; and the HDMI audio is resampled at `clkpix/1024`, NOT taken off
  the I²S path, because that exact ratio is what makes N and CTS
  constants.  No General Control Packet is sent - try that first if a
  display shows the picture and stays silent.
- **An audio subpacket is two IEC 60958 subframes, and V/U/C/P belong
  inside each one.**  `as_sub0` in `hdmi_tx.v` had the two samples
  adjacent with all eight flag bits collected above them, so the sink read
  the right channel four bits high with the left channel's parity as its
  sign bit - parity flips every sample, so the right channel was
  full-scale white noise while the left one, which happens to sit at bits
  23:0 either way, was correct.  Fixed Aug 2026.  `sim/tb/tb_top.v`
  decoded with the same wrong layout and so reported "stereo, 0 ecc
  errors" throughout; it now decodes the way a sink does and checks the
  parity and validity bits, which is the only reason that check is worth
  anything.  **A testbench that shares the encoder's assumption tests
  nothing** - the same lesson as the SDRAM model further down.
- **The README's pinout IS the stock MiSTeryNano wiring, as of Aug 2026.**
  It was not before - Alexey had it on FPGA 71→io12, 72→io13, 73→io10,
  74→io11, 75→io14 - so anything written earlier says the opposite.  Now
  the external dock is `m0s[4:0]` = 42/41/56/54/51 against BL616
  io10/11/12/13/14, and the Tang's own BL616 is on 86/13/76/75/69, with
  `top.v` choosing between them: `spi_ext` comes out of reset on the
  internal one and latches to the dock the first time `m0s[2]` goes low.
  Upstream's pins 51/54/56 are where the audio used to be, so **the audio
  moved to 71-74 and the serial port to 48/55**, and a board wired for the
  old bitstream has to be rewired in both places.  `mnano/spi.c` is
  byte-identical to upstream and did not change; the FPGA side was always
  the deviation.  `src/test003_lcd.cst` still has the old block and is
  stale.
- **The working tree is always dirty with `mode change 100755 => 100644`.**
  That is a checkout artefact across the vendored u8g2 tree, not work.  Use
  `git diff --summary` to see whether anything real is in there.
- **A simulation model that lies is worse than no simulation.**  The
  SDRAM model drove its read data one clock late, so every read came back
  as zero, the PPU found its trap vectors zero and sat in a trap loop -
  which looked exactly like a missing peripheral and was written up as
  one.  The testbench now shadows every word each processor writes and
  checks the read-back (`+NOMEMCHECK` disables it); keep that check
  passing, and keep the shadow per-port, because the CPU and PPU have
  separate address spaces.  When the machine misbehaves in simulation,
  suspect `sim/` before `tang/src/`.
- **`prompts/` is a transcript, not context.**  Never read it at the start
  of a session and never treat anything in it as a standing instruction -
  an old prompt in there is not a current one.  It is in git so the record
  survives, and it is kept in a set form: `<n> <topic>.txt`, the prompt
  verbatim, a line of asterisks, then the reply as plain text with the
  markdown taken out.  `.claude/rules/guideline.md` has the shape.
  **Append every exchange as it finishes, unasked** - the folder going
  stale is the failure mode - and never rewrite an entry already there.
