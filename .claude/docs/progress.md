# State of the port

Last bitstream: **1 September 2026** (`bin/tang.fs`, 7262008 bytes), built
here with `make bitstream` and carrying every RTL change in this file -
the four VM2 core fixes, the AY chipselect, the stereo audio, the first
timing constraints, the return to stock MiSTeryNano wiring, HDMI audio,
the audio subpacket layout fix (defect 11) and the September tree cleanup
(**Repository hygiene** below), which changed no logic and left the
placement where it was: Logic 44%, Register 25%, BSRAM 48%, 0
setup-violated endpoints and 524 hold (the artefact defect 3 describes).  Last MCU firmware: **30 August 2026**
(`bin/bl616.bin`, 430512 bytes), also built here, carrying the
settings-file fix.  The bitstream of 30 Aug was on hardware and played AY
music under one or two chips; **this one has not been heard.**  The
machine runs: both processors, screen over HDMI, USB keyboard through the
BL616, four floppies off the SD card, AY sound and the beeper, and the OSD
menu.

This file is the running record.  Everything below was established by
reading the sources in August 2026 and, from the end of that month, by
linting and simulating them.  None of it has been checked on hardware from
here, and this host still cannot build the bitstream.

## What the host can do, as of August 2026

Everything except run it on a board.  `make toolchain` fetches Verilator,
Yosys, GTKWave, openFPGALoader, CMake, Ninja, a T-Head RISC-V GCC, the
Bouffalo SDK **and Gowin EDA Education** into `tools/`, none of it
installed on the host and none of it committed.  On top of that:

- **`make bitstream` builds the FPGA bitstream** in about a minute, using
  Gowin's headless `gw_sh`, and copies it to `bin/tang.fs`.  This was
  believed impossible until it was tried: the Education edition is a free
  tarball, needs no licence for the GW2AR-18C, and only needed its own
  stale bundled libraries moved out of the way.  See
  `.claude/docs/build.md` for the three things that had to be settled.
  Current resource use (2 Sep 2026, with the IDE cartridge): Logic 47%,
  Register 26%, BSRAM 64%, PLL 2/2.  Before the cartridge it was Logic
  44%, Register 25%, BSRAM 48%; the original January 2025 figures were
  Logic 41%, Register 23%, BSRAM 48%, PLL 2/2,
  IOLOGIC 7%.  BSRAM went from 46% with the second audio FIFO for stereo;
  logic from 39% with the HDMI encoder; the IOLOGIC row is the four
  OSER10s and is new.  Timing: 14651 paths, 8997 endpoints, **0 setup
  violations**, 583 hold - the hold number being the artefact
  `tang/src/test003.sdc` describes at length, not a finding.

- **`make lint` is clean.**  Verilator reads every source in
  `tang/test003.gprj` - `tools/srcs.py` gets the list out of the project
  XML so it cannot drift - with `sim/stubs/gowin_ip_sim.v` in place of the
  vendor IP.  Zero errors, many warnings, all of them the author's.
- **`make fw` builds the firmware** into `build/fw/bl616.bin`, and that is
  now what `bin/bl616.bin` is - copy it across whenever `mnano/` changes,
  since a user flashing from `bin/` is the point of the directory.  It is
  built against a newer SDK than the August 2024 binary it replaced and is
  not byte-comparable with it.  See `.claude/docs/build.md` for the three
  things that had to be settled to get it to compile at all.
- **`make sim` runs the machine**: `sim/tb/tb_top.v` against a functional
  SDRAM model and a stand-in BL616 that speaks the real SPI protocol.
  About 10 ms of simulated time per wall second.
- **There is no `synth` target.**  Yosys segfaults on these sources at
  `read_verilog`, and three of the IP cores are encrypted anyway.

### What the simulation shows

The machine boots.  Reproduced at 900 ms of simulated time:

```
[tb] 12.2 us   PPU first bus cycle, addr 0360000
[tb] 326 us    FPGA ready, core id 0x05 (expect 05 = UKNC)
[tb] 391 us    released reset
[tb] 45.29 ms  CPU DCLO released by the PPU
[tb] 45.29 ms  R177716 000040 -> 000000  (dclo=0 halt=0 aclo=1)
[tb] 45.54 ms  CPU ACLO released
[tb] 45.54 ms  R177716 000000 -> 100000  (dclo=0 halt=0 aclo=0)
[tb] 45.55 ms  CPU first bus cycle, addr 0360000
[tb] 900 ms    done: 46 video frames, leds=110010
[tb] memory ops: ppu 150905, cpu 819911
[tb] read-after-write: 135172 checked, 0 wrong
```

So: the MCU side answers `5c 42` and reports core id 5; the PPU runs its
power-on RAM walk from `070000` upward; at 45 ms it clears bit 5 of
`R177716` and the central processor starts; both processors then run, and
every word either of them reads back is the word it wrote.  Video runs at
51 Hz.

**The screen draws.**  `make frames RUN_MS=1400 PPM_FROM=1200` gives a
1280x600 frame with white and blue on black reading

```
СТАРТОВЫЙ ТЕСТ
- ошибка ОЗУ ЦП
```

- the start-up test, reporting a CPU RAM error.  Which is exactly what the
read-after-write check says: 31 mismatches out of 1118476, nearly all of
them bank 1 - the CPU's RAM - around `070020`-`070024` at about 1.038 s.
The machine's own diagnostic and the testbench's independent check agree,
so something in the CPU memory path really does return the wrong word.
Given the last two faults were both in `sim/`, suspect the SDRAM model
first: it does not implement auto-precharge, and its single read pipeline
mixes the tail of one 4-word burst with the head of the next when the
controller interleaves the two banks a few cycles apart, which is exactly
the shape of an occasional wrong word.  **That is the open end of this.**

Until the SPI master in the testbench was fixed (below) it was worse: the
PPU set bit 4 of `R177716` at 1.047 s and halted the CPU, the screen never
drew at all, and the check reported 201 mismatches.  All three were the
testbench's fault.

The memory check itself took three attempts to key correctly, which is
worth knowing before trusting a number out of it.  `sdram2.v` fetches from
**both banks in every processor slot** - bank 0 is the PPU's own RAM, bank
1 is the CPU's - and the four-byte mask picks which half of the 32-bit port
word means anything: mask `1100` is the low half and bank 0, `0011` the
high half and bank 1.  Bank 1 is reachable from both ports, which is how
the PPU loads the CPU's memory and where the video reads the screen from.
Keying the shadow by port reports every cross-write as a fault; keying it
by bank is right, and raised the coverage from 71766 checks to 1118476.

#### Two bugs that were not in the design

Neither of the two faults that looked like the machine misbehaving was in
`tang/src/`.  Both were in `sim/`, and both are worth recording because of
how convincing they were.

**One clock cycle in the SDRAM model.**  The read data was driven from
stage `CAS` of the latency pipeline instead of `CAS-1`; stage 0 is loaded
by a non-blocking assignment on the edge that carries the READ command, so
it only becomes visible after that edge, and driving from stage `CAS` put
every word on the bus one clock after the controller had already sampled
it.  **Every read returned zero.**  The PPU found all its trap vectors
zero, jumped to zero, executed zero as a HALT, trapped again, and went
round for ever - which looked exactly like a machine waiting on a device it
did not have, and was written up here as a missing SD card model.

**A delta-cycle race in the testbench's SPI master.**  `mcu_spi.v` samples
MOSI on `always @(negedge spi_io_clk)`, and the master assigned the next
bit at the same timestamp as that edge.  The slave lost the race every
time, so **every byte arrived shifted one bit left**: `0x04` became `0x08`
and `"R"` (`0x52`) became `0xA4`.  No configuration value ever matched its
letter, so the machine was never configured at all - it ran only because
Verilator zero-initialises `system_reset`, and the volume stayed at mute.
The status command survived because it is `0x00`, which shifts to `0x00`,
so the handshake looked perfect.  Fixed with a hold time after the falling
edge; `+SPITRACE` now prints what sysctrl actually receives.

Two checks came out of these.  The testbench keeps a shadow copy of every
word each processor writes and compares it against what comes back
(`+NOMEMCHECK` turns it off), per port, because the CPU and PPU have
separate address spaces.  And an I2S monitor decodes the audio off the pin,
which is the only way to tell a stereo path from a mono one without
headphones.

