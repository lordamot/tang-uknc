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
// gw_sh - and where it stands as of 30 August 2026:
//
//   Paths analysed                 13809
//   Endpoints analysed              8629
//   Setup-violated endpoints            0     (729 before these clocks
//                                              were declared)
//   Hold-violated endpoints           559
//
//   clk_25    needs  25.071 MHz,  makes 106.612 MHz
//   clk_3_12  needs   3.134 MHz,  makes  40.105 MHz
//   PLL CLKOUT       50.143 MHz,  makes  67.225 MHz
//   PLL CLKOUTD       4.179 MHz,  makes  41.239 MHz
//
// So setup is clean with real margin everywhere.  The 559 hold violations
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
//     `- (inside dvi_tx: hdmi_rpll and its clkdiv, both internal to the IP)
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
//   sdram2.v : always @(posedge curs_set or posedge new_scr)
//   top.v    : always @(posedge sd_img_mounted[n])   x4
//   fdd4.v   : disk_step, clk_dsk
//   xm2-01.v : timer_clk_4
//   audio.v  : the FIFO read strobe, isread_aud
//
// Left undeclared, each of these is analysed against the tool's default
// 100 MHz, which is nonsense - they are event signals that change a few
// hundred thousand times a second at most, and that default is where the
// bulk of the reported setup violations come from.  Declared at a period
// that reflects what they actually are, the analysis becomes honest.
//
// These periods are BOUNDS, not measurements: 1 us is far slower than any
// of them runs, chosen so the paths from them are not the thing hiding a
// real violation elsewhere.  The proper fix is to re-clock every one of
// them onto a real clock with an enable, at which point all of this goes.
//------------------------------------------------------------------------
create_clock -name curs_set     -period 1000 [get_nets {ram1/curs_set}]
create_clock -name isread_aud   -period 1000 [get_nets {isread_aud}]
create_clock -name disk_step    -period 1000 [get_nets {disk_step}]
create_clock -name clk_dsk      -period 1000 [get_nets {fdd/clk_dsk}]
create_clock -name timer_clk_4  -period 1000 [get_nets {dd1/timer_clk_4}]

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
