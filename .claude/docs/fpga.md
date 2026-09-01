# The FPGA implementation

Target: **GW2AR-LV18QN88C8/I7** (GW2AR-18C, QFN88) - the Tang Nano 20K.
Project file `tang/test003.gprj`, top module `top` in `tang/src/top.v`,
constraints `tang/src/test003.cst`.

## What is actually built

**`tang/test003.gprj` is the source of truth.**  Thirty-eight source
files are in it, plus `test003.cst` and `test003.sdc`, and every one of
them is instantiated: the tree was cleaned in September 2026 so that what
is under `tang/src/` is what is built.  `tools/srcs.py` reads the list
out for lint and simulation, `tools/gowin_tcl.py` for the bitstream.  The
live set, by role:

| role | files |
|---|---|
| top | `top.v` |
| processors | `cpu.v`, `ppu.v`, `wm2wb/vm2_wb.v`, `wm2wb/vm2_plm.v`, `wmrst.v` |
| video/memory | `sdram2.v`, `mkcolorreg.v` |
| peripherals | `xm2-01.v`, `vp1_120.v`, `vp65.v`, `vp1-128fdd.v`, `fdd/fdd4.v`, `aberrant.v`, `ay/ym2149.sv`, `audio.v` |
| serial | `uart/uart_rx.v`, `uart/uart_tx.v` |
| MisterNano | `mister/{mcu_spi,sysctrl,hid,osd_u8g2,sd_card,sd_rw,sdcmd_ctrl,sector_dpram}.v` |
| HDMI | `hdmi/{hdmi_tx,tmds_channel,hdmi_packet,hdmi_serdes}.v` |
| vendor IP | `ip/{sys_rpll,fifo_audio,rom208,sdbuf_sdpb,dbufsec16,uartfifo}/*.v`, `fdd/ip/rawtr_prom/*.v` |

### What was removed, September 2026

Until then about as many `.v` files sat under `tang/src/` outside the
project as inside it - three earlier SD stacks (`sd/`, `sd_dat/`, `sdio/`),
an earlier OSD, a PS/2 keyboard path, the VHDL AY line, two earlier SDRAM
arbiters, files named `(Копия)`, `.bak` and `.v_` copies, and a dozen
generated IP cores for paths that had been dropped - and several of them
shared a module name with a live file (`src/fdd4.v` against
`src/fdd/fdd4.v`, `src/ym2149.sv` against `src/ay/ym2149.sv`).  Ten more
were in the project but instantiated nowhere: `load.v` (the older
load-the-whole-image-into-RAM scheme), `sdram1.v` and the `memstr` IP it
alone used, `dbg/dbgmon.v` (see **Board diagnostics**), `ip/dvi_tx` (see
**HDMI**), `fdd/ip/buf_sec`, `uart/uart_{rx,tx}_path.v`, the disabled
`test003_lcd.cst` (an RGB LCD pinout) and `test003.rao` (an oscilloscope
setup probing the removed `load` instance).  With them went the ROM data
only they read under `tang/rom/` and the duplicate `tang/rom128/`.

All of it is in git history - `git log --all -- <path>` finds the last
commit that had a file - and none of it is coming back by accident, because
the project file no longer names it.  If one of the earlier revisions is
wanted for reference, read it out of history rather than restoring it.

## Clocks

One `sys_rpll` (`ip/sys_rpll/`), 27 MHz in:

```
FCLKIN 27, IDIV_SEL 6, FBDIV_SEL 12   ->  27 * 13 / 7 = 50.14 MHz
  CLKOUT   clkram        50.14 MHz    SDRAM + pixel clock for hdmi_tx
  CLKOUTP  O_sdram_clk   phase-shifted copy, straight out to the chip
  CLKOUTD  clk4          SDIV_SEL 12  ->  4.18 MHz, the CPU clock
```

Everything else is a **bit of the horizontal counter** in `sdram2.v`, which
runs on `clkram`:

```
clk_25  = horz[0]   25.07 MHz   the "system" clock: MisterNano, xm2-01, fdd4, vp1_120
ppu_clk = horz[3]    3.13 MHz   the PPU clock, clk_3_12 in top.v
clk_50  = clkram    50.14 MHz
```

