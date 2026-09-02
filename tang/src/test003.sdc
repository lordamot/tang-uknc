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
// So setup is clean with real margin everywhere.  The 583 hold violations
// are NOT a separate discovery - they are the direct cost of the
// compromise described further down, where clk_25 and clk_3_12 have to be
// declared as independent clocks because this parser will not accept them
// as generated ones.  The tool then cannot relate their edges (TA1117,
// repeatedly) and analyses the crossings between them at the worst case.
// Before drawing any conclusion from that number, make the generated-clock
// form resolve; a hold violation between two clocks that are actually the
// same counter is not a hold violation.
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
// These are create_clock, not create_generated_clock, and that is a
// compromise worth understanding.  create_generated_clock is the right
// description - they really are divides of the PLL output - but this
// version's parser will not resolve the source: with -source
// [get_pins {pl1/rpll_inst/CLKOUT}] it answers `TA2004 : Cannot get clock
// with name ''` and drops the constraint.  Declared as independent clocks
// at their true periods the analysis inside each domain is right, which is
// the bulk of it; what is lost is the phase relationship between them and
// the PLL, so paths crossing between the two are analysed without knowing
// the edges line up.  Restoring that is worth doing if the source can be
// made to resolve.
//
// clkram is 27 MHz * 13 / 7 = 50.143 MHz, so /2 and /16 give:
create_clock -name clk_25   -period 39.886  [get_nets {clk_25}]
create_clock -name clk_3_12 -period 319.086 [get_nets {clk_3_12}]

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
set_clock_groups -asynchronous -group [get_clocks {spi_clk}] -group [get_clocks {clk27 clk_25 clk_3_12}]

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