There is still **no SD card model** - `sdcmd` and `sddat0..3` have pull-ups
and nothing else, and `sd_card`'s `sdcmd_in`/`sddat_in` (its `ifdef
VERILATOR` split-port inputs) are not connected in `top.v` at all, which is
where the two PINMISSING warnings in the lint come from.  So no disk can be
read in simulation.

#### The bug that was not in the design

The first version of this testbench had the machine stuck in a trap loop
with the CPU never started, and the note here blamed the missing SD card
model.  That was wrong, and worth recording because of how it was wrong.

The real fault was one clock cycle in `sim/stubs/sdram_model.v`.  The read
data was driven from stage `CAS` of the latency pipeline instead of
`CAS-1`; stage 0 is loaded by a non-blocking assignment on the edge that
carries the READ command, so it only becomes visible after that edge, and
driving from stage `CAS` put every word on the bus one clock after the
controller had already sampled it.  **Every read returned zero.**  The PPU
therefore found all its trap vectors zero, jumped to zero, executed zero
as a HALT, trapped again, and went round for ever.  All of that looked
exactly like a machine waiting on a device it did not have.

Two things came out of it.  The testbench now keeps a shadow copy of every
word each processor writes and checks it against what comes back
(`+NOMEMCHECK` turns it off), which would have found this in the first
second.  And the shadow is per-port: the CPU and PPU have separate address
spaces and land in different parts of the SDRAM, so one shared array
reports tens of thousands of mismatches that are the check's own fault.

There is still **no SD card model** - `sdcmd` and `sddat0..3` have pull-ups
and nothing else, and `sd_card`'s `sdcmd_in`/`sddat_in` (its `ifdef
VERILATOR` split-port inputs) are not connected in `top.v` at all, which is
where the two PINMISSING warnings in the lint come from.  So no disk can
be read in simulation.  That is a real gap; it just was not this one.

## Known defects

### 1. The AY chip select was not where its comment says - FIXED

`aberrant.v:37`.  The decode was

```verilog
// Chipselect 177130/2
wire ceppu = ~(|((ppu_wbm_adr_i[15:3] ^ 13'o17736) & 13'o17736));
```

Run over the address range, the mask leaves two bits of the compare
don't-care - `adr[3]` and `adr[9]` - and matched **32 addresses**:
`0177360`-`0177377` *and* `0177760`-`0177777`.  The second range is inside
МХ2-01's `0177700`-`0177777`.  The priority mux in `top.v` hid it on
reads; writes were not hidden, so every write to `0177760`-`0177776` also
clocked `bdir`/`bc` into the AYs.

Fixed by changing the mask to `13'o17776`, which compares `adr[9]` and
leaves only `adr[3]` don't-care.  The decode is now `0177360`-`0177377`
and nothing else - 16 addresses, verified by running the expression over
all 65536.  `adr[3]` stays don't-care deliberately: it is why
`0177370`-`0177377` answers as well as `0177360`-`0177367`, and the two
chips are picked by `adr[2:1]`, not by `adr[3]`.

The design lints clean and the machine still boots in simulation with
exactly the same timings.  **Not tried on hardware.**

### 2. `menu.c` opened the wrong settings file - FIXED

`mnano/menu.c:427`.  `settings_file[]` had three faults at once: a missing
comma that welded `"/uknc.ini"` and `"/agat9.ini"` into one string, an
order that did not match the `CORE_ID_*` defines in `sysctrl.h` (so this
core, id 5, read and wrote **`/sd/amiga.ini`**), and `CORE_ID_VIC20` being
`0x10` against an array of seven.

The table now follows `sysctrl.h` exactly, and `settings_file_name()`
handles VIC20 separately and bounds-checks everything else, returning NULL
for a core with no settings file.  Both callers check that NULL - opening
it would have taken FatFs down.  The firmware builds.  **Not tried on
hardware, and it needs a reflash to take effect.**

### 2b. The VM2 core's `inc (PC)+` bug - FIXED

`tang/src/wm2wb/vm2_wb.v:626`.  The vendored copy of 1801BM1/cpu11's VM2
core dates from October 2023 and carried the `dc_fl` bug reported as
upstream issue #31: `dc_fl` was formed from the *registered* copies of the
predecoder's exchange-type flags, which can change on the same edge, so in
a synchronous model it latched the previous clock's state.  `ix[0]` - the
RMW flag - is loaded from it, so an `inc (PC)+` following an instruction
that had set the exchange type to read (upstream's test uses `cmp #1, #1`)
read the prefetch register instead of performing the read-modify-write.

Fixed by taking the upstream patch verbatim (commit `e057663`, 22 Aug
2026): the `ir_stb` branch now reads `pld[5]`, `pld[4]` and `pld[3]`
directly instead of `dc_bi`/`dc_iord`/`dc_iowr`.  **Both** processors are
this same module, so it applies to the CPU and the PPU alike.  Lints
clean; the machine boots in simulation with unchanged timings, and it does
not change the 1.037 s mismatches or the 1.047 s halt described above.
**Not tried on hardware.**

Our copy still predates two other upstream fixes worth knowing about:
`8d097ae` (Aug 2024, non-blocking assignment in the prefetch) and
`abe8b68`/`2f765b4` (Dec 2023, shadow PSW/PC in halt mode, and the
interrupt-acknowledge timeout vector).  None has been applied.

### 2c. The remaining upstream VM2 fixes - APPLIED

Three more commits from 1801BM1/cpu11 postdate this tree's October 2023
copy of the core and are now in:

- `8d097ae` (Aug 2024) - `bir_fix` was assigned with `=` inside a clocked
  block.  Upstream calls it a syntax issue with no synthesis impact; taken
  for the sake of staying in step.
- `abe8b68` (Dec 2023) - shadow PSW/PC update in halt mode.  `cpsw_stb`
  tested `psw[]` rather than `psw_rc[]`, so the write that clears PSW[7] to
  let interrupts in did not itself unfreeze the shadow registers, and an
  interrupt taken on that write stacked stale values and returned to the
  wrong place.
- `2f765b4` (Dec 2023) - interrupt-acknowledge timeout vector.  A bus
  timeout during an IAKO cycle has to raise the halt-mode exception on
  vector 274; it raised the ordinary bus exception on vector 4 because the
  IAKO flag was no longer held when the interrupt matrix looked.  The
  commit also adds `tadone` to stop repeated abort requests turning it into
  the double-timeout exception on vector 174.

All four VM2 fixes together lint clean and the machine boots in simulation
with unchanged timings.  **None has been on hardware.**

### 2d. The AY played mono - FIXED

`aberrant.v` pans the two AYs the usual way - `l_channel` is A + B/2 and
`r_channel` is C + B/2 - but `top.v` mixed only `m_channel`, so both I2S
slots got the same word and the panning was discarded.  `left_channel` and
`right_channel` were declared and driven and read by nothing.

Now `top.v` builds a left and a right mix (the channels are 11 bits against
mono's 12, so they shift up one place further to keep the same full-scale
point; the one-bit beeper is centre and goes into both), feeds each to its
own `fifo_audio` instance, and `audio.v` picks which word goes into which
I2S slot from `b_cnt[4]`.  A second instance of the same FIFO core costs
one more BSRAM block and avoids an IP Core Generator run - regenerating
`fifo_audio` at 32 bits wide would be the tidier answer if BSRAM ever gets
tight.

Verified at the pin: with two different constants forced onto the panned
outputs (`+AUDIOTEST`), 5945 of 5970 I2S frames carry sound and L differs
from R in every one of them; without the force the machine is silent, which
it is - nothing in it plays anything during these runs.  `m_channel` is
still connected and now read by nothing, which is what a mono menu option
would use.

### 3. No timing constraints - FIXED, AND NOW RUN

`tang/impl/pnr/test003.rpt.txt` reported `<Timing Constraints File>: ---`,
so every timing number the tool has produced for this design was against
its own default and meant nothing.

`tang/src/test003.sdc` now exists and is in `test003.gprj`.  It names the
clocks and does nothing else: `clk27` at 37.037 ns, the four counter-bit
clocks as generated clocks off `clkram` with their real divides (2, 8, 16,
32), and a false path off the two data-driven pseudo-clocks (`curs_set`
and `sd_img_mounted[*]`).  The PLL outputs are left to be derived through
the rPLL primitive rather than declared by hand, which would replace the
derived clock and get `clkoutp`'s phase wrong.

It has now been run, on every `make bitstream`:

```
Paths analysed                 13809
Endpoints analysed              8629
Setup-violated endpoints            0     (729 before the clocks were declared)
Hold-violated endpoints           559

clk_25    needs  25.071 MHz,  makes 106.612 MHz
clk_3_12  needs   3.134 MHz,  makes  40.105 MHz
PLL CLKOUT       50.143 MHz,  makes  67.225 MHz
PLL CLKOUTD       4.179 MHz,  makes  41.239 MHz
```

**Setup is clean with real margin everywhere.**  The 559 hold violations
are not a separate discovery - they are the cost of a compromise.  This
version's SDC parser will not resolve a `create_generated_clock` source:
neither `[get_nets {clkram}]` (TA1061 - the name does not survive
synthesis) nor `[get_pins {pl1/rpll_inst/CLKOUT}]`, with or without
`-master_clock`, is accepted (TA2004).  So `clk_25` and `clk_3_12` are
declared as independent `create_clock`s at their true periods.  The
analysis inside each domain is then right, but the tool cannot relate the
edges of two clocks that are physically the same counter, and analyses the
crossings between them at worst case.  **Make the generated-clock form
resolve before reading anything into that 559.**

Two more things learned by running it.  `clk_6_25` could not be
constrained at all - it was `sdram2`'s `cpu_clk`, brought out to a wire
nothing read and removed by synthesis, which was defect 5 below showing up
in a second place; the port is gone now.  And five signals that are flops clocked by data
(`ram1/curs_set`, `isread_aud`, `disk_step`, `fdd/clk_dsk`,
`dd1/timer_clk_4`) were being analysed at the tool's default 100 MHz,
which is where most of the original 729 setup violations came from; they
are now declared at 1 us, a deliberate bound rather than a measurement.

Still undone, in the order worth doing: make the generated clocks resolve,
then `set_input_delay`/`set_output_delay` on the SDRAM pins (the whole file
constrains the inside of the chip only), the same for TMDS, and the
question of whether `clk4` and `clk_3_12` can honestly be declared
asynchronous.

### 4. Clocks that the tools cannot reason about - MOSTLY FIXED

What this was: a timing tool checks every path from a clock edge to the
next clock edge, and it can only do that for nets it knows are clocks.
Where a design clocks a flop from a data signal, or from a clock the tool
cannot relate to the others, that path is either unchecked or checked
against a made-up number.  Unchecked paths are not wrong; they are
untested, and each place-and-route routes them differently, so a build
works or does not by luck.  That is what "the start screen stopped
appearing with an SD card present" after a re-layout was.

- **Flops clocked by data signals - FIXED, Sep 2026.**  `fdd4.v` clocked
  `no_trk` off `step` (a PPU register bit), `sd_rd`/`_trk`/`_sek`/`_data`
  and the track ROM off `clk_dsk_n`, `count_word` off `clk_dsk`, and
  `read_sd` off `sd_rd` with an asynchronous clear; `top.v` clocked the
  four `mount_dsk` flops off `sd_img_mounted[n]`; `sdram2.v` clocked
  `vga_curs` off `curs_set`.  All of it now runs on the clock the signal
  belongs to, with the pulse as an enable and `step` through two flops and
  an edge detector.  `step` was the worst of them: it changes on the PPU
  clock, which is the same counter as `clk_25`, so it moved at the very
  edge of the 25 MHz flop it clocked, and a routing change could move it
  to either side.  `sim/tb/tb_fdd4.v` (`make fdd-test`) runs the old
  module out of git beside the new one and compares the words the PPU
  reads, the sectors requested and the head position across a spin,
  stepping past track 0, an empty drive and a motor restart - all agree,
  status lines never differ for more than two 25 MHz cycles.  Full-machine
  simulation boots identically (15 frames at 300 ms, the same single
  read-after-write miss at 177 ms as the unmodified tree - see the open
  question).  The `curs_set`, `disk_step` and `clk_dsk` clocks are gone
  from the SDC and `sd_img_mounted[0..3]` no longer appear in the report
  as tool-invented 100 MHz clocks.
- **The MCU's SPI link - NOW CONSTRAINED.**  `m0s[3]` is the BL616's
  20 MHz SPI clock on a general I/O pin (`PR1014` says it is routed on
  fabric).  It was not declared, so the MISO path - clock in through
  fabric, the flop in `mcu_spi.v`, the pad - against the MCU's sampling
  edge 25 ns later was never checked, and it is the path the power-on
  handshake and every SD mount goes through.  `test003.sdc` now declares
  `spi_clk` at 50 ns with input and output delays against the falling
  edge and puts it in its own asynchronous group; the report analyses it
  (Fmax 31.6 MHz against the 20 MHz needed).  The delays are bounds, not
  measurements of the BL616.
- **The counter-bit clocks - RELATED TO THE PLL, 2 Sep 2026.**  The
  form the parser accepts: `clkram` declared as a base clock on the PLL
  pin `pl1/rpll_inst/CLKOUT`, then `clk4`, `clk_25` and `clk_3_12` as
  `create_generated_clock` with that pin as `-source` and `-master_clock
  clkram`, targets `pl1/rpll_inst/CLKOUTD`, `ram1/horz_0_s0/Q` and
  `ram1/horz_3_s0/Q`.  Both earlier forms (PLL pin as source without a
  named master; the flop's own CLK pin as source) fail with TA2004.  The
  BUFG output `t3/O` is accepted as a target but its inverted twin
  `t3n/O` is refused (TA2003), so the Q pin it is.  Result: every TA1117
  gone, hold count 656 -> 56, setup still 0.  Of the 56, the ones inside
  `ram1` from `clk_3_12`/`clk_25` to `clkram` are an artefact of the
  clock sitting on a Q pin that also feeds the SDRAM state machine; the
  real ones are `clk_25 -> clk_3_12` on slow control words (volume,
  keyboard, floppy status), 0.2-0.4 ns, harmless on a level.  **What this
  changes on the board:** every clk4 edge lands on a clk_25 edge, so the
  CPU's bus into `vp1_120` (the CPU-PPU channel) was a hold race on every
  capture that the tool never looked at, and a placement decided it.  Now
  it is analysed and fixed by routing.  Defect 13 has the board evidence.

  **And the phase has to be right.**  `-divide_by` puts every generated
  clock's rising edge on master edge 1, so the first form had clk_25 and
  clk_3_12 rising together.  They do not: `horz` counts clkram edges,
  horz[0] rises on odd ones, horz[3] toggles when horz[2:0] wraps, an
  even one - so every PPU edge sits on a clk_25 FALLING edge, 20 ns from
  the nearest rising.  With the wrong model the tool checked clk_25 ->
  PPU paths for hold as coincident (false violations) and for setup as
  320 ns (never), and a 20 ns path it never optimised - the floppy's
  status word into `vp1_128fdd` - came out of the 09:51 placement too
  slow: start screen fine, floppy load hung with "зависание при приеме
  А.В.Р.".  `-edges {3 5 7}` for clk_25 and `{17 33 49}` for clk_3_12
  put the edges where they are; the report then shows the PPU-to-channel
  paths as the tightest in the design at 6.6 ns of slack, the false hold
  lines gone, 0 setup violations, 20 hold of which 19 are the `ram1`
  artefact and one is a video register reset at -0.085 ns.

  **And clk4's phase is a lottery.**  clk4 is the PLL's own /12 and
  `horz` starts at lock, so whether clk4's edges land on odd or even
  clkram edges - on a clk_25 rising edge (hold race) or 20 ns from one
  (setup window) - is decided at each power-up.  One `-edges` cannot
  say "either", so clk4 is defined on the coincident edge (`{3 15 27}`)
  for hold and `set_max_delay 15` caps every path between clk4 and the
  clk_25 and clk_3_12 domains for the other case.  That cap immediately
  failed on the CPU's DCLO/ACLO/HALT, which fanned out from `R177716`
  straight into dozens of enables in the CPU core; those three now go
  through two flops on the CPU clock in `top.v`.  clk_3_12 is written
  on the BUFG output `t3/O` with the inverted clock made from that
  output, but the tool resolves the target back to horz[3]'s Q, so the
  false hold lines from horz[0] and horz[3] into the SDRAM state machine
  remain - 15 in the 10:43 build, all inside `ram1`, all really
  clkram -> clkram.  The gate allows exactly that pattern, plus one
  named exception: the OSD enable onto a video register's reset pin,
  bounded at -0.2 ns.  The 10:43 build: 0 setup violations, tightest
  real paths the PPU- and CPU-to-channel ones at 4.2 ns of slack under
  the 15 ns cap, `make timing` green.  **Built and gated, not run on
  the board** - the board has the 10:22 build.

  **The artefact then went away for good, and what it had hidden came
  out.**  Adding the IDE cartridge moved the placement and the `ram1`
  lines went from 15 to 64, more than the report lists, so the gate
  could no longer vouch for the rest.  `sdram2.v` now makes clk_25 and
  the PPU clock from two flops of their own (`clk25_q`, `clk312_q`,
  `syn_preserve`), in lockstep with the counter bits and feeding nothing
  but the clock network, and the generated clocks sit on those.  The
  next report had four hold lines, all real: three clkram -> clk_25
  into the pixel sampler `tripl` and one clk4 -> clk_25 from a CPU
  register into the channel's `P177062`, each a tenth of a nanosecond
  short on a coincident edge - the CPU one being the exact race that
  blanked the screen that morning.  Two answers, both kept: the
  headless flow now passes the IDE's `Correct_Hold_Violation` on to the
  router (`tools/gowin_tcl.py`, `set_option -correct_hold_violation`),
  and `vp1_120.v`'s CPU side no longer relies on winning that race - the
  strobe goes through two flops, the decode fires on the synchronised
  copy when address and data have been stable for two clocks, and the
  ack (data and interrupt-vector alike) goes out one clock after the
  data, 80 ns a CPU access to the channel.
- **Still open:** `clk27_d` on fabric; `xm2-01.v` clocks the PPU timer
  from `timer_clk_4`, a mux of counter bits (the beeper divider was
  re-clocked on 2 Sep 2026); `audio.v` clocks the I2S FIFO read from
  `isread_aud`.  Slow, inside the PPU domain, not on the boot path.

Resource use after the change: Logic 44%, Register 25%, BSRAM 48%, 0
setup violations.  **Not run on a board.**

### 5. `clk_6_25` goes nowhere - REMOVED

`sdram2`'s `cpu_clk` (6.27 MHz) was brought out to a wire in `top.v` that
nothing read.  The CPU runs on the PLL's `clk4` (4.18 MHz) instead.  If
the intent was to run the CPU at twice the PPU rate off one counter, that
is not what happens, and as of Sep 2026 the port and the wire are gone, so
it is a decision to take rather than a loose end.

### 6. The MCU link was not wired like MiSTeryNano's - CHANGED

Not a defect, a deliberate divergence, and now undone.  Alexey had the
five SPI signals on FPGA pins 71-75; upstream puts them on `m0s[4:0]` =
42/41/56/54/51, and every MiSTeryNano diagram, every MiSTeryShield20k
carrier and every third-party build assumes upstream's.  The MCU side was
never the divergence - `mnano/spi.c` is byte-identical to upstream's, GPIO
12/13/10/11/14 - so this was a change to `test003.cst` and `top.v` only,
and the firmware binary in `bin/` is unaffected.

`top.v` also gained upstream's dual-MCU arrangement - `spi_dir`/`spi_dat`/
`spi_csn`/`spi_sclk`/`spi_irqn` on 75/76/86/13/69 to the Tang's own
on-board BL616, with a flop `spi_ext` selecting the inputs - **and lost it
again the same afternoon.**  `spi_irqn` wants pin 69, and 69 is the FPGA's
TX into that same BL616, which is what puts the VP-65 console on the USB-C
plug.  The internal path had never been run on hardware here, needs
assembly 3921 or later, and costs the USB-JTAG bridge as well once the chip
is actually flashed; the console is worth more than all of that.  So the
five ports, the five `IO_LOC` lines and the `spi_ext` flop are gone, the
dock is the only attachment, and there is no mux to settle - `main.c`'s
retry loop now has nothing to absorb.  `git show 36e8c2b` has the removed
form if it is ever wanted back.

The cost is that upstream's 51/54/56 are where this core's I²S was, and 55
is upstream's `bl616_mon_rx`:

```
                before                 now
MCU link        71 72 73 74 75         42 41 56 54 51
audio I2S       56 55 54 51            71 72 73 74
serial          69 out  70 in          69 out  70 in   (unchanged)
```

Audio swapped onto the pins the link vacated. The serial port went to
upstream's 48/55 for a few hours, because upstream spends 69 on
`spi_irqn`, and came back to 69/70 the moment the internal BL616 link was
dropped - so **VP-65 is on the USB-C serial port exactly as it always
was**.  48 and 55 are free and are where to put it if 69 is ever wanted
for the interrupt again.

Checked: lint clean; `make sim` output bit-identical to the same run
before the change, including the one read-after-write mismatch, which is
defect-free evidence that nothing but placement moved; `make bitstream`
places every pin as constrained, 0 setup violations.  **Not checked on
hardware, and this is the one change in this file that can be wrong in a
way no simulation will show** - it is entirely about which pad a signal
comes out of.  The internal-BL616 half has never been exercised at all.

`src/test003_lcd.cst`, which carried the old five-pin MCU block and named
ports that no longer existed, was removed in Sep 2026.

### 7. HDMI carried no sound - ADDED

Gowin's `DVI_TX` IP is what its name says.  It is DVI: video only, no data
islands, and therefore no audio - its own documentation offers exactly two
options, external clock and OBUF type.  There is no Gowin HDMI IP with
audio in the Education install either.  So the machine's sound only ever
left by the I²S pins, and getting it down the HDMI cable meant replacing
the IP.

`src/hdmi/` is that replacement, four files:

```
hdmi_tx.v       timing, packet scheduling, audio capture, packet picker
tmds_channel.v  8b/10b, control words, TERC4, both guard bands
hdmi_packet.v   the 32-clock packet and its BCH ECC
hdmi_serdes.v   rPLL x5, four OSER10, four ELVDS_OBUF
```

The two coding files are transcriptions of HDMI 1.4a 5.4 and 5.2.3.4,
derived from hdl-util/hdmi (MIT) and rewritten in Verilog-2001; the rest
is ours, because upstream's top level makes its own video timing and
`sdram2.v` already does that here.  Four packet types go out - audio clock
regeneration, audio sample, audio InfoFrame, AVI InfoFrame - four packets
a line, in the back porch, on blanking lines as well as active ones.
`.claude/docs/fpga.md` has the design; the three things to know are the
delay line, the back-porch assumption and the `clkpix/1024` resampling.

The I²S output is untouched and still runs at its own rate.

What was checked, and it is more than usual, because a bad encoder would
show up as no picture at all:

- `make lint` clean.
- **The testbench now decodes the TMDS stream**, the way a sink does:
  follow the preambles and guard bands into a video or data island period
  and decode what is inside.  So `make frames` no longer taps the RGB
  signals - it reconstructs the picture out of the encoder's own output,
  and it still reads `СТАРТОВЫЙ ТЕСТ / - ошибка ОЗУ ЦП` at 1280x600.  That
  is a round trip through the 8b/10b, not an inspection of its input.
- Over a 1.4 s run: 177876 packets, **0 ECC errors**, 69482 audio samples,
  no overflow of the sample buffer.  With `+AUDIOTEST` forcing two
  different constants onto the AY mix, 2976 of 2995 audio samples came
  back non-zero with L != R - the same answer the I²S monitor gives, from
  the other output.
- `make bitstream` places it: 0 setup violations, and the tool derives the
  serial clock on its own as a generated 250.715 MHz off the pixel clock,
  which is what makes the OSER10s analysable at all.  Nothing under
  `src/hdmi/` appears in the ten worst timing paths.

That paragraph used to end "no display has ever been asked to play this".
One has now, and it found two bugs that none of the above could - see
defects 8 and 9.  The ECC check in the testbench still uses the same
polynomial constant as the encoder, so it proves the plumbing and not the
polynomial.  A General Control Packet **is** now sent, asserting neither
mute flag; the AVI InfoFrame still carries VIC 0, and at least one
television plays audio on that mode regardless.

### 8. The HDMI audio rate was 2% off standard - FIXED

`hdmi_tx.v` took a sample every 1024 pixel clocks.  At 50.143 MHz that is
**48.968 kHz**, while the IEC 60958 channel status beside it declared a
flat **48 kHz**.  A sink clocks its converter from one and its buffer from
the other, and 960 samples a second of disagreement drains or floods a
receiver FIFO of a few hundred samples in about half a second.

Heard on the board as: keypress clicks getting through, music playing for
half a second and stopping, and continuous music never playing at all -
because a stream with no pauses in it never gives the sink a reason to
re-arm.  The shape of that symptom is what identified it; nothing in the
design or the simulation was wrong in a way either could show.

No integer divider of 50.143 MHz lands on a standard rate - 48 kHz needs
1044.58 - so the sample instant now comes from a phase accumulator: add N
every pixel clock, take a sample and subtract at 128 x CTS.  **N = 6144,
CTS = 50140** makes the ratio exactly N/(128 x CTS) by construction, so
what the sink regenerates and what we deliver agree to the bit whatever
`f_TMDS` really is - and it is a PLL output nobody has measured.

Checked in simulation (9746 samples over 6363 lines, 203.0 ms = 48,010 Hz,
0 ECC errors, 0 bad parity) and then on the board: the diagnostic monitor's
`hdmipkt` counter went from +4883 per 100 ms window to +4787, a ratio of
0.9803 against the predicted 48000/48960 = 0.9804.

### 9. The mixer's output was combinational and sampled asynchronously - FIXED

`volume_data_l/r` were an `always @(*)`, and `hdmi_tx` latches them at the
audio sample instant - an instant with no relation to the PPU clock the
mixer runs on.  So the encoder could take the value while the adders were
still settling and put a carry-chain intermediate on the wire as a sample.

It was **consistent rather than intermittent**, which is what made it look
like a dead path rather than noise: the old divider took a sample every
1024 pixel clocks and `ppuclk_p` is `clkram/16`, and 1024 = 64 x 16, so the
sample instant sat at one fixed phase of the PPU clock forever.  Land that
phase in the settling window and every sample is wrong, every time.

Registering the output on `posedge ppuclk_p` makes the sample a settled
value by construction, at 320 ns of latency and sixteen flip-flops.

**The diagnostic monitor could not see this**, and that is the part worth
remembering.  Its probes sampled `volume_data_l` on `posedge ppuclk_p` too,
so they reported a clean waveform while the encoder was being fed spikes.
Third time in this repository that an instrument shared the design's
assumption and both were wrong together, after the SDRAM model and the
audio subframe layout.  When the board and the probe disagree, suspect the
probe earlier than I did - it took three build cycles.

### 10. The DC blocker is out of the signal path - EXPLAINED BY 11

The offset it was written for is real: measured on the board, one AY chip's
music sits on **+3000 of DC** with the blocker bypassed.  But every
DC-blocked form of the signal was silent on the operator's television and
the raw unipolar sum was not, and on 31 Aug 2026 the blocker and its S2
bypass were removed with the cause written up as unknown.  The cause is
defect 11: every silent form set sample bit 15 or 14, and the encoder was
sending those bits where the sink reads its flags.  The raw sum stays for
one build so that the layout fix is the only change; then the blocker
(`git show f2bb44b^`) should return, beeper level and all.

### 11. The audio subpacket was packed as two subframes - FIXED, NOT HEARD

`hdmi_tx.v`, `as_sub0`.  HDMI 1.4b table 5-12 lays an audio sample
subpacket out as the two 24-bit samples adjacent, left in bytes 0-2, right
in 3-5, and all eight flags in byte 6 as `{PR,CR,UR,VR,PL,CL,UL,VL}`.
hdl-util/hdmi's `audio_sample_packet.sv`, which this encoder is derived
from and which plays on real sinks, builds exactly that word.  On 30 Aug
2026 the word was changed to two 28-bit IEC 60958 subframes end to end -
`{P,C,U,V,sample}` twice - and `CLAUDE.md` gained a trap defending it.

On a sink reading the spec layout, that stream is:

```
sink reads          gets                          meaning
L    bits 23:0      samp_l                        correct
R    bits 47:24     {samp_r[19:0], PL, CL, 0, 0}  right sample x16, wraps past 4096
VL   bit 48         samp_r[20] = sample bit 12
UL   bit 49         samp_r[21] = sample bit 13
CL   bit 50         samp_r[22] = sample bit 14    channel status corrupted when set
PL   bit 51         samp_r[23] = sample bit 15    the sign
```

Left and right carry the same mono word, so the left channel's channel
status bit is sample bit 14 and its parity bit is the sign.  A negative
sample has both set; a sample of 16384 or more has bit 14.  Either writes
a 1 into the 192-bit channel status block the sink is assembling, and a
block with the wrong bit set means non-PCM, a different rate or a
different format - the sink mutes.  That explains, one symptom each:

- the raw sum plays: never negative, and under two chips never 16384;
- minus 512, DC-blocked, DC-blocked-plus-offset: negative or over the
  line at some point, silent (defect 10's whole table);
- the beeper at 16384 mutes, at 8192 plays: bit 14 against bit 13;
- **three AY chips playing at once mute where one or two play**: peaks of
  18360 against 6120 and 12240.  This is the report that found it.

The right channel would also have been sixteen times too loud and
wrapping, which the earlier "right channel is white noise" observation
may have been - that observation was what motivated the change, and it
was made before the combinational mixer (defect 9) was found, so it had
more than one candidate.

Reverted to table 5-12 on 1 Sep 2026.  `sim/tb/tb_top.v` decoded with the
same wrong layout and had reported "stereo, 0 bad parity" throughout; it
now decodes the spec layout and checks P and V there.  Lint clean;
simulation with `+AUDIOTEST` decodes stereo samples with 0 bad parity and
0 flagged invalid through the new decoder.  **Not heard on a board.**  The
expected result is three chips and the beeper at any level, both channels
at the same level, and no reason left for the unipolar sum - which is why
the blocker should be the next build, not this one.

### 12. Every AY tone was an octave low - FIXED, HEARD

`aberrant.v` tied the three cores' `SEL` pins high.  In `ym2149.sv` the
prescaler reloads with `{SEL, 3'b111}`: `SEL=0` divides the clock enable
by 8, which is what the chip does (tone = fclk / (16 x TP)), and `SEL=1`
by 16, for a core fed at twice the chip clock - the MiSTer ZX Spectrum
feeds it a 3.5 MHz enable for a 1.7734 MHz chip.  Here the enable is the
chip clock itself, 1.7734 MHz, so every tone counter ran at half rate and
so did the envelope generator.  Measured in `tb_aberrant`: period 252
gave 220 Hz with `SEL=1` and 440 Hz with `SEL=0`; an envelope of period
1000 gave 3.5 Hz against the chip's 6.9 Hz.

That is the "bass sounds filtered out" report of 2 Sep 2026.  PT3 bass
sits at C2-C3, 65-130 Hz; an octave down it is 33-65 Hz, which a
television's speaker does not reproduce, while the melody an octave down
still sounds like music.  Nothing in the HDMI path filters anything: the
encoder takes the mixer word as it is, the resampler is a sample-and-hold
and the DC blocker is not in the path.  The only frequency-shaping
element in the whole chain was the AY divider.

The same pin explains the earlier reading in this file that the chips
free-ran "1.77 times too fast" before the phase accumulator: with `CE`
tied high at 3.1339 MHz and `SEL=1` the effective clock was 1.567 MHz,
12% flat, not 77% sharp.  The accumulator was still the right change, it
just was not the last one.

Fixed 2 Sep 2026: `SEL` low on all three instances.  `tb_aberrant` now
counts the output edges over a simulated second and fails outside 2% of
880, so a wrong prescaler cannot get past `make ab-test` again.  Lint
clean, bitstream builds.  **Heard on the board, 2 Sep 2026**: the
operator reports the AYs playing, after the bass had been reported as
"filtered out" on the octave-low build.  Defect 10's blocker is still the next
change after this one is heard.

### 13. The start screen appears on only some power cycles - FIXED, HEARD

Reported 2 Sep 2026: from a power cycle the machine sometimes does not
reach its start screen, and needed three power cycles once; when it does
reach it, floppies load and the AYs play.  Nothing in the design is
random, so the cause has to be a state that is fixed for a power cycle
and re-rolled by the next one.  Three were found, all on the FPGA side;
the MCU's handshake was read and is not one (it polls for 5 s, the
FPGA's `sysctrl` does not answer while in its 335 ms reset, and the 'R'
write cannot land on an uninitialised memory).

1. **SDRAM initialised 5.7 us after PLL lock, no refresh cycles.**
   `sdram2.v`'s reset counter stepped per 16 clkram cycles, not per
   "clkref" as its MiST-derived comment assumed, so the "1 ms" was 10 us,
   and the sequence was PRECHARGE, NOPs, LOAD MODE with no AUTO REFRESH.
   A mode load the chip ignores is a power cycle of bad memory: the PPU
   draws into SDRAM, so no screen, or garbage.  Fixed: 1.3 ms settle
   after lock, two refreshes before the mode load.
2. **The HDMI PLL took a PLL output as reference with no reset.**  Where
   a PLL acquiring on a reference that is itself acquiring ends up is
   not guaranteed; Gowin's guide asks for RESET released after the input
   is stable.  Fixed: reset from `sys_rpll`'s LOCK, and the OSER10s from
   the serial PLL's.  This case would look like *no signal* at the
   monitor rather than a blank picture.
3. **The PPU ran from configuration.**  Its reset was the MCU's 'R' bit,
   0 from power-on, so it executed its boot ROM before the PLL locked
   and hit SDRAM before init, with the 1801's bus timeout deciding what
   happened next - possibly the trap-loop the simulation used to show.
   The MCU's reset a third of a second later cleaned it up in the cases
   that worked.  Fixed: `pp_rst` includes `~init`.

4. **`init` read as done from configuration.**  `sdram2.v`'s reset
   counter had no initial value, so it was 0 - which is `init` - from
   configuration until the first clkram edge, however long the PLL took
   to give one.  `count_rst` in `top.v` keys off `init`, and so does the
   PPU's reset now; the simulation found this because its fastboot
   shortcut waited for `init` and fired at time zero.  Fixed: the counter
   initialises to 31.

`sim/tb/tb_top.v`'s fastboot shortcut now waits for `init` before
forcing the reset counter, since the counter is held at zero until then.

**Board result, 2 Sep 2026, build of 09:22 (items 1-4 above, old
SDC):** the machine now fails *every* power cycle, SD card in or out:
black screen with a blinking cursor, key presses beep, no start screen.
The beeps prove the MCU handshake and its reset landed (the beeper is
behind the volume control, which is mute until the MCU sets it), so the
PPU is running a clean second boot on initialised memory and the CPU is
not being heard.  The previous build (09:02, floppy re-clocking) reached
the screen.

The simulation was tried as a witness and turned out to be an unreliable
one.  The tree draws a blue field with a cursor at 1.2 s where the
previous revision draws the start-test text; a three-way bisect passed
with the PPU hold reverted alone AND with the SDRAM settle reverted
alone, and failed with only the counter's initial value reverted - i.e.
the two together, "the PPU starts at 1.3 ms".  PPU bus traces to 1.1 s
then showed both builds identical to the instruction until 1.038 s, when
the PPU begins reading the CPU's bytes off the channel (`177060`) and
the *SDRAM model* hands it wrong words from its own RAM at `002000` and
`007414`-`007420`; the failing build halts the CPU on them, the passing
build got one bad read and survived.  That is the model's documented
burst-interleaving flaw striking or missing by timing, not a property of
the design, so the sim's pass/fail on these variants means nothing.

What is left is the board: two builds of the same logic, one works, one
does not, and the difference is placement.  The one path placement can
break that fits "PPU waits for the CPU and never hears it" is the CPU's
bus into `vp1_120`, clk4 into clk_25 with coincident edges, which no
build until 09:51 had analysed (defect 4).  The 09:51 build related the
clocks and **reached the start screen every time** - so it was the
crossing - but hung loading a floppy, because that build's clock phase
was wrong by one clkram period (defect 4, "the phase has to be right")
and the floppy status path into the PPU had gone unoptimised.  The
10:22 build corrects the phase, and **the operator confirms it on the
board: start screen, floppy load and AY playback all work.**  The PPU
hold (item 3) stays in.

So the whole of the day's board evidence, in order: the intermittent
start screen was one or more of items 1-4 plus the unanalysed
CPU-to-channel crossing; the 09:22 build (items 1-4, old SDC) failed
every time on that crossing's new placement; the 09:51 build (clocks
related) reached the screen every time and hung the floppy on the wrong
phase; the 10:22 build (phase right) does everything.  What made the
difference is not any one RTL change but that the crossings between the
processors and the clk_25 peripherals are now analysed with the right
edges, so a placement can no longer roll them.

### 14. IDE hard disk cartridge - ADDED, WORKS ON THE BOARD

2 Sep 2026.  `src/ide/ide.v` and `ide_rom.v`: Oleg H.'s IDE controller
for the УКНЦ in ROM cartridge slot 1, with its WD boot ROM
(`tang/rom/ide_wdromv0110.bin`, 24 KB in three banks), implemented from
UKNCBTL's emulation of it; `.claude/docs/platform.md` has the map, the
inversions and the geometry rules.  The disk is SD slot 4, mounted from
the OSD's new "HDD 0:" entry (`*.img`), saved with the other images by
the existing settings code; `sdc.c` reads the image's first sector at
mount and sends sectors/track, heads and the inversion flag as SYS
values `'S'`, `'H'`, `'I'`.  `sd_card.v` grew from four slots to five,
`fdd4.v` yields the SD path while the cartridge's request is up, and
`ppu.v` exports its window state and no longer writes RAM through the
window in cartridge mode.

Verified: `make ide-test` (bus in, stand-in card out: ROM banks, status
after reset, IDENTIFY, a two-sector CHS read at the right LBAs with the
right words and byte order, the inverted-image case, a sector write
arriving in order, SET CONFIG changing the LBA arithmetic); `make lint`;
`make sim` boots as before (the cartridge is absent without a mounted
image) and draws the start screen at 1.2 s; `make bitstream` passes the
timing gate with 0 setup and 0 hold violations at logic 47%, registers
26%, BSRAM 64%; `make fw` builds and is in `bin/bl616.bin`.
**On the board, 2 Sep 2026, first try:** everything up to the boot
works - the cartridge appears, the WD ROM runs from the start menu,
reads its boot sector - and the ROM then refuses the sector as wrong.
That is a data-form symptom: bytes inverted the wrong way, or (ruled
out from Gowin's BSRAM guide: a byte port addresses the same 14-bit
space as a word port, so byte 0 is word 0's low half, as the design and
the sim model assume) swapped.  The inversion chain matches UKNCBTL
line for line, so the suspect is the sector-0 heuristic against this
particular image.  Added the OSD override "HDD image: Auto|Plain|
Inverted" (`'J'` -> `system_hdd_mode` -> `ide.v`) so the board can say
which.  **Second try:** only Plain gets past the home block, and the
boot sector is still refused - so the data form is right and the home
block (block 0, sector 1) reads correctly, and what the ROM rejects is
block 1, the WD layout's boot block, which the cartridge reads as sector
2 of the same track and cannot misplace whatever the geometry.  Reading
`rt11dsk` (ukncbtl-utils) settled what `hi` does - a complement of every
byte, nothing more - and showed three incompatible layouts, WD, HD and
HZ, of which only WD has its boot block at block 1.  The likely truth is
that the image is not a WD-layout image with a system on partition 0.
Awaiting the image's origin and its first bytes.  A real bug found on
the way and fixed: `next_sector` compared the head in 4 bits, so a
16-head geometry wrapped the head after every sector; `tb_ide` now
covers it.

**Third try, with the image in hand** (`build/WDC170inv_P.img`, plain
despite the name: 34 sectors, 10 heads, 980 cylinders, block 1 starting
with `000240`) and a note from someone who did it on real hardware
(`build/clue.txt`): the boot succeeds only when the home block's
geometry bytes match what the drive reports - so **the WD ROM reads
IDENTIFY**.  Ours handed it garbage: Hard.cpp inverts its identify
buffer and then applies the image's inversion rule, which comes out
plain only for an inverted image - the form everyone uses on hardware
and in the emulator - and a plain image gets `~identify`; on top of
that we reported 0 cylinders.  Fixed: IDENTIFY is plain on the bus
whatever the image form (`identify ^ inv` into the buffer), and the MCU
sends cylinders as `'C'`/`'Y'`.

**Fourth try, with WDINIT's own code:** its identify loop
(`007702: MOV #177423,(R4)`, then `MOV (R5),R0; COM R0` per word)
complements what it reads, and its sector loop does not - so the bus
carries `~identify` on real hardware and the third try had it backwards;
the tool's "Cylinders: 64555, Heads: 65525, Sectors: 65501" are the
complements of 980, 10 and 34, which is the plain-identify build seen
through that `COM`.  Back to `~identify` on the bus for either image
form, with the real cylinder count kept; `tb_ide` checks `~045a`,
`~980`, `~UK`.  WDINIT's "heads<>16, sectors<>63 not supported" is the
tool's own limit for initialising CF cards and does not concern
booting.  Also added: "HDD prot." (`'K'`), since a booted RT-11 writes
to its disk (one word at block 108 changed on the card in the first
session) and the card should be keepable pristine.

**Fifth try, with an empty 16x63 image (`build/wd16x63.img`):** WDINIT
showed the right geometry and failed its first write - "WD write (track
sector): 000000 000001", then "read and compare error".  The image came
back with block 0 untouched and a valid home block, checksum and all,
in **block 21**: the floppy controller's sector number for track 1
sector 1, which RT-11 was reading off the floppy while the tool wrote.
The two requesters were muxed onto `sd_card.v` by "who is pending" and
could both be visible to it for a cycle or two, and the MCU picks the
drive from a one-hot mask.  Fixed with `ide/sd_arbiter.v`: one owner at
a time, granted when the cartridge asks with no floppy request up and
the card idle, held until done, every mux keyed on the owner, the
floppies masked and held back meanwhile; `make sdarb-test` drives the
same-cycle case.  Also: a new READ or WRITE command clears the ERROR
bit, as on a drive (the tool checks it right after the command).
**Sixth try, 2 Sep 2026: "all works now"** - WDINIT initialises the
empty 16x63 image, RT-11 goes onto WD0: and boots from the cartridge.
The whole chain, for the record: the cartridge in slot 1 with the WD
ROM in three banks; registers indexed by the inverted address, every
bus word inverted, sector data inverted once more for a raw-dump image;
IDENTIFY complemented on the bus with the real geometry; CHS to LBA in
the cartridge; five SD slots with an arbiter between the floppies and
the disk; the OSD's HDD 0:, HDD image (Auto/Plain/Inverted) and HDD
prot. entries, saved with the settings.  Still open: no bounds check on
CHS; slot 2 is empty and not selectable; byte writes with only the odd
byte selected are ignored; whether the original WD image
(`build/WDC170inv_P.img`) boots now that identify is right has not been
retried.

### 15. Shift plus a same-row key typed the key forever - FIXED, WORKS ON THE BOARD

Reported 2 Sep 2026: RShift + the PC `'` key (the one with Э on it)
printed `,` and kept printing it until another RShift press and
release.  Three things stacked:

1. **`uknc.h` mapped `'` to 05**, which is not the Э key (0155) but the
   numeric keypad's comma - hence the `,`.  UKNCBTL's `qkeyboardview.cpp`
   is the layout; the table also had right Alt on 0172 (ПОМ) with a
   comment saying ГРАФ (066).
2. **The machine's keyboard is a scanned matrix and the ROM counts
   rows, not keys.**  A press is reported once per row, the release is
   `0200 | row` once the row is empty, and the ROM's autorepeat runs
   until releases balance presses.  Shift (0105) and the keypad share
   row 5.  The MCU forwarded every USB event, so Shift+`'` was two
   presses in row 5; `hid.v` truncates a release to its row, so both
   releases were 0205.
3. **`xm2-01.v` latches `but_data` only when it changes**, so the second
   0205 never happened.  Two presses, one release: the ROM repeated.

Reproduced against the real ROM in the headless UKNCBTL (see
`.claude/docs/mcu.md`, "Testing a key sequence without a board"), at an
RT-11 prompt, five seconds after each stream:

```
0105 005 0205           the board's stream       a line of ,,,,, and on
0105 005 0205 0205      with the lost release    one , and stop
Shift + keypad-comma    through the real matrix  nothing typed at all
0105 025 0205           Shift + PC minus         a line of ///// and on
0105 0155 0215 0205     the fixed stream, Shift+Э   what the matrix does
0105 0175 0215 0205     the fixed stream, Shift+-   =
```

The fix is in `usb_host.c`: `kbd_tx_uknc()` tracks which HID keys it
has forwarded and how many are down per row, and sends only the row's
first press and last release; presses eaten by the OSD or mapped to
`MISS` are not tracked, so their releases are dropped rather than sent
for a row the core never saw.  `'` → 0155, PC `-` → 0175 (the `- =`
key, row 13, so Shift+`-` is `=` rather than nothing), right Alt → 066.
The firmware's own function was compiled on the host to produce the
streams that were then replayed, so the emulator saw the code that
ships.  No FPGA change; `hid.v`'s truncation is now a no-op on what it
receives.  The board confirmed the repeat gone the same afternoon.

Second round the same day, after the board confirmed the repeat gone:
Backspace "printed something instead of deleting".  Two findings.  The
faithful matrix rule swallows the next key down in a held row, and
Backspace shares row 10 with A, K, M and 3 - a PC typist rolls into it
from those constantly, and the real keyboard's users never could.  The
filter now sends rollover inside a row as a release of the row and a new
press, forgetting the row's older keys; Shift held twice is one code and
releases when the second is up.  And `build/moutst.dsk` does `SET TT
NOSCOPE` at startup, in which RT-11 echoes a rubout as `\` plus the
deleted characters: that is what the emulator shows for a Backspace
through UKNCBTL's own matrix too, so it is RT-11's hardcopy echo and
`SET TT SCOPE` at the prompt is the cure, not the firmware.  Verified in
the emulator with the shipped function: A then Backspace rolled in
either order, K rolled into A, both Shifts either order then `1` giving
`!`, releases under the OSD - all as expected.

`xm2-01.v` has a queue now (same day): `but_data` is change-detected on
every clock, up to seven bytes wait, and `R177702` is loaded only after
the PPU has read the previous one, which is the real controller's ready
handshake.  `make kbd-test` (`sim/tb/tb_kbd.v`) sends bursts 1.5 us
apart against a PPU polling every 40 or 400 us and checks every byte out
in order; the firmware also spaces its bytes 2 ms apart for a board
still on the older bitstream.  Builds, lints, passes the gate with 0
setup and 0 hold violations, and the resource line did not move
(47% / 26% / 64%).  Both flashed on 2 Sep 2026 and confirmed at the
keyboard: chords, rolled Backspace, no repeat - "all works".

### 16. Covox at 0177372 - ADDED, NOT HEARD

Asked for on 2 Sep 2026: the "new covox" that blairecas/badapple probes
for ("LPT port A 177100 or new covox 177372 if detected"), mixed into
the HDMI audio.  It is the ЦАП of the Aberrant sound module's map, on the
module's expansion connector.  No data sheet turned up - not in
badapple (the repo holds the CPU loader, the PPU side is in the released
image only), not in nzeemin's UKNCBTL (whose Covox, release 2025.1, is
on the PPU printer port `0177100`, inverted), not on the forums - so the
interface was read out of the players: spcplay's PPU loop writes the
sample as the low byte of a `MOV` to the port, and every UKNC device is
detected with a `TST` under a trap-4 handler.

`tang/src/covox.v`: one register on the PPU clock at `0177372`, reads
acknowledged and returning the sample, word and byte writes both taken
(`0177373` as the odd byte), unsigned and uninverted.  `top.v` adds it
to the ack OR and the data mux after the Aberrant, and to the mixer
shifted up five (0..8160), where `clip()` now has a real corner to
saturate (34712 with everything at full).  `make covox-test` checks the
writes, the read-back and that the Covox and the Aberrant never
acknowledge the same address across `0177360`-`0177376`.  Lint clean.
`.claude/docs/platform.md` has the interface.  Not implemented: the
printer-port Covox at `0177100`, which players fall back to when this
one is absent - it is not, now.

### 17. Bad Apple from the hard disk - LBA28, READ-AHEAD AND A READ STALL, PLAYS ON THE BOARD

2 Sep 2026, with `build/bappwd.img` (blairecas/badapple's WD image,
inverted, 63 sectors x 16 heads, booted from the cartridge with menu
option 2): coloured vertical stripes instead of the demo and no sound.

**Stripes: LBA28.**  The readme's own words settled it: the emulator
the demo ships is UKNCBTL with "LBA28 support for IDE emulation" and
shorter DRQ timeouts, and block 2 of the image writes `0340` to the
head register before every read - LBA mode.  `ide.v` followed the stock
Hard.cpp, which ignores bit 6 and computes CHS from the LBA bytes, so
every video sector came from the wrong place.  Confirmed in the
emulator first: the stock `Hard.cpp` boots the image to nothing, and
with `CalculateOffset()`/`NextSector()` given an LBA28 branch the
silhouettes play (a scratchpad copy of the headless UKNCBTL from
`../mc0511-dicewars`, with `--cart` and `--hdd` added).  `ide.v`:
`curheadreg[6]` selects `{head[3:0], cyl, sector}` as the SD sector
straight, and `next_sector` counts the 28-bit number up into the
registers; `tb_ide` has the two-sector LBA read, the carry into the
cylinder high byte, bit 24 from the head nibble, and CHS after LBA.
On the board: the demo plays, with sound "quite different".

**The sound: sector latency, not the DAC.**  The PPU loop (disassembled
in the emulator at 001400-001672) pulls the whole show out of the IDE
data register: `MOV (R5),(R3)` for a sound word straight to the Covox
and `MOV (R5),@0(R5)` pairs for screen words, 52 samples and 102 pairs
per sector, `BIT #10,(R4)` polling DRQ between sectors.  So the sample
rate IS the rate at which sectors arrive: with near-instant sectors the
emulator logs 1065 Covox writes a frame (26.6 kHz), with UKNCBTL's
stock 1 ms per sector 698 (17.5 kHz), and every wait for a sector is a
hole in the audio - which is why the author shortened those timeouts.
The samples are plain unsigned bytes in the low byte of the word, high
byte zero, mean 128, so the DAC's form and level were right.  The
cartridge fetched the next sector only after the PPU had drained the
current one, so each of ~500 sectors a second cost a full card read of
silence, 0.4-1 ms against 2 ms of audio.

`ide.v` now **reads ahead**: a second sector bank (one more BSRAM), and
the next sector of a multi-sector read is fetched while the current one
is drained.  A READ arriving while a read-ahead is in flight discards
that result and fetches its own; a WRITE whose buffer fills meanwhile
waits for the engine; `tb_ide` checks the second sector is fetched
before a word of the first is drained, the third only once a bank is
free, DRQ without BUSY across the drain, data in order, and the discard
case.  Two WAVs from the emulator with the port logged - stock delay and
none - went to the operator as the reference.  Heard: it plays.

**Then 24 kHz exactly.**  With instant sectors the loop runs at 26.6
kHz where the author's hardware gave "~24 kHz", so the cartridge holds
each sector: not handed over sooner than N x 25 us after the previous
one was drained (`hold_units`/`hold_tick`, counted from the drain, so
the card's own time sits inside the gap).  N is the OSD's "HDD delay"
(`'D'`, `system_hdd_delay`, 0-375 us), default 9 = 225 us: 40 ms /
(960 / 52) - 1.953 ms = 214 us, and the emulator given a 225 us gap
logs 959.6 writes a frame, 24.0 kHz.  Our PPU's speed against the
emulator's is the one unknown, which is why it is a setting.  `tb_ide`
checks the hold.  Built, flashed, heard - and heard as "the highs
lowered, bassy" on the voice: 52 samples at the full 26.6 kHz and
then a 214 us hold is amplitude modulation at 461 Hz, and the pitch
stays 11% sharp.  The emulator's Covox stream measured against the
operator's reference recording has no shortage of highs (relative to
300-1000 Hz it holds 10 dB more above 4 kHz than the recording, which
rolls off itself), and the HDMI path has no filter, so the hold was
the culprit.

**Replaced by a per-read stall.**  Every read of the data register is
acknowledged `hdd_delay` x 0.3125 PPU cycles late on average, a phase
accumulator in 1/64 cycle carrying the fraction from read to read
(`stall_acc`/`stall_cnt` in `ide.v`; the bus sees ack on its own
clock, clk_25/8, so stalls go out in whole PPU cycles and the fraction
dithers).  256 reads a sector, so the loop slows uniformly by
`hdd_delay` x 25.6 us a sector, no gap anywhere; 8, the default, is
205 us: 1.953 + 0.205 = 2.158 ms a sector, 24.1 kHz.  The OSD entry
runs 0-975 us in 25 us steps (40 entries, `'D'` six bits).  `tb_ide`:
with delay 8, 256 data reads take 5120 clk_25 more than with 0, the
data intact, and the sector completes.  **On the board: right at 750
us**, not 205 - so our PPU runs this loop a good deal faster than the
emulator's model, and 750 (index 30) is the default now on both
sides.  The menu shows microseconds; "index 8, 9" in the earlier notes
are that number divided by 25.  The voice is fine at 750.

### 18. Kakave+ mouse and real-time clock - ADDED, NOT ON A BOARD

2 Sep 2026.  The mouse/RTC half of yrust's Kakave+ cartridge (the IDE
half is item 14), from the files in `build/rtc_kkve/`: the ATmega sketch
is the protocol, the RT-11 programs KKVTST/KKVRTC/KKVDTS are how it is
used, and the Quartus archive (a zlib container with a name header per
entry; `build/rtc_kkve/x/qar.py` unpacks it) only confirmed that the
CPLD is a plain decoder.  `kakave.v` on the PPU bus at `0177400` and
`0177410`, `.claude/docs/platform.md` has the register description.