`BUFG` instances in `top.v` put `clk4`, `~clk4`, `clk_3_12` and
`~clk_3_12` onto global lines.

Two things to know before touching any of this:

- **The CPU and the PPU are on unrelated clocks.**  The CPU runs off the
  PLL's `clk4`; the PPU off a counter bit.  Not a divider chain from a
  common source.  `sdram2` used to export `horz[2]` (6.27 MHz) as
  `cpu_clk` and `top.v` brought it to a wire nothing read, along with
  `horz[4]` as `clk_dac` into a BUFG nothing read; both went in Sep 2026.
  If the CPU is ever to run at twice the PPU rate off the one counter,
  that is a new port, not a forgotten one.
- **The timing constraints are `tang/src/test003.sdc`, Aug 2026.**  Before
  it the report said `<Timing Constraints File>: ---` and every number was
  against a tool default.  It reports 0 setup violations; the hold count
  (524 as of Sep 2026) is an artefact of `clk_25` and `clk_3_12` having to
  be declared as independent clocks - see `progress.md`.

`test003.log` also carries a dozen `TA1117` warnings - the tool cannot
relate the PLL output to `clk_25`, `clk_3_12` and `ram1/curs_set`, because
`clk_25` and friends are counter bits and `curs_set` is a data signal used
as a clock (`always @(posedge curs_set ...)` in `sdram2.v`).

## Bus fabric

Two Wishbone-ish master buses, one per processor, with the peripherals
combined by OR-of-acks and a priority mux in `top.v`.

```
PPU bus  ppu_wbm_*        peripherals: xm2-01, vp1_120, vp1-128fdd, aberrant
  data mux priority:  xm2 > vp1_120 > vp1-128fdd > aberrant
  interrupt vector bus ppu_wbi_*: xm2 then vp1_120

CPU bus  cpu_wbm_*        peripherals: vp1_120, vp65
  data mux priority:  vp1_120 > vp65
```

Because acks are ORed and the data mux is a priority chain, **two
peripherals answering the same address is silent**: the lower-priority one
still sees the strobe and still updates its own state.  That is the shape
of the AY aliasing bug in `CLAUDE.md`.

## Memory

`sdram2.v` is both the SDRAM controller and the video generator - see
`.claude/docs/video.md`.  It arbitrates two ports, `cpu_*` and `ppu_*`,
each 19-bit address / 32-bit data with a 4-bit byte mask, against the
display's own fetches.

Vendor IP in the live build:

| IP | used by | what for |
|---|---|---|
| `sys_rpll` | `top.v` | the board PLL |
| `fifo_audio` | `top.v` | crossing from `ppuclk_p` to the I²S clock |
| `rom208` | `ppu.v` | the PPU's ROM, from `tang/rom/uknc_rom.mif` |
| `sdbuf_sdpb` | `mister/sd_card.v` | SD sector buffer |
| `dbufsec16` | `fdd/fdd4.v` | double sector buffer |
| `rawtr_prom` | `fdd/fdd4.v` | the raw-track template, from `src/fdd/rom128/rawtrk.mif` |
| `uartfifo` | `vp65.v` | serial FIFO |

The `.ipc` file is the generator's input and the `.v` its output.  To
change a depth, a width or a `.mif`, edit the `.ipc` in the Gowin IP Core
Generator and regenerate; never hand-edit the `.v`.

**`hdmi/hdmi_serdes.v` is not in that table and is not IP.**  It
instantiates `rPLL`, `OSER10` and `ELVDS_OBUF` by hand.  Those are device
primitives out of the Gowin library, not generator output, so there is no
`.ipc` behind it and editing it is ordinary RTL work - but it is the one
file in `src/hdmi/` that cannot be simulated here, which is why
`tools/srcs.py` lists it in `STUBBED` and `sim/stubs/gowin_ip_sim.v` has a
model for it.

## HDMI

`src/hdmi/`, four files, August 2026.  It replaced Gowin's `DVI_TX` IP,
which is what its name says: DVI, video only, no data islands and
therefore no sound.  The docs for that IP list two options, external clock
and OBUF type, and audio is not among them; there is no Gowin HDMI IP with
audio in the Education install either.  So sound over HDMI meant writing
the encoder.

