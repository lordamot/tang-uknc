# Timing rules

Why this file exists: on 2 Sep 2026 three consecutive layouts of the same
logic behaved three ways on the board - one reached the start screen only
on some power cycles, one never, one reached it but hung loading a floppy
- and the difference between them was placement on paths the timing tool
had not been told about.  `.claude/docs/progress.md` defects 4 and 13
have the account.  These rules exist so that adding hardware, which
always means a new layout, cannot do that again.

## The invariants

- **Every clock is declared and related.**  `tang/src/test003.sdc` names
  `clkram` on the PLL pin and `clk4`, `clk_25`, `clk_3_12` as generated
  clocks off it, with their real edges (`-edges`, not `-divide_by`: the
  PPU clock's edges sit on clk_25's falling edges).  The SPI clock is a
  base clock in its own asynchronous group.  A layout is not accepted
  while `test003.log` carries `TA1132` (a clock the SDC did not declare)
  or `TA1117` (two clocks it could not relate).
- **No flop is clocked by a data signal.**  `always @(posedge <thing>)`
  where the thing is a register bit, a pulse, a compare, a mux of counter
  bits - that is what `step`, `clk_dsk`, `sd_rd`, `sd_img_mounted`,
  `curs_set` and `clk8kHz` were, and they are enables on real clocks now.
  A new one goes in as an enable too.  `timer_clk_4` and `isread_aud` are
  the two that remain, declared at 1 us; do not add to that list.
- **Every crossing between the processors and the peripherals is
  bounded.**  clk4 against clk_25 and clk_3_12 has a phase that is
  decided at each power-up, so `set_max_delay 15` caps every path between
  those domains and the clk4 definition sits on the coincident edge for
  hold.  A path that cannot meet 15 ns is re-registered in RTL, not
  relaxed in the SDC - the CPU's DCLO/ACLO/HALT are the worked example:
  they fanned out from `R177716` into the whole CPU core and failed the
  cap, and now go through two flops on the CPU clock in `top.v`.
- **A new clock pin is a clock pin.**  `PR1014` says a clock is on
  general routing; the two known ones are the SPI clock and `clk27_d`.
  A third fails the gate.  If the hardware you are adding brings its own
  clock, it gets a `create_clock` and either a relation or an
  asynchronous group, and its crossings get synchronisers.
- **No false paths, no relaxed constraints, to make a report green.**
  `set_false_path` and `set_clock_groups` are for crossings that have
  been read and shown to be synchronised or non-existent, and the SDC
  comment says which.  The ones there now: the CPU's bus into `vp1_120`
  (a synchronised strobe and enable-qualified data), and SDRAM read data
  into either processor (the acknowledge follows the data by a clock).
  A new one needs the same paragraph.  A synchroniser's first stage is
  the textbook case; a data bus captured at a coincident edge is not,
  unless an enable that the SDC comment names keeps it from loading
  there.

## The gate

`make bitstream` runs `tools/timing_check.py` after place-and-route and
does **not** copy the bitstream to `bin/` if it fails.  `make timing`
runs the check alone on the last report.  It fails on: any setup
violation; any hold violation outside `ram1`, or more than the report
lists; `TA1132`, `TA1117`, `TA2000`, `TA2003`, `TA2004` in the log; a
`PR1014` beyond the two known nets; any of the named clocks missing.
Any hold violation fails it - the counter-bit clocks come from flops of
their own since 2 Sep 2026, so there is no artefact to allow - except
the exceptions listed in the script by name, reason and slack floor
(today: the OSD enable onto a video register's reset pin).  Adding to
that list needs the same: a name, a reason, a floor, and a line here.

A red gate is information, not an obstacle: it says which path a new
layout would have rolled the dice on.  Fix the path or the constraint,
never the check.

## When adding hardware

1. Decide which clock it lives on.  Peripherals the PPU talks to go on
   `ppuclk_n` like `aberrant` and `vp1_128fdd`; things the MCU talks to
   go on `mist_clk` (clk_25); nothing new goes on a clock of its own
   without a line in the SDC and a paragraph in `fpga.md`.
2. Every signal that crosses into or out of it from another domain is
   either a level through two flops, a pulse through a handshake, or a
   bus that the tool can time because both clocks are declared.  Say
   which, in a comment at the crossing.
3. Build.  Read the gate's output, then the clock table in
   `tang/impl/pnr/test003_tr_content.html`: the new clock is there,
   related or grouped, and the tightest paths make sense.
4. Only then flash - and say "meets timing", which is a different claim
   from "works".