What was decided and why:

- **The mouse is the USB one.**  `usb_host.c` already sends every report
  over SPI; `hid.v` now exports one report with a toggle and `kakave.v`
  accumulates it on the PPU clock, clipped to ±63 as the sketch clips.
  Y is negated: PS/2 counts up, USB counts down, and KKVTST subtracts.
  A first version negated in eight bits and -128 stayed -128; the
  testbench caught it, so the negation is nine bits wide.
- **The clock counts in the FPGA.**  No battery, no time source on the
  BL616, so the calendar is a counter on the PPU clock with an exact
  second (7 s = 21937500 cycles, a phase accumulator), set by the
  machine through the cartridge protocol or by the OSD's new Clock form
  whose values are saved with the settings and re-sent at power-up.
  The reset lines do not touch it.
- **Weekday 1 = Sunday**, the library's convention, not the RT-11
  programs' printout; documented in `platform.md`.
- **'M' from the MCU** says whether a mouse is attached, so KKVTST's
  "who are you" gets `00AA` only when there is one.

Checked: `make lint`, `make kakave-test` (decode over the whole I/O
page, motion, buttons, clipping, commands, set/read, leap and year
rollover, weekday, the exact second, the OSD path, reset), `make fw`
builds, `make bitstream` builds and meets the timing gate.  Not checked:
a board, and any real software beyond reading the three RT-11 sources -
the emulator next door has no Kakave.  The decode was also walked in
python over `0177000`-`0177777` against every PPU-bus decode in the
tree: nothing else answers these two words.

