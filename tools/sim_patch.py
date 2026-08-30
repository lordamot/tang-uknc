#!/usr/bin/env python3
"""Make Icarus-compatible copies of the few sources it cannot parse.

tang/src/ is the author's and is never edited (.claude/rules/guideline.md),
so where Icarus Verilog is short of a SystemVerilog construct the fix is a
patched copy under build/sim/, not a change to the original.

Verilator parses every one of these files as they stand - it is only
Icarus that needs the help - so `make lint` uses Verilator on the sources
themselves and only `make sim` reads what this produces.

Each substitution below says what it is and why it is safe.  Anything not
listed here is copied through byte for byte.
"""

import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# path relative to the repo root -> list of (pattern, replacement, note)
PATCHES = {
    "tang/src/ay/ym2149.sv": [
        (
            # Icarus requires declaration before use; SystemVerilog does
            # not, and the file relies on that.  Pure reordering of
            # declarations - nothing else moves.
            r"assign ACTIVE  = ~ymreg\[7\]\[5:0\];\n"
            r"assign IOA_out = ymreg\[14\];\n"
            r"assign IOB_out = ymreg\[15\];\n"
            r"\nreg \[7:0\] addr;\n"
            r"reg \[7:0\] ymreg\[16\];\n",
            "reg [7:0] addr;\n"
            "reg [7:0] ymreg[16];\n"
            "\n"
            "assign ACTIVE  = ~ymreg[7][5:0];\n"
            "assign IOA_out = ymreg[14];\n"
            "assign IOB_out = ymreg[15];\n",
            "hoist addr/ymreg above their first use",
        ),
        (
            r"assign DO = dout;\nreg \[7:0\] dout;\n",
            "reg [7:0] dout;\nassign DO = dout;\n",
            "hoist dout above its first use",
        ),
        (
            # Icarus cannot parse an assignment pattern on an unpacked
            # array.  The loop sets the same 16 bytes to the same values;
            # ymreg[7] = 8'hFF is what '1 means for an 8-bit element.
            r"\t\tymreg\s*<=\s*'\{default:0\};\n"
            r"\t\tymreg\[7\]\s*<=\s*'1;\n"
            r"\t\taddr\s*<=\s*'0;\n",
            "\t\tfor (ivl_i = 0; ivl_i < 16; ivl_i = ivl_i + 1)\n"
            "\t\t\tymreg[ivl_i] <= 8'h00;\n"
            "\t\tymreg[7]  <= 8'hFF;\n"
            "\t\taddr      <= 8'h00;\n",
            "'{default:0} / '1 / '0 -> explicit values",
        ),
        (
            # ...and the loop needs a counter, declared beside the array.
            r"(reg \[7:0\] ymreg\[16\];\n)",
            r"\1integer ivl_i;   // added by tools/sim_patch.py\n",
            "declare the loop counter",
        ),
    ],
}


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "sim", "src")
    os.makedirs(outdir, exist_ok=True)
    written = []

    for rel, subs in PATCHES.items():
        src = os.path.join(ROOT, rel)
        if not os.path.exists(src):
            sys.exit(f"sim_patch.py: {rel} is gone - check tools/srcs.py too")
        text = open(src, encoding="utf-8", errors="surrogateescape").read()
        for pattern, repl, note in subs:
            text, n = re.subn(pattern, repl, text)
            if n == 0:
                sys.exit(
                    f"sim_patch.py: {rel}: nothing matched for {note!r}.\n"
                    "The file changed under the patch.  Re-read it and update\n"
                    "tools/sim_patch.py rather than loosening the pattern."
                )
        dst = os.path.join(outdir, os.path.basename(rel))
        open(dst, "w", encoding="utf-8", errors="surrogateescape").write(text)
        written.append(dst)

    for w in written:
        print(os.path.relpath(w, ROOT))


if __name__ == "__main__":
    main()
