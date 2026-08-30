# The FPGA implementation

Target: **GW2AR-LV18QN88C8/I7** (GW2AR-18C, QFN88) - the Tang Nano 20K.
Project file `tang/test003.gprj`, top module `top` in `tang/src/top.v`,
constraints `tang/src/test003.cst`.

## What is actually built

**`tang/test003.gprj` is the source of truth.**  Forty files are enabled in
it; roughly as many `.v` files under `tang/src/` are not, and several of
those are earlier revisions with the same module name as a live one.  The
live set, by role:

| role | files |
|---|---|
| top | `top.v` |
| processors | `cpu.v`, `ppu.v`, `wm2wb/vm2_wb.v`, `wm2wb/vm2_plm.v` |
| video/memory | `sdram1.v`, `sdram2.v`, `mkcolorreg.v` |
| peripherals | `xm2-01.v`, `vp1_120.v`, `vp65.v`, `vp1-128fdd.v`, `fdd/fdd4.v`, `aberrant.v`, `ay/ym2149.sv`, `audio.v` |
| serial | `uart/uart_{rx,tx}.v`, `uart/uart_{rx,tx}_path.v` |
| MisterNano | `mister/{mcu_spi,sysctrl,hid,osd_u8g2,sd_card,sd_rw,sdcmd_ctrl,sector_dpram}.v` |
| vendor IP | `ip/{sys_rpll,dvi_tx,fifo_audio,memstr,rom208,sdbuf_sdpb,dbufsec16,uartfifo}/*.v`, `fdd/ip/{buf_sec,rawtr_prom}/*.v` |
| in the project but never instantiated | `load.v` |

### Dead files - present but not built

Do not fix bugs in these, and do not delete them either; several are the
author's working history.

```
src/fdd4.v                      superseded by src/fdd/fdd4.v (different ports)
src/fdd4 (Копия).v              a copy of the above
src/vp1-128fdd (Копия).v        a copy
src/sdcontroller.v              superseded by fdd/fdd4.v talking to mister/sd_rw
src/fdd/sdcontroller.v
src/sdram.v, sdram100.v         earlier arbiters; sdram1.v + sdram2.v are live
src/osd.v (+ ip/osdfont)        earlier OSD; mister/osd_u8g2.v is live
src/ps2/*                       earlier PS/2 keyboard path; HID comes over SPI now
src/sd/*, src/sd_dat/*, src/sdio/*   three earlier SD stacks
src/ym2149.sv                   root copy; ay/ym2149.sv is live
src/ay/{ay8910.vhd,ayglue.v,ym2149.vhd}, src/YM2149_volmix.vhd,
src/vol_table_array.vhd         the VHDL AY line, unused - the build is
                                Verilog-only and no VHDL file is in the .gprj
ip/{bufsec16,secrom16,secstat16,osdfont,filename,fifo_hs8,videofifo,
    hdmi_rpll,lcd_rpll,gowin_clkdiv,sys_clkdiv2,sdram_controller_hs}
                                generated IP for paths that were dropped
```

`src/test003_lcd.cst` is in the project but disabled - it is the pinout for
driving an RGB LCD panel instead of HDMI.  `src/test003.rao` is a disabled
Gowin Analyzer Oscilloscope setup.

## Clocks

One `sys_rpll` (`ip/sys_rpll/`), 27 MHz in:

```
FCLKIN 27, IDIV_SEL 6, FBDIV_SEL 12   ->  27 * 13 / 7 = 50.14 MHz
  CLKOUT   clkram        50.14 MHz    SDRAM + pixel clock for dvi_tx
  CLKOUTP  O_sdram_clk   phase-shifted copy, straight out to the chip
  CLKOUTD  clk4          SDIV_SEL 12  ->  4.18 MHz, the CPU clock
```

Everything else is a **bit of the horizontal counter** in `sdram2.v`, which
runs on `clkram`:

```
clk_25  = horz[0]   25.07 MHz   the "system" clock: MisterNano, xm2-01, fdd4, vp1_120
clk_12  = horz[1]   12.5  MHz   internal
clk_6   = horz[2]    6.27 MHz   exported as cpu_clk - NOT USED, see below
clk_3   = horz[3]    3.13 MHz   ppu clock
clk_dac = horz[4]    1.57 MHz   audio
clk_50  = clkram    50.14 MHz
```

`BUFG` instances in `top.v` put `clk4`, `~clk4`, `clk_3_12`, `~clk_3_12`
and `clk_dac` onto global lines.

Two things to know before touching any of this:

- **`clk_6_25` is dangling.**  `sdram2`'s `cpu_clk` output is wired to a
  wire in `top.v` that nothing reads; the CPU actually runs off the PLL's
  `clk4`.  So the CPU and the PPU are on *unrelated* clocks, not on a
  divider chain from a common one.
- **There is no timing constraints file.**  `tang/impl/pnr/test003.rpt.txt`
  says `<Timing Constraints File>: ---`, so every number in
  `test003.timing_paths` is against a tool default and the worst reported
  setup figure (-6.4 ns, on `ppu1/ppu`) means nothing in particular.  The
  design works on hardware; that is the only evidence there is.  Adding an
  `.sdc` is the single highest-value change available and would probably
  report a pile of violations on day one.

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
display's own fetches.  `sdram1.v` is also in the build and instantiates
`memstr`.