### 19. "ЗАВИСАНИЕ ПРИ ПРИЕМЕ А.В.П." - a vector fetch nobody answered, then one answered twice - FIXED, MKLAD RUNS ON THE BOARD

3 Sep 2026.  A game (MKLAD, 1991) started from RT-11 crashed at once
on the board, and the same disk rebooted later gave the ROM's
`ЗАВИСАНИЕ ПРИ ПРИЕМЕ А.В.П.` - which is not the floppy message it was
taken for on 2 Sep but the PPU's halt text for a **bus timeout while
receiving the interrupt vector address**: an interrupt was taken and
the vector-fetch cycle got no acknowledge.  It ran once and then not,
which is the CPU and PPU racing.

The cause is in the vector chain.  `top.v` runs the PPU's fetch strobe
through `xm2-01.v` (timer 304, key 300) and on to `vp1_120.v` (the
channels); a chip must let the strobe pass unless it is the one with
an enabled request.  `xm2-01.v` stopped it on `setVIRQtm|setVIRQbt` -
"set" alone - while it acknowledges only on set AND enabled, and a
timer or key request is set-but-disabled from the moment its vector is
taken until the handler reads `177714` or `177702`.  A channel
interrupt taken in that window - the CPU's byte arriving while the
PPU is in the first instructions of its timer handler - reached
nobody.  `vp1_120.v` gated its own chain outputs the same way (and
drove the PPU one to 1), which would starve `vp65` on the CPU side in
the same fashion.  Both gates are the VIRQ condition now.

