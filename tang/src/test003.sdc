//========================================================================
// Timing constraints for test003 (MC0511 on Tang Nano 20K).
//========================================================================
// Before this file existed the PnR report said
//
//     <Timing Constraints File>: ---
//
// which means every timing number the tool had ever produced for this
// design was against its own default and meant nothing.  This file names
// the clocks, and that alone turned the timing report from noise into an
// analysis.
//
// It HAS been run - `make bitstream` builds the whole thing headless with
// gw_sh - and where it stands as of 30 August 2026, with the HDMI encoder
// in place of Gowin's dvi_tx:
//
//   Paths analysed                 14651
//   Endpoints analysed              8997
//   Setup-violated endpoints            0     (729 before these clocks
//                                              were declared)
//   Hold-violated endpoints           583
//
//   clk_25    needs  25.071 MHz,  makes 111.510 MHz
//   clk_3_12  needs   3.134 MHz,  makes  36.814 MHz
//   PLL CLKOUT       50.143 MHz,  makes  55.182 MHz
//   PLL CLKOUTD       4.179 MHz,  makes  42.330 MHz
//
// The 50.143 MHz domain is the tight one, at 1.82 ns of slack, and it was
// tighter after the encoder went in - 67.2 MHz before - but the critical
// path is NOT in the encoder.  It runs from sdram2's horz counter through
// the pixel lookup and the OSD into top.v's I_rgb_* registers, and it got
// slower because the die got fuller, not because anything was added to
// it.  Nothing under src/hdmi/ appears in the ten worst paths.
//
// The HDMI serial clock needs no line here.  src/hdmi/hdmi_serdes.v takes
// the pixel clock as its PLL reference, so the tool derives it on its own
// and says so: hdmi_ser/pll_hdmi/CLKOUT, generated, 250.715 MHz, master
// pl1/rpll_inst/CLKOUT.  That it is derived rather than declared is the
// whole reason the OSER10s can be trusted - the two clocks are related.
//
// The 583 hold violations of that date were the cost of clk_25 and
// clk_3_12 being declared as independent clocks, which this parser forced
// until the form that it does accept was found on 2 Sep 2026 - see the
// counter-bit section below.  With the four clocks related the count is
// 56, and what is left is real or a known artefact, both described there.
//
// Do not make the report green by adding false paths until each one has
// been shown to be a genuine non-path.  A quiet report bought that way is
// worth less than the noisy one it replaced.
//
//------------------------------------------------------------------------
// The clock tree, as it actually is
//------------------------------------------------------------------------
//   clk27            27.000 MHz   board oscillator, pin 4
//     `- sys_rpll pl1 (x13 / 7)
//         |- clkram        50.143 MHz   clkout   - SDRAM, and clkpix
//         |- O_sdram_clk   50.143 MHz   clkoutp  - phase-shifted, to the pad
//         `- clk4           4.179 MHz   clkoutd  (/12) - the CPU
//     `- hdmi_ser/pll_hdmi (x5, referenced to clkram, not to clk27)
//         `- clk_serial   250.715 MHz - the four OSER10s
//            (this used to be a PLL inside Gowin's dvi_tx doing the
//             same thing; the budget is unchanged at two of two)
//
// Everything else is a BIT OF A COUNTER, not a PLL output.  sdram2's
// `horz` counter runs on clkram, and:
//
//   clk_50  = clkram        50.143 MHz
//   clk_25  = horz[0]       25.071 MHz   the whole MiSTeryNano side
//   clk_6_25= horz[2]        6.268 MHz   brought out, read by nothing
//   clk_3_12= horz[3]        3.134 MHz   the PPU
//   clk_dac = horz[4]        1.567 MHz
//
// The tools cannot derive those relationships on their own - test003.log
// says so twelve times over as TA1117 - which is what the
// create_generated_clock lines below are for.
//========================================================================

//------------------------------------------------------------------------
// Board clock.  The PLL outputs are derived from this by the tool through
// the rPLL primitive in src/ip/sys_rpll; they are deliberately not
// declared again here, because declaring a PLL output by hand replaces
// the derived clock rather than adding to it, and gets the phase of
// clkoutp wrong.
//------------------------------------------------------------------------
create_clock -name clk27 -period 37.037 -waveform {0 18.518} [get_ports {clk27}]