Vendor IP in the live build:

| IP | used by | what for |
|---|---|---|
| `sys_rpll` | `top.v` | the one PLL |
| `dvi_tx` | `top.v` | HDMI/TMDS encoder and serialiser |
| `fifo_audio` | `top.v` | crossing from `ppuclk_p` to the I²S clock |
| `rom208` | `ppu.v` | the PPU's ROM |
| `memstr` | `sdram1.v` | line store |
| `sdbuf_sdpb` | `load.v` (uninstantiated) | SD sector buffer |
| `dbufsec16` | `fdd/fdd4.v` | double sector buffer |
| `rawtr_prom` | `fdd/fdd4.v` | the raw-track template, from `rom128/rawtrk.mif` |
| `uartfifo` | `vp65.v` | serial FIFO |
| `buf_sec` | - | in the project, not instantiated |

The `.ipc` file is the generator's input and the `.v` its output.  To
change a depth, a width or a `.mif`, edit the `.ipc` in the Gowin IP Core
Generator and regenerate; never hand-edit the `.v`.

## Resource budget

From the January 2025 place and route (`tang/impl/pnr/test003.rpt.txt`):

```
Logic      8000/20736   39%
Register   3477/15915   22%
BSRAM                   46%
DSP           0/         0%
PLL           2/2      100%
```

**Both PLLs are spoken for** - the design has one `sys_rpll` and `dvi_tx`
brings its own - so a new clock has to come out of the existing counter
chain, not a new PLL.  BSRAM at 46% is the next tightest, and it is what
ROMs, FIFOs and sector buffers all come out of.  Logic and registers have
plenty of room.

## Pins

`tang/src/test003.cst`, GW2AR-18C QFN88.  Complete list:

```
clk27         4      buts[0]  88   buts[1]  87   leds[5:0]  20,19,18,17,16,15
HDMI          O_tmds_clk_p 33,34   data[0] 35,36   data[1] 37,38   data[2] 39,40
SD card       sdclk 83  sdcmd 82  sddat0 84  sddat1 85  sddat2 80  sddat3 81
audio         HP_BCK 71  HP_WS 72  HP_DIN 73  PA_EN 74
serial        uart_tx 48  uart_rx 55
MCU external  m0s[0] 42  m0s[1] 41  m0s[2] 56  m0s[3] 54  m0s[4] 51
MCU internal  spi_dir 75  spi_dat 76  spi_csn 86  spi_sclk 13  spi_irqn 69
```

### The MCU link

**As of August 2026 this is stock MiSTeryNano wiring**, and the README's
table is now the upstream one.  It was not before: Alexey had the five
signals on 71-75 against BL616 io12/13/10/11/14, which is why every
version of this document until now told you to ignore upstream diagrams.

Upstream supports two MCUs at once and so does this, from `top.v`:

```
role                external M0S Dock   internal BL616   BL616 GPIO
miso, FPGA -> MCU   m0s[0]  42          spi_dir   75     10
mosi, MCU -> FPGA   m0s[1]  41          spi_dat   76     11
csn                 m0s[2]  56          spi_csn   86     12
sclk                m0s[3]  54          spi_sclk  13     13
irqn, FPGA -> MCU   m0s[4]  51          spi_irqn  69     14
```

The two outputs go to both ports unconditionally; `m0s[3:1]` are driven
`z` so the dock owns them.  The three inputs are selected by `spi_ext`,
a single flop that comes out of reset choosing the internal BL616 and
latches to the external one the first time `m0s[2]` is seen low.  So an
M0S Dock needs no build option and no jumper - plugging it in and letting
its firmware start is the whole configuration - and the first transaction
may be lost while the flop settles, which the firmware's retry loop in
`main.c` absorbs.

The internal path has never been exercised on hardware here.  It also
costs the USB-JTAG bridge (flashing that BL616 replaces it) and needs a
Tang Nano 20K of assembly 3921 or later.

### What that move cost

The upstream m0s pins are 51, 54 and 56, which is exactly where this
core's I²S was, and upstream's `bl616_mon_rx` is 55, the fourth. So:

```
                before (to Aug 2026)   now
MCU link        71 72 73 74 75         42 41 56 54 51
audio I2S       56 55 54 51            71 72 73 74
serial          69 out  70 in          48 out  55 in
```

The audio simply swapped onto the pins the MCU link vacated.  The serial
port could not: 69 is the FPGA's TX into the on-board BL616 and upstream
spends it on `spi_irqn`, and 70 is that BL616's TX, which would fight an
external adapter. Both ends therefore move to the header pins upstream
reserves for a USB-UART adapter, 48 and 55 - **the VP-65 serial port no
longer reaches the USB-C port at all**, and needs an adapter.

`src/test003_lcd.cst` still carries the old five-pin MCU block. It is
`enable="0"` in the `.gprj` and names ports that no longer exist, so it
would have to be brought forward before that variant could be built.
