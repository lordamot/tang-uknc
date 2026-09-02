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
Logic 44%   Register 25%   BSRAM 48%   PLL 2/2 (100%)  [1 Sep 2026 PnR]
      (47% / 30% / 46% in the run before, which had the diagnostic monitor)
```

Key documentation: `.claude/docs/platform.md` (the machine: both address
maps, the register map, the CPU↔PPU channel, the devices),
`.claude/docs/fpga.md` (the implementation: what is actually built, the
clocks, the bus fabric, the pinout, what was removed and when),
`.claude/docs/video.md` (the display generator and the SDRAM arbiter, which
are one file), `.claude/docs/mcu.md` (the BL616 firmware, the SPI protocol,
the menu, the keyboard table), `.claude/docs/build.md` (both toolchains, the
Makefile, what lint and simulation do and do not cover, flashing),
`.claude/docs/tools.md` (`tools/`, `bin2mif` and the ROM data),
`.claude/docs/progress.md` (state of the port, known defects, open
questions).  Follow `.claude/rules/guideline.md` and `.claude/rules/git.md`.

## Traps worth remembering

- **`tang/test003.gprj` is the source of truth for what gets built, and
  since Sep 2026 the tree matches it.**  Until then half the `.v` files
  under `tang/src/` were not in it - three earlier SD stacks, an earlier
  OSD, a PS/2 path, a VHDL AY line, files named `(Копия)` - and several
  shared a module name with a live file; ten more were in the project and
  instantiated nowhere (`load.v`, `sdram1.v`, `dbg/dbgmon.v`, `ip/dvi_tx`
  among them).  All of that was removed; `.claude/docs/fpga.md` lists what
  went and `git log --all -- <path>` finds any of it.  Keep it that way:
  a new file goes into the `.gprj` or it does not go into `tang/src/`.
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
- **A flop clocked by a data signal is a die roll per placement.**  Until
  Sep 2026 `fdd4.v`, `top.v` and `sdram2.v` clocked flops off `step`,
  `clk_dsk`, `sd_rd`, `sd_img_mounted[n]` and `curs_set`; the SDC could
  only call those 1 us clocks, the tool routed them on general fabric,
  and a re-place-and-route broke the start screen with an SD card in.
  They are enables on real clocks now, `step` through a synchroniser (it
  changes on the PPU clock, the same counter as `clk_25`, so it moved AT
  the edge of the flop it clocked).  Do not write `always @(posedge
  <something that is not a clock>)`; `make fdd-test` shows how to prove
  the rewrite equivalent.  The SPI clock from the BL616 is declared as
  `spi_clk` in the SDC and its MISO path is analysed - keep it that way.
- **`gw_sh` is not the IDE.**  Its SDC parser takes no backslash
  continuations, calls `ram_rw_check` `rw_check_on_ram`, takes
  `set_clock_groups` only with `[get_clocks {...}]` (bare braces are a
  syntax error that aborts PnR - and `make bitstream` then fails, so read
  its exit status rather than the last log line), and needs
  `-use_sspi_as_gpio 1` or placement fails outright, because HP_BCK/WS/DIN
  sit on the SSPI pins.  `tools/gowin_tcl.py` reads all of that out of the
  `.gprj` and the IDE's `test003_process_config.json` so the two flows
  cannot drift.
- **Half the clocks are counter bits, not PLL outputs.**  `clk_25` and
  `clk_3_12` are `horz[0]` and `horz[3]` from `sdram2.v`.  The tools
  cannot relate them to the PLL and say so in `test003.log`.  Both PLLs
  are already used, so a new clock has to come off that counter too.
- **CPU and PPU are on unrelated clocks.**  The CPU runs off the PLL's
  `clk4` (4.18 MHz), the PPU off the counter.  `sdram2` used to export a
  6.27 MHz `cpu_clk` that `top.v` brought to a wire nothing read, and a
  `clk_dac` into a BUFG nothing read; both ports are gone (Sep 2026).
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
  Aug 2026 with a real HDMI encoder that sends audio.  `ip/dvi_tx` was
  removed from the tree in Sep 2026; it is in git history, and putting it
  back is the IP directory, its `.gprj` line and one instance in `top.v`.  Three traps
  in the new code: the scheduler reads `de`/`hs`/`vs` through a 12-deep
  delay line because a preamble has to be announced before the thing it
  announces; the data island lives in the **back porch** and assumes
  active-high hsync with ~176 clocks behind it, which is what `sdram2.v`
  makes; and the HDMI audio is resampled there, NOT taken off the I²S
  path.  It was `clkpix/1024` until Aug 2026, which is 48.968 kHz - 2%
  off standard while the channel status declared 48 kHz, and that
  disagreement drains a receiver's audio FIFO in about half a second.  It
  is now a phase accumulator: add `N` a pixel clock, take a sample at
  `128*CTS`, with **N = 6144 and CTS = 50140** making the ratio exact by
  construction whatever `f_TMDS` really is.  A General Control Packet **is**
  sent now, asserting **neither** mute flag (`SB0 = 8'h00`) - the file
  used to send `8'h10` on a bit order that contradicts HDMI 1.4b table
  5-8, and the experiment behind it was confounded.