`sim/tb/tb_virq.v` (`make virq-test`) wires the two chips as `top.v`
does and takes four vectors: timer, channel 0 with the timer flag
still up, key, channel 1 with the key unread.  Against the previous
RTL the two channel fetches time out; against this they answer 320
and 330.  Lint clean, bitstream built, timing gate passed, resources
unchanged, flashed to the Tang.  **On the board the halt was gone**
and the game drew part of its first tile row and waited forever,
silently.

The second fault was next door.  Logging every I/O register the game
touches in UKNCBTL (a unique {processor, direction, address, PC} set,
switched on once RT-11 is up) showed its PPU code reading `177714`
exactly once, at start-up, and never again - its timer handler does
not read the counter.  `xm2-01.v` re-armed the timer's request only on
that read, so the game got one tick and no more; UKNCBTL raises 304 on
every overflow while interrupts are enabled (`Board.cpp` TimerTick).
Every overflow re-arms the request now; the testbench's fifth vector
is a second timer tick with the counter unread.  Bitstream rebuilt
(logic 52%, +52 cells), gate passed, not yet flashed at the time of
writing - the Tang's FTDI wanted a replug.  Same log for the CPU side:
the program probes `177546`, `177570`, `177746`, `177760`, `172540`,
`160000` and writes sixteen words at `172100`, all of which the
emulator answers with a bus error too, so those are the same trap on
both.  If the game still stops after this, the log's remaining
differences to check are the byte writes to `177024` (a pixel through
the colour registers) and the 16-bit values it writes to `177016`,
which both implementations keep to three bits.

