#!/usr/bin/env python3
"""Print the design's source list, straight out of the Gowin project file.

tang/test003.gprj is the source of truth for what gets built (see
.claude/docs/fpga.md), so the simulation and lint flows read it rather
than keeping a second list that would drift.

  srcs.py           the enabled Verilog sources, minus the vendor IP
  srcs.py --ip      just the vendor IP that gets replaced by sim models
  srcs.py --all     everything enabled, including the IP
  srcs.py --cst     the enabled physical constraint files (.cst)
  srcs.py --sdc     the enabled timing constraint files (.sdc)
"""

import argparse
import os
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GPRJ = os.path.join(ROOT, "tang", "test003.gprj")

# Vendor IP is replaced wholesale by sim/stubs/gowin_ip_sim.v: three of
# these files are encrypted and the rest need the Gowin primitive library.
IP_MARKERS = ("/ip/", "\\ip\\")

# Ours, but stubbed for the same reason: hdmi_serdes.v is nothing but
# rPLL, OSER10 and ELVDS_OBUF, which Verilator has no models for, and
# simulating a 250 MHz serial clock for the whole run would cost a great
# deal to watch bits that hdmi_tx.v has already decided.  The encoder
# above it is real RTL and is simulated; see sim/stubs/gowin_ip_sim.v.
STUBBED = ("src/hdmi/hdmi_serdes.v",)


def entries():
    tree = ET.parse(GPRJ)
    for f in tree.getroot().iter("File"):
        if f.get("enable") != "1":
            continue
        yield f.get("path"), f.get("type")


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--ip", action="store_true")
    g.add_argument("--all", action="store_true")
    g.add_argument("--cst", action="store_true")
    g.add_argument("--sdc", action="store_true")
    ap.add_argument("--abs", action="store_true", help="absolute paths")
    args = ap.parse_args()

    out = []
    for path, kind in entries():
        norm = path.replace("\\", "/")
        is_ip = any(m in path for m in IP_MARKERS) or norm in STUBBED
        if args.cst:
            keep = kind == "file.cst"
        elif args.sdc:
            keep = kind == "file.sdc"
        elif args.ip:
            keep = kind == "file.verilog" and is_ip
        elif args.all:
            keep = kind == "file.verilog"
        else:
            keep = kind == "file.verilog" and not is_ip
        if keep:
            full = os.path.join("tang", path)
            if args.abs:
                full = os.path.join(ROOT, full)
            if not os.path.exists(os.path.join(ROOT, "tang", path)):
                print(f"srcs.py: missing {full}", file=sys.stderr)
            out.append(full)

    print("\n".join(out))


if __name__ == "__main__":
    main()