- **An audio subpacket is NOT two IEC 60958 subframes end to end.**  HDMI
  1.4b table 5-12 puts the two 24-bit samples adjacent in bytes 0-5, left
  first, and all eight flags in byte 6 as `{PR,CR,UR,VR,PL,CL,UL,VL}`;
  hdl-util/hdmi, which plays on real sinks, builds exactly that word.
  `as_sub0` in `hdmi_tx.v` was changed on 30 Aug 2026 to the interleaved
  form - `{P,C,U,V,sample}` twice - on the reasoning that a subpacket is
  two subframes, and a trap here defended it.  On a sink that reads the
  spec layout that put **sample bits 15:12 into the left channel's V, U, C
  and P positions**: any negative sample, and any sample at or above
  16384, wrote a 1 into the channel status block the sink was reading, and
  a corrupt block is non-PCM or a rate change, so the sink muted.  That is
  the entire "unipolar plays, bipolar is silent" table, the beeper muting
  at 16384 and not at 8192, and three AY chips (peak 18360) muting where
  one or two (6120, 12240) played.  Reverted to the spec layout on 1 Sep
  2026; `sim/tb/tb_top.v` decoded with the same wrong layout and said
  "stereo, 0 bad parity" throughout, and now decodes table 5-12.  **A
  testbench that shares the encoder's assumption tests nothing** - the
  same lesson as the SDRAM model further down, and this time the shared
  assumption was written into this file as a trap.  Check a packet layout
  against the standard or a known-good encoder, never against a symptom.
- **The README's pinout IS the stock MiSTeryNano wiring, as of Aug 2026.**
  It was not before - Alexey had it on FPGA 71→io12, 72→io13, 73→io10,
  74→io11, 75→io14 - so anything written earlier says the opposite.  Now
  the external dock is `m0s[4:0]` = 42/41/56/54/51 against BL616
  io10/11/12/13/14, and that is the **only** MCU attachment.  Upstream's
  pins 51/54/56 are where the audio used to be, so **the audio moved to
  71-74**, and a board wired for the old bitstream has to be rewired
  there.  The serial port moved to 48/55 with it and then straight back to
  69/70; see the next trap.  `mnano/spi.c` is byte-identical to upstream
  and did not change; the FPGA side was always the deviation.
- **Pin 69 is the USB-C serial console, and upstream wants it for
  `spi_irqn`.  You cannot have both.**  MiSTeryNano also drives the Tang's
  own on-board BL616 over 86/13/76/75/69, muxed against the dock by a flop
  `spi_ext`.  This core carried that for one afternoon on 30 Aug 2026 and
  gave it up: 69 is the FPGA's TX into that same BL616, so the internal
  link costs the VP-65 console - and the console works, while the internal
  link had never been run on hardware, needs assembly 3921 or later, and
  costs the USB-JTAG bridge as well once you actually flash that chip.  So
  `uart_tx` is back on 69, `uart_rx` on 70, and 13/48/55/75/76/86 are
  free.  For a fortnight in Aug 2026 the pin carried the **diagnostic
  monitor** rather than the VP-65; that was removed on 31 Aug 2026 and
  `uart_tx` is `vp65_uart_tx` again - see the diagnostic monitor trap below.  Either
  way it is one `assign` and it changes none of the above, only which
  module drives the pin.  `git show 36e8c2b` has the removed form.  **The FPGA design never
  affected USB-C programming either way** - that is an FT2232 the on-board
  BL616 presents, independent of every user pin; only reflashing that
  BL616 takes it, and `howto.md` §5.5 is how to put it back.
- **The working tree is always dirty with `mode change 100755 => 100644`.**
  That is a checkout artefact across the vendored u8g2 tree, not work.  Use
  `git diff --summary` to see whether anything real is in there.
