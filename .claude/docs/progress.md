# State of the port

Last bitstream: **30 August 2026** (`bin/tang.fs`, 7262008 bytes), built
here with `make bitstream` and carrying every RTL change in this file - the
four VM2 core fixes, the AY chipselect, the stereo audio, the first timing
constraints, the return to stock MiSTeryNano wiring, and HDMI audio.  Last MCU
firmware: **30 August 2026** (`bin/bl616.bin`, 430512 bytes), also built
here, carrying the settings-file fix; the wiring change needed nothing
from it.  **Neither has been on hardware, and the pinout changed - a board
wired for any earlier bitstream must be rewired.**  The machine runs: both
processors, screen over HDMI, USB keyboard through the BL616, four floppies
off the SD card, AY sound and the beeper, and the OSD menu.

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
  Current resource use: Logic 41%, Register 23%, BSRAM 48%, PLL 2/2,
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

Two more things learned by running it.  `clk_6_25` cannot be constrained
at all - it is `sdram2`'s `cpu_clk`, top.v brings it out to a wire nothing
reads, and synthesis removes it, which is defect 5 below showing up in a
second place.  And five signals that are flops clocked by data
(`ram1/curs_set`, `isread_aud`, `disk_step`, `fdd/clk_dsk`,
`dd1/timer_clk_4`) were being analysed at the tool's default 100 MHz,
which is where most of the original 729 setup violations came from; they
are now declared at 1 us, a deliberate bound rather than a measurement.

Still undone, in the order worth doing: make the generated clocks resolve,
then `set_input_delay`/`set_output_delay` on the SDRAM pins (the whole file
constrains the inside of the chip only), the same for TMDS, and the
question of whether `clk4` and `clk_3_12` can honestly be declared
asynchronous.

### 4. Clocks that the tools cannot reason about

- `clk_25`, `clk_3_12`, `clk_dac` are **bits of a counter**, not PLL
  outputs, so no clock relationship is derivable and `test003.log` says so
  twelve times over (`TA1117`).
- `sdram2.v` clocks a flop off `curs_set`, a data signal
  (`always @(posedge curs_set or posedge new_scr)`).  Same for the four
  `mount_dsk` flops in `top.v`, clocked off `sd_img_mounted[n]`.
- `top.v` warned twice at PnR that `spi_io_clk_d` and `clk27_d` were
  routed on general fabric rather than a clock tree (`PR1014`).  Since the
  MCU link became a mux of two sources (defect 6) only `clk27_d` is left;
  the SPI clock is no longer a pin the tool can name.

None of this is broken today.  All of it is why the design is fragile
against re-place-and-route.

### 5. `clk_6_25` goes nowhere

`sdram2`'s `cpu_clk` (6.27 MHz) is brought out to a wire in `top.v` that
nothing reads.  The CPU runs on the PLL's `clk4` (4.18 MHz) instead.  If
the intent was to run the CPU at twice the PPU rate off one counter, that
is not what happens.

### 6. The MCU link was not wired like MiSTeryNano's - CHANGED

Not a defect, a deliberate divergence, and now undone.  Alexey had the
five SPI signals on FPGA pins 71-75; upstream puts them on `m0s[4:0]` =
42/41/56/54/51, and every MiSTeryNano diagram, every MiSTeryShield20k
carrier and every third-party build assumes upstream's.  The MCU side was
never the divergence - `mnano/spi.c` is byte-identical to upstream's, GPIO
12/13/10/11/14 - so this was a change to `test003.cst` and `top.v` only,
and the firmware binary in `bin/` is unaffected.

What `top.v` gained is upstream's dual-MCU arrangement, not just new pin
numbers: `spi_dir`/`spi_dat`/`spi_csn`/`spi_sclk`/`spi_irqn` on 75/76/86/
13/69 reach the Tang's own on-board BL616, the two FPGA outputs are driven
to both ports at once, and a single flop `spi_ext` selects the three
inputs - internal after reset, external for good once `m0s[2]` is first
seen low.  A dock therefore needs no build option; the transaction during
which the flop settles may be lost, and `main.c`'s retry loop absorbs that
exactly as it does upstream.

The cost is that upstream's 51/54/56 are where this core's I²S was, and 55
is upstream's `bl616_mon_rx`:

```
                before                 now
MCU link        71 72 73 74 75         42 41 56 54 51
audio I2S       56 55 54 51            71 72 73 74
serial          69 out  70 in          48 out  55 in
```

Audio swapped onto the pins the link vacated. The serial port could not
stay: 69 is the FPGA's TX into the on-board BL616 and upstream spends it
on `spi_irqn`, and 70 is that BL616's TX, which an external adapter would
fight - so **VP-65 no longer reaches the USB-C serial port** and needs a
USB-UART adapter on 48/55.

Checked: lint clean; `make sim` output bit-identical to the same run
before the change, including the one read-after-write mismatch, which is
defect-free evidence that nothing but placement moved; `make bitstream`
places every pin as constrained, 0 setup violations.  **Not checked on
hardware, and this is the one change in this file that can be wrong in a
way no simulation will show** - it is entirely about which pad a signal
comes out of.  The internal-BL616 half has never been exercised at all.

`src/test003_lcd.cst` still carries the old five-pin MCU block.  It is
disabled in the `.gprj` and now names ports that do not exist.

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

What was **not** checked, and it is the important part: no display has
ever been asked to play this.  The ECC check in the testbench uses the
same polynomial constant as the encoder, so it proves the plumbing - bit
order, timing, reset - and not the polynomial.  No General Control Packet
is sent, and the AVI InfoFrame carries VIC 0 because 1280x600 at 50.7 Hz
is not a CEA mode; either could be why a real sink stays silent.  Those
two are the first things to try.

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
- **Why does the PPU end up in a trap loop in simulation?**  See above.
  Find the first divergence, not the symptom; an SD card model is probably
  the prerequisite for going any further.
- **Why is `sdram1.v` in the build?**  `sdram2` is what `top.v`
  instantiates; `sdram1` is compiled and appears to be unreferenced from
  the top-level hierarchy.

## Repository hygiene

Roughly half the `.v` files under `tang/src/` are not in
`tang/test003.gprj`, including three complete earlier SD stacks, an earlier
OSD, an earlier PS/2 keyboard path, and the whole VHDL AY line.  Several
share a module name with a live file.  The list is in
`.claude/docs/fpga.md`; check it before editing anything.