**Afternoon, the same day: the silent stop was the fix itself.**  With
both changes flashed the game still drew part of its first tile row
and stopped.  Rebuilt the emulator log (the instrumented copy had gone
with a host restart) and read the game's PPU code properly: its timer
handler *does* read `177714` - it stops the timer, writes the next
period to `177712` and spins on `CMP R0,@#177714` until the counter
reads it back - so the "one tick" theory above was wrong, and the
re-arm change, though it matches UKNCBTL, fixed nothing.  What the
morning's chain fix had done was replace the halt with a hang: the
gate `pin_wbi_stb_o = virq ? 0 : strobe` is combinational, xm2-01
answers 304 on the strobe's first clock and its request drops on the
next, so the strobe to `vp1_120` *rose* in the middle of the fetch;
`vp1_120` edge-detects that strobe, saw a fresh fetch, and if a
channel-2 byte was waiting - during the tile draw one always is, the
CPU sends every tile as a four-byte call - answered 340 to nobody
(top.v's mux hands the core xm2-01's word) and cleared `enVIRQPrx[2]`.
The channel-2 request was gone with the byte unread; the PPU never
took it, the CPU spun on the ready bit.  The first timer tick of the
draw, 5 ms in, is the end of the picture.  `vp1_120`'s own chain
output to `vp65` had the same gate.