- **`sys_rst_n` is active HIGH, and the buttons read 0 released.**  The
  name is a lie: it is high for the first 335 ms and low after, and every
  module here takes it as `if (reset)`.  Wire it to something wanting an
  active-low reset and you get a block that runs for a third of a second
  after power-on and is then held in reset forever - which is exactly what
  happened to `dbgmon` and cost a build.  `sys_rst` is the active-low one.
  The same reasoning settles the buttons: `n_all_rst = init & ~buts[0]`
  only makes sense if pressing S1 is what forces the reset, so **0 is
  released and 1 is pressed**, whatever `PULL_MODE=UP` in the `.cst` says.
- **A sample the encoder latches must be REGISTERED, not combinational.**
  `volume_data_l/r` were an `always @(*)` and `hdmi_tx` latches them at the
  audio sample instant, which has no relation to the PPU clock the mixer
  runs on - so the encoder could send a carry-chain intermediate as a
  sample.  It looked like a dead audio path rather than noise because the
  old divider took a sample every 1024 pixel clocks and `ppuclk_p` is
  `clkram/16`: 1024 = 64*16, so the sample instant sat at ONE fixed phase
  forever, and if that phase is the settling window then every sample is
  wrong, every time.  Anything crossing from the mixer to the encoder gets
  a flop.
- **There is no diagnostic monitor in the tree any more.**  For a
  fortnight in Aug 2026 `src/dbg/dbgmon.v` printed 18 hex words ten times
  a second down the USB-C serial line and `tools/dbgmon.py` read them, so
  a running board could be measured from here.  The instance and its ~160
  lines of probe accumulators came out of `top.v` on 31 Aug 2026 and the
  module and reader left the tree in Sep 2026; `git log --all --
  tang/src/dbg` finds the module (the reader was never tracked - `tools/`
  is gitignored), and `.claude/docs/fpga.md` keeps what was learned.  The main lesson: its probes sampled
  `volume_data_l` on `posedge ppuclk_p`, in the mixer's own domain, so a
  value wrong only *between* clock edges read as perfect - that is the
  bug above, and the monitor agreed with the design for three build cycles
  while the board disagreed with both.
- **Flashing the FPGA is replug, flash, power-cycle - in that order.**
  `openFPGALoader -f -r` writes the flash and reports success but does
  **not** reliably reconfigure the chip, so without the power cycle you
  are testing the previous bitstream; that cost a whole test run.  And
  once anything has opened `/dev/ttyUSB*`, the next flash dies with
  `ftdi_usb_reset failed` - the FT2232 is emulated by the on-board BL616
  and will not take a second USB reset - so only replugging the cable
  clears it, and `--skip-reset` does not help because the reset is inside
  the device open.  Do **not** reach for a `USBDEVFS_RESET` ioctl: it
  drops the device off the bus entirely and needs the replug anyway.
- **The sound is still a unipolar sum, and the reason it had to be is now
  known and is not the sum.**  Four states went on the board in Aug 2026:
  the raw sum plays; minus a constant 512, DC-blocked bipolar, and
  DC-blocked plus an offset are all silent.  That was read as a sink that
  will not take a bipolar stream and no mechanism was known.  The
  mechanism was the subpacket layout above: every silent form put a 1
  into sample bit 15 or bit 14, which the sink read as the left channel's
  parity and channel-status bits.  The DC blocker that was removed on 31
  Aug 2026 (`git show f2bb44b^`) was never the problem and is worth
  putting back once the fixed layout has been heard on a board - the mean
  really does step with the program material, +3000 under one chip and
  +9000 under three, and a sink's own AC coupling turns each step into a
  thump.  The layout fix went out alone on purpose, one variable at a
  time; **S2 still does nothing**.
- **`ym2149.sv`'s `SEL` is a prescaler select, and 1 means "my clock enable
  is twice the chip clock".**  The divider reloads with `{SEL, 3'b111}`:
  0 divides by 8, which is the chip; 1 divides by 16.  `aberrant.v` feeds
  the cores the chip's own 1.7734 MHz and so wants `SEL=0`; it had `SEL=1`
  until 2 Sep 2026, and every tone was an octave low and every envelope
  at half speed - heard as "the bass is filtered out", because a bass
  line an octave down is under a television speaker's floor.  `make
  ab-test` now counts edges over a simulated second and fails on a wrong
  pitch; "it oscillates" is not a pitch check.  The old "1.77 times too
  fast" figure in the history was computed without this pin and is wrong.
- **Real software never sets the beeper tone bits.**  `R177716[12:8]`
  selects among 8 kHz/1 kHz/500/250/60, and over 234 seconds of a running
  machine the register took four values - `100000`, `100020`, `100200`,
  `100220` - and none of them touched `[12:8]`.  The music is bit 7
  toggled in a timing loop, 177-473 writes per 100 ms.  The divider chain
  in `xm2-01.v` is dead code for anything that actually runs.
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