//------------------------------------------------------------------------
// The counter-bit clocks.
//
// clk_25 and clk_3_12 are bits of the `horz` counter in sdram2.v, so the
// tool cannot derive them and they have to be declared.  Two naming traps,
// both learned by running it:
//
//  * the source is NOT `clkram`.  That name does not survive synthesis -
//    PnR answers TA1061/TA2003 and throws the constraint away.  The PLL
//    output pin is what to use, and the timing report calls it
//    pl1/rpll_inst/CLKOUT.
//  * `clk_6_25` and `clk_dac` cannot be constrained at all.  clk_6_25 is
//    sdram2's cpu_clk, which top.v brings out to a wire nothing reads, so
//    synthesis removes it; clk_dac does not survive either.  Constrain
//    what exists.
//------------------------------------------------------------------------
// One line each - this parser does not take a backslash continuation.
//
// Until 2 Sep 2026 these were create_clock, declared independent, because
// no create_generated_clock form would parse; the crossings between the
// processors and the clk_25 peripherals were then not analysed at all.
// The form that parses, and the phase that is right, are below.
//
// clkram is 27 MHz * 13 / 7 = 50.143 MHz, so /2 and /16 give:
// Sep 2026: declared as what they are.  Two forms fail with TA2004
// "Cannot get clock with name ''": -source on the PLL's CLKOUT pin, and
// -source on the counter flop's own CLK pin.  What the parser wants is a
// NAMED clock at the source, so clkram is declared here on the PLL pin
// (this replaces the tool's own derived clock on that pin; clkoutp's
// phase, which the header above worried about, only reaches the SDRAM
// pad and nothing inside the chip is timed against it), and every
// division of it - clk4 in the PLL, clk_25 and clk_3_12 in the counter -
// is a generated clock with clkram as -master_clock.  The tool then
// relates all four and analyses, and fixes hold on, every crossing
// between the processors and the peripherals on clk_25, which every clk4
// edge hits on a clk_25 edge.  Before this those paths were not analysed
// at all (TA1117), and a placement decided whether the CPU's channel to
// the PPU worked.
create_clock -name clkram -period 19.943 -waveform {0 9.972} [get_pins {pl1/rpll_inst/CLKOUT}]
create_generated_clock -name clk4     -source [get_pins {pl1/rpll_inst/CLKOUT}] -master_clock clkram -divide_by 12 [get_pins {pl1/rpll_inst/CLKOUTD}]
// PHASE.  horz counts clkram edges from lock, so with k the edge number:
// horz[0] rises on odd k; horz[3] toggles when horz[2:0] wraps 7 -> 0,
// which is an EVEN k - the same edge on which horz[0] falls.  So every
// edge of clk_3_12, rising or falling, sits on a FALLING edge of clk_25,
// 20 ns from the nearest rising one.  `-divide_by` alone puts every
// generated clock's rising edge on master edge 1, i.e. clk_25 and
// clk_3_12 rising together, which is wrong by one clkram period - and
// with that model every clk_25 -> PPU path was checked for hold as if
// coincident (false violations on fdd -> vp128, volume -> mixer,
// keyboard -> R177702) and for setup as if it had 320 ns, when it has 20.
// The floppy's status word into vp1_128fdd is exactly such a path, and
// the build that carried the wrong phase loaded no floppy ("зависание
// при приеме А.В.Р.").  Master edges are numbered from 1, rising odd,
// falling even, so clk_25 rising at k=1,3,.. is edges 3,7,..:
create_generated_clock -name clk_25   -source [get_pins {pl1/rpll_inst/CLKOUT}] -master_clock clkram -edges {3 5 7} [get_pins {ram1/horz_0_s0/Q}]
// clk_25 and clk_3_12 are defined on the counter flops' Q pins.  That has
// a cost: horz[3:0] is also the SDRAM state machine's phase (`q`), and a
// clock defined on a Q pin makes every path from it look clock-launched,
// so the report carries a handful of false hold violations on the
// counter's own increment and on sdram2's use of q - all of them
// clk_3_12/clk_25 -> clkram inside ram1, all of them really clkram ->
// clkram.  Defining clk_3_12 on the BUFG output t3/O instead was tried
// (Sep 2026) and the parser took it, but the inverted twin on t3n/O was
// refused (TA2003), and a clock on t3/O alone would leave the PPU's
// negedge flops unconstrained - the inverter feeds off the raw net, not
// off t3/O.  So the Q pin it is: from there the network reaches both
// BUFGs and the inverter.  Read the ram1-internal hold lines as the
// artefact they are; anything between two different modules is real.
// clk_3_12 rising at k=8 (edge 17), falling at k=16 (edge 33): its edges
// on even k, as above.  Polarity matters here because vp1_128fdd and
// aberrant run on the inverted BUFG, and the tool follows the inverter.
create_generated_clock -name clk_3_12 -source [get_pins {pl1/rpll_inst/CLKOUT}] -master_clock clkram -edges {17 33 49} [get_pins {ram1/horz_3_s0/Q}]