Now each chip decides *while the strobe is low* which vector, if any,
it will answer, and holds that for the whole fetch (`vec_own`,
`ppu_own`, `cpu_own`); the chain strobe is the incoming one ANDed with
"not mine", and the CPU side passes the synchronised strobe on rather
than the raw one, so it cannot run ahead of the decision.
`tb_virq` gained the pair - a channel-2 byte waiting and the timer
overflowing, fetch 304 then 340 - plus a monitor that fails on any
chain strobe changing during a fetch, and a CPU-side fetch through to
the vp65 chain.  The morning's RTL fails nine ways on it; this passes.
Lint clean; `make bitstream` 15:18, timing gate passed (0 setup, 0
hold), logic 52% / registers 28% / BSRAM 66%, `bin/tang.fs` updated.
**Confirmed on the board the same afternoon**: flashed to the SPI
flash, power-cycled, and MKLAD runs - from MKLAD.DSK and through Run
SAV - the level draws whole and the game plays, with the timer, the
keyboard and the channel all live at once.  That is the first program
seen on this hardware that drives the PPU timer and channel 2
together, and the vector chain is the thing it proves.

## Open questions


- **Which bitstream is the shipped one?**  `bin/tang.fs` and
  `tang/impl/pnr/test003.fs` are the same size and date and differ in
  content.