```
hdmi_tx.v       timing, packet scheduling, audio capture, the packet picker
tmds_channel.v  one channel: 8b/10b, control words, TERC4, both guard bands
hdmi_packet.v   the 32-clock packet and its BCH ECC
hdmi_serdes.v   rPLL x5, four OSER10, four ELVDS_OBUF - the only Gowin part
```

`tmds_channel.v` and `hdmi_packet.v` are transcriptions of HDMI 1.4a
sections 5.4 and 5.2.3.4, derived from Sameer Puri's
[hdl-util/hdmi](https://github.com/hdl-util/hdmi) (MIT) and rewritten in
Verilog-2001.  The rest is ours, because upstream's top level generates
its own video timing and this design already has `sdram2.v` doing that.

Four things worth knowing before touching it:

- **It takes its timing from `de`/`hs`/`vs` and knows no mode.**  A data
  island has to be announced 8 clocks ahead and a video period 10, which
  means knowing the future, so the video goes through a 12-deep delay line
  and the scheduler reads the undelayed signals.  Sync and pixels are
  delayed together, so the picture does not move.
- **The data island sits in the back porch**, four packets a line, starting
  four clocks after `hs` falls.  There are 176 clocks there and the island
  needs 144, which leaves the video preamble and guard band their ten with
  room over.  It runs on blanking lines too, and that is what carries the
  audio across the frame boundary.
- **The audio is resampled here, not taken from the I²S path, and it is
  resampled to exactly 48 kHz.**  It used to take a sample every 1024
  pixel clocks, which at 50.143 MHz is 48.968 kHz - 2% fast, not a rate
  that exists in the standard, with the IEC 60958 channel status declaring
  a flat 48 kHz beside it.  A sink clocks its converter from one and its
  buffer from the other, and 960 samples a second of disagreement drains
  or floods a receiver FIFO of a few hundred samples in about half a
  second.  On the board that was heard as keypress clicks getting through,
  music playing for half a second and stopping, and continuous music never
  playing at all - a stream with no pauses in it never gives the sink a
  reason to re-arm.

  No integer divider of 50.143 MHz lands on a standard rate (48 kHz would
  need 1044.58), so the sample instant comes from a phase accumulator
  instead: add N every pixel clock, take a sample and subtract when it
  reaches 128 x CTS.  With **N = 6144 and CTS = 50140** the ratio is
  exactly N/(128 x CTS) by construction, so the rate the sink regenerates
  and the rate we deliver agree to the bit whatever `f_TMDS` really is -
  which matters, because it is a PLL output nobody has measured.  The
  48 kHz in the channel status is now true rather than a 2% lie.  The I²S
  output is untouched and still runs at its own rate off `ppuclk_p`.
- **Five packet types go out and one deliberately does not.**  Sent: audio
  clock regeneration, audio sample, audio InfoFrame, AVI InfoFrame and the
  General Control Packet, plus null packets in the slots with nothing to
  fill them.  Not sent: the HDMI Vendor Specific InfoFrame, which only
  matters for 3D and 4K modes.

  **The GCP asserts neither mute flag - `SB0 = 8'h00`.**  It carried
  `8'h10` for a while, on the strength of one experiment where `8'h01`
  blacked the screen and was read as "bit 0 is Set_AVMUTE".  HDMI 1.4b
  table 5-8 says the reverse - bit 0 Clear, bit 4 Set - which would make
  `8'h10` a Set_AVMUTE going out fifty times a second.  The experiment
  cannot settle it, because that build carried other changes and the black
  screen had more than one candidate.  So the packet now asserts nothing,
  which is right under either reading and is what a steady-state source
  sends: a mute flag is a one-shot, not a state to restate every frame,
  and a sink powers up unmuted.  The GCP still does the job it was added
  for, which is stating the colour depth.

  **The audio sample subpacket is packed as HDMI 1.4b table 5-12** - the
  two 24-bit samples adjacent in bits 47:0, left first, and the eight
  flags in bits 55:48 as `{PR,CR,UR,VR,PL,CL,UL,VL}` - and not as two
  IEC 60958 subframes end to end.  It was the latter from 30 Aug to 1 Sep
  2026, which put sample bits 15:12 into the sink's flag positions for the
  left channel; every "bipolar is silent" and "three chips mute"
  observation of that period is that.  `.claude/docs/progress.md` defect
  11 has the bit-by-bit table.  `sim/tb/tb_top.v` decodes the spec layout
  and checks P and V, and `+AUDIOTEST` now drives the mix through a sample
  of exactly 16384 so that the check reaches the bit that mattered.

The AVI InfoFrame carries **VIC 0**, because 1280x600 at 50.7 Hz is not a
CEA mode and there is no code for it.  Whether a sink will accept audio on
a mode it does not recognise used to be an open question; as of Aug 2026 it
is settled for at least one television, which plays AY music from this
design at every volume setting.  It is not settled in general.

## Board diagnostics

There is no instrument on the board as of September 2026.  For a fortnight
in August 2026 there was one: `src/dbg/dbgmon.v` printed 18 16-bit words
as hex down the USB-C serial line ten times a second, `tools/dbgmon.py`
read and named them, and about 160 lines of probe accumulators in `top.v`
fed it - counts of AY writes, bus timeouts, beeper edges, the range of the
mixer output.  The instance came out on 31 Aug 2026 so the audio path
could be judged with nothing experimental in the design, and the module
and the reader were removed from the tree in Sep 2026 along with the rest
of the uninstantiated code.  `git log --all -- tang/src/dbg` finds the
module, and the commit before the one that dropped the instance has the
last probe list.  The reader is not in history at all - `tools/` is
gitignored and `dbgmon.py` was never force-added - but it was small: open
`/dev/serial/by-id/*if01*` at the monitor's baud rate, split each CR LF
line on spaces, check the magic word, name the columns.

Three things worth carrying forward from it, for whatever replaces it:

- **Pin 69 is the only line out.**  It is `uart_tx` into the Tang's own
  BL616, which the host sees as interface B of an FT2232
  (`/dev/serial/by-id/*if01*`, since the `ttyUSBn` number changes on
  every re-enumeration).  The VP-65's transmitter, the УКНЦ's own C2
  serial line, owns that pin now; a monitor takes it over with one
  `assign` in `top.v`.  Take bus events off the PPU bus - a write
  `aberrant` acked is an AY write - rather than out of the modules, so
  nothing has to be touched to be watched, and count the **ack**, which is
  what a silent peripheral fails at first.
- **`sys_rst_n` is active HIGH.**  The name is a lie and it has cost a
  build: it is high for the first 335 ms and low afterwards, and every
  module in this design takes it as `if (reset)`.  Wiring it to something
  that wants an active-low reset gives a block that runs for a third of a
  second after power-on and is then held in reset forever.  `sys_rst` is
  its complement and is the active-low one.  The same reasoning fixes the
  buttons: `n_all_rst = init & ~buts[0]` only makes sense if **the buttons
  read 0 released and 1 pressed**, whatever `PULL_MODE=UP` in the `.cst`
  suggests.
- **What such a monitor cannot see.**  It sampled `volume_data_l` on
  `posedge ppuclk_p`, in the same domain the mixer runs in, so a value
  that was wrong only *between* clock edges read as perfect.  That is
  exactly the bug it failed to find - `progress.md` defect 9 - and the
  general lesson is the one the SDRAM model already taught: an instrument
  that shares the design's assumptions agrees with it and both are wrong
  together.

## Resource budget

From the 31 Aug 2026 place and route (`tang/impl/pnr/test003.rpt.txt`),
the first without the diagnostic monitor:

```
Logic      8923/20736   44%
Register   3873/15915   25%
BSRAM        22/46      48%
DSP           0/         0%
PLL           2/2      100%
IOLOGIC       8/121      7%
```

January 2025 was 39% / 22% / 46%; stereo took the BSRAM up and the HDMI
encoder took the logic up.  The run before this one was 47% / 30% / 46%,
**with** the diagnostic monitor: it cost about 670 LUTs and 810 registers,
and taking it out gave them back.  BSRAM went the other way, 21 blocks to
22, and that is not noise - handing pin 69 back to `vp065` makes its
`uartfifo` reachable again, and while its transmitter drove nothing the
synthesiser had been pruning that block away.

**Both PLLs are spoken for** - `sys_rpll` off the crystal and
`hdmi_ser/pll_hdmi` off the pixel clock - so a new clock has to come out of
the existing counter chain, not a new PLL.  That was true before as well;
the second PLL used to be inside `dvi_tx`, doing the same job.  BSRAM at
48% is the next tightest, and it is what ROMs, FIFOs and sector buffers all
come out of.  Logic and registers have room.

The **IOLOGIC** row is new and is the four `OSER10`s.

## Pins

`tang/src/test003.cst`, GW2AR-18C QFN88.  Complete list:

```
clk27         4      buts[0]  88   buts[1]  87   leds[5:0]  20,19,18,17,16,15
                     (S1 resets;  S2 is constrained but read nowhere)
HDMI          O_tmds_clk_p 33,34   data[0] 35,36   data[1] 37,38   data[2] 39,40
SD card       sdclk 83  sdcmd 82  sddat0 84  sddat1 85  sddat2 80  sddat3 81
audio         HP_BCK 71  HP_WS 72  HP_DIN 73  PA_EN 74
serial        uart_tx 69  uart_rx 70      (to the on-board BL616, USB-C)
                                          uart_tx is vp065's C2 line; the
                                          diagnostic monitor takes it when
                                          it is instantiated - see below
MCU           m0s[0] 42  m0s[1] 41  m0s[2] 56  m0s[3] 54  m0s[4] 51
free          13, 48, 55, 75, 76, 86
```

### The MCU link

**As of August 2026 this is stock MiSTeryNano wiring**, and the README's
table is now the upstream one.  It was not before: Alexey had the five
signals on 71-75 against BL616 io12/13/10/11/14, which is why every
version of this document until now told you to ignore upstream diagrams.

One attachment, an external BL616 / M0S Dock, from `top.v`:

```
role                m0s bit   FPGA pin   BL616 GPIO
miso, FPGA -> MCU   m0s[0]    42         10
mosi, MCU -> FPGA   m0s[1]    41         11
csn                 m0s[2]    56         12
sclk                m0s[3]    54         13
irqn, FPGA -> MCU   m0s[4]    51         14
```

`m0s[3:1]` are driven `z` so the dock owns them; `m0s[0]` and `m0s[4]` are
the FPGA's outputs.  No build option, no jumper, no mux.

**Upstream's second attachment is deliberately not here.**  MiSTeryNano
also drives the Tang Nano 20K's own on-board BL616 over `spi_dir` 75,
`spi_dat` 76, `spi_csn` 86, `spi_sclk` 13 and `spi_irqn` 69, selecting
between the two with a flop that latches to the dock the first time
`m0s[2]` goes low.  This core carried that for one afternoon on 30 August
2026 and then gave it up, because **pin 69 is the FPGA's TX into that same
BL616** - the USB-C serial console - and the interrupt line takes it.  The
internal path had never been exercised on hardware here, needs a Tang Nano
20K of assembly 3921 or later, and costs the USB-JTAG bridge as well the
moment you actually flash that chip.  Trading a working console for an
untested attachment was the wrong way round.  Putting it back is the five
`IO_LOC` lines, the five ports and the `spi_ext` flop, all of which are in
`git show 36e8c2b`.

### What that move cost

The upstream m0s pins are 51, 54 and 56, which is exactly where this
core's I²S was, and upstream's `bl616_mon_rx` is 55, the fourth. So:

```
                before (to Aug 2026)   now
MCU link        71 72 73 74 75         42 41 56 54 51
audio I2S       56 55 54 51            71 72 73 74
serial          69 out  70 in          69 out  70 in   (unchanged)
```

The audio simply swapped onto the pins the MCU link vacated.  The serial
port went to 48/55 for a few hours, because upstream spends 69 on
`spi_irqn`, and came straight back to 69/70 when the internal BL616 link
was dropped - so **the VP-65 console is on the USB-C port exactly as it
always was**, and needs no adapter.  Upstream's 48/55 remain free and are
where to put it if 69 is ever wanted for the interrupt again.

`src/test003_lcd.cst`, the pinout for an RGB LCD panel in place of HDMI,
was disabled in the `.gprj`, carried the old five-pin MCU block and named
ports that no longer existed; it was removed in Sep 2026 and is in git
history if that variant is ever wanted.