//------------------------------------------------------------------------
// Flops clocked by data, which is not a thing a timing tool can analyse.
//
// As of Sep 2026 the SD and floppy path is clear of them: fdd4.v runs
// entirely on clk_25 with clk_dsk/clk_dsk_n as enables and `step` through
// a synchroniser, top.v samples sd_img_mounted on mist_clk, and sdram2.v's
// cursor flop runs on clkram.  The `curs_set`, `disk_step` and `clk_dsk`
// clocks that used to be declared here at an invented 1 us no longer
// exist as clocks.  What is left:
//
//   xm2-01.v : timer_clk_4 - the PPU timer's prescaler pick, a mux of
//              counter bits used as a clock; and clk8kHz, the beeper
//              divider
//   audio.v  : the FIFO read strobe, isread_aud
//
// Both are inside the PPU's own domain and slow.  Left undeclared they
// are analysed against the tool's default 100 MHz, which is nonsense and
// is where spurious setup violations come from; declared at a period that
// is a BOUND rather than a measurement - 1 us is far slower than either
// runs - the paths from them are not the thing hiding a real violation
// elsewhere.  The proper fix is the same as was done for the floppy: an
// enable on a real clock, after which these two lines go.
//------------------------------------------------------------------------
create_clock -name isread_aud   -period 1000 [get_nets {isread_aud}]
create_clock -name timer_clk_4  -period 1000 [get_nets {dd1/timer_clk_4}]

//------------------------------------------------------------------------
// The MCU's SPI link.  m0s[3] is the BL616's SPI clock, 20 MHz
// (mnano/spi.c), driven into a general I/O pin, so it reaches
// mcu_spi.v's flops over general routing - PR1014 in the log says so.
// Mode 1: the MCU sets up MOSI and reads MISO on the FALLING edge, the
// FPGA shifts MOSI in on the falling edge and drives MISO on the rising
// one.  So the MISO path is clock-in through fabric, a flop, and the pad,
// all inside the 25 ns to the next falling edge - and until Sep 2026 that
// was not constrained at all, so each placement met it or did not by
// luck.  Whether it did is the difference between the MCU's power-on
// handshake completing and the machine sitting in cold reset with no
// start screen; with an SD card present the mount traffic on the same
// link is more chances to get it wrong.
//
// The delays are the BL616's, not measured: 5 ns for its output valid
// after its own edge and 5 ns of setup at its input, plus 2 ns of cable
// each way.  They are bounds, and generous ones for this cable.
//------------------------------------------------------------------------
create_clock -name spi_clk -period 50 -waveform {0 25} [get_ports {m0s[3]}]
set_input_delay  -clock spi_clk -clock_fall -max 7 [get_ports {m0s[1] m0s[2]}]
set_input_delay  -clock spi_clk -clock_fall -min 1 [get_ports {m0s[1] m0s[2]}]
set_output_delay -clock spi_clk -clock_fall -max 7 [get_ports {m0s[0]}]
set_output_delay -clock spi_clk -clock_fall -min -1 [get_ports {m0s[0]}]

// The SPI domain is asynchronous to every clock on the board and the
// crossing in mcu_spi.v is a handshake: spi_data_in is written on the
// SPI edge that raises spi_data_in_ready, and mist_clk reads it two flops
// after seeing that flag, by which time it has been stable for three SPI
// bit times.  Every path between the groups goes through that flag, so
// declaring the groups asynchronous hides nothing that was analysable.
set_clock_groups -asynchronous -group [get_clocks {spi_clk}] -group [get_clocks {clk27 clkram clk4 clk_25 clk_3_12}]

//------------------------------------------------------------------------
// Left deliberately undone, in the order worth doing:
//
//  1. set_input_delay / set_output_delay on the SDRAM bus.  Everything
//     here constrains the inside of the chip only; the pins are still
//     unanalysed, and the SDRAM interface at 50 MHz with a
//     phase-shifted output clock is exactly where board-level timing
//     would bite.  It needs the MT48LC datasheet numbers, not a guess.
//  2. The same for the TMDS pins, though dvi_tx handles its own
//     serialiser internally and this matters less.
//  3. set_clock_groups -asynchronous between clk4 and clk_3_12.  This is
//     tempting - the CPU and PPU really do run on unrelated dividers -
//     but the two talk to each other over the wishbone, and declaring
//     them asynchronous without checking that every crossing is
//     synchronised turns a reported problem into an unreported one.
//     Check the crossings first.
//========================================================================