- **What made `tang/rom/uknc_rom.mif`?**  It is 16384 words; the `.bin`
  beside it is 32256 bytes.  No converter for that in the repo.
- **What are `bin2mif`'s arguments?**  Binary only, no source.
- **Is the "Disk prot." menu value an index or a bitmask?**  The menu
  offers six choices onto `system_floppy_wprot[3:0]`; `menu.c` decides and
  the FPGA just takes four bits.  Not traced.
- **One read-after-write miss at 177 ms - GONE with defect 13.**  `make
  sim` at 300 ms reported `cpu bank1 read 166575 at 014701, wrote 146175`
  on the unmodified tree and after the floppy re-clocking alike; after
  the PPU was held until `init` (defect 13) the same run reports 0 wrong.
  Not traced to a mechanism, but the PPU running against an
  uninitialised SDRAM was the only thing that changed.
- **Why does the PPU end up in a trap loop in simulation?**  See above.
  Find the first divergence, not the symptom; an SD card model is probably
  the prerequisite for going any further.
- **Will the fixed subpacket layout play bipolar?**  Defect 11 says it
  should and says why it did not before; the board has not heard it.  If
  it does, put the DC blocker back (defect 10).
- **Why did the player hang with `Зависание при приеме а.в.п`?**  Now
  answered by defect 4: the message came back on 2 Sep 2026 from a build
  whose clk_25 -> PPU paths were modelled with the wrong phase, and it is
  the floppy status word into `vp1_128fdd` - a 20 ns path that no build
  before that day had analysed, so every placement rolled it.  Whether
  the 10:22 build's placement, which analyses it, has cleared it for good
  is the board's to say - and on 2 Sep 2026 it said yes: the 10:22 build
  loads floppies.  The gate in `tools/timing_check.py` (`make timing`,
  run by `make bitstream`) is what keeps the next layout honest on it.

## Repository hygiene

Cleaned in September 2026: every source under `tang/src/` is now in
`tang/test003.gprj` and every module in it is instantiated.  Roughly half
the `.v` files used to be outside the project - three earlier SD stacks,
an earlier OSD, a PS/2 keyboard path, the VHDL AY line, `(Копия)` files -
and ten more were inside it but unused.  `.claude/docs/fpga.md` lists
what went; git history has it.  The dead signals the same pass took out of
the custom RTL (`top.v`, `aberrant.v`, `sdram2.v`, `fdd4.v`, `vp65.v`,
`hdmi_tx.v`) were all write-only or undriven; the ABC-panned stereo pair
in `aberrant.v` went with them, since the mixer is mono by design.
Verilator `-Wall` over the custom files now reports only unused input bits
on peripheral ports, which is the bus interface and stays.
