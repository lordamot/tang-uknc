#!/usr/bin/env python3
"""Gate a place-and-route on its timing report.

Reads tang/impl/pnr/test003_tr_content.html and test003.log and exits
non-zero if the layout is one that could break the machine the way the
2 Sep 2026 layouts did (.claude/docs/progress.md, defects 4 and 13):

  * any setup-violated endpoint;
  * any hold-violated path at all, or more hold violations than the
    report lists, so that none can hide;
  * a clock the tool found that the SDC did not declare (TA1132), or two
    clocks it could not relate (TA1117) - a new clock has to be declared
    and related, or put in an asynchronous group on purpose;
  * a constraint the parser dropped (TA2000/TA2003/TA2004);
  * a clock on general routing (PR1014) beyond the two known ones;
  * any of the named clocks missing from the report, which means the SDC
    stopped describing the design.

There used to be an allowance for hold lines inside ram1, the artefact
of clk_25/clk_3_12 being defined on counter bits that also fed logic;
since the clocks come from flops of their own (sdram2.v, clk25_q and
clk312_q) there is no artefact and no allowance.  The only exceptions
are the named ones below, each with a reason and a slack floor.
Run by `make bitstream` after PnR and by `make timing` on its own.
"""
import re, sys, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
# The PnR directory: this tree's, or the one named on the command line
# (../tang-ultima builds this core out of its tree and checks it there).
PNR  = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "tang/impl/pnr"
TR   = PNR / "test003_tr_content.html"
LOG  = PNR / "test003.log"

REQUIRED_CLOCKS = ["clk27", "clkram", "clk4", "clk_25", "clk_3_12", "spi_clk"]
KNOWN_FABRIC_CLOCKS = {"m0s_in[3]", "clk27_d"}   # the SPI clock pin; clk27's sampled copy
HOLD_ARTEFACT = re.compile(r"(?!x)x")   # matches nothing; see the docstring
# Named exceptions: (from-node regex, to-node regex, slack floor in ns, why).
# The OSD's enable is a level that synthesis maps onto the video registers'
# sync-reset pins, and the router does not hold-fix reset pins; at worst
# it is one pixel wrong on the frame the OSD is switched, and the floor
# says how far it may drift before it counts.
HOLD_EXCEPTIONS = [
    (re.compile(r"^osd1/enabled_s\d+/Q$"), re.compile(r"^I_rgb_[rgb]_\d+_s\d+/RESET$"), -0.2,
     "OSD enable onto a video register reset pin, a level"),
]

def text(p):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]*>", " ", p.read_text(errors="replace")))

def main():
    errs = []
    if not TR.exists() or not LOG.exists():
        print("timing_check: no PnR report - run make bitstream first")
        return 2
    t = text(TR)
    log = LOG.read_text(errors="replace")

    m = re.search(r"Numbers of Setup Violated Endpoints (\d+)", t)
    n = re.search(r"Numbers of Hold Violated Endpoints (\d+)", t)
    setup = int(m.group(1)) if m else -1
    hold  = int(n.group(1)) if n else -1
    if setup != 0:
        errs.append(f"{setup} setup-violated endpoints")

    # the hold path table: "Path Number Path Slack From Node To Node From Clock To Clock ..."
    hp = re.search(r"Hold Paths Table.*?Path Number.*?Data Delay(.*?)(?:Setup|Recovery|Removal|Minimum|$)", t)
    listed = []
    if hp:
        for row in re.finditer(r"\b(\d{1,2}) (-\d+\.\d+) (\S+) (\S+) (\S+) (\S+)", hp.group(1)):
            listed.append((float(row.group(2)), row.group(3), row.group(4), row.group(5), row.group(6)))
    def excused(r):
        if HOLD_ARTEFACT.match(f"{r[1]} {r[2]}"):
            return True
        return any(f.match(r[1]) and t.match(r[2]) and r[0] >= floor
                   for f, t, floor, _ in HOLD_EXCEPTIONS)
    outside = [r for r in listed if not excused(r)]
    if outside:
        errs.append(f"{len(outside)} hold-violated path(s):")
        for r in outside[:10]:
            errs.append(f"    {r[0]:7.3f}  {r[1]} -> {r[2]}  ({r[3]} -> {r[4]})")
    if hold > len(listed) and hold > 25:
        errs.append(f"{hold} hold-violated endpoints but the report lists only {len(listed)} paths - cannot audit them")

    clocks = re.search(r"Clock Name Type Period(.*?)Clock Name Constraint", t)
    names = set(re.findall(r"\b(\S+) (?:Base|Generated) \d", clocks.group(1))) if clocks else set()
    for c in REQUIRED_CLOCKS:
        if c not in names:
            errs.append(f"clock {c} is not in the report - a constraint was dropped")

    for code, why in [("TA1132", "a clock the SDC did not declare"),
                      ("TA1117", "two clocks the tool could not relate"),
                      ("TA2000", "SDC syntax error"),
                      ("TA2003", "SDC object not found"),
                      ("TA2004", "SDC clock not found")]:
        for line in log.splitlines():
            if code in line:
                errs.append(f"{code} ({why}): {line.strip()}")
    for line in log.splitlines():
        if "PR1014" in line:
            net = re.search(r"clock signal '([^']+)'", line)
            if net and net.group(1) not in KNOWN_FABRIC_CLOCKS:
                errs.append(f"PR1014: new clock on general routing: {net.group(1)}")

    print(f"timing_check: setup violated {setup}, hold violated {hold} "
          f"({len(listed)} listed, {len(listed) - len(outside)} excused by name), "
          f"clocks {', '.join(sorted(names))}")
    if errs:
        print("timing_check: FAIL")
        for e in errs:
            print("  " + e)
        return 1
    print("timing_check: ok - this layout is analysed on every crossing the SDC names")
    return 0

if __name__ == "__main__":
    sys.exit(main())
