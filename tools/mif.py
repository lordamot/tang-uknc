#!/usr/bin/env python3
"""Convert between flat binaries, Gowin/Altera .mif files and $readmemh hex.

This replaces the opaque committed `bin2mif` binary (see
.claude/docs/tools.md): that one has no source, so nobody can say what its
arguments are.  This one is fifteen lines of parsing and does both
directions.

  mif.py tohex  in.mif  out.hex           .mif -> one hex word per line
  mif.py tomif  in.bin  out.mif -w 16     flat binary -> .mif
  mif.py tobin  in.mif  out.bin           .mif -> flat binary
  mif.py binhex in.bin  out.hex           flat binary -> hex, 16-bit LE words

`tohex` is what the simulation models use: $readmemh cannot read a .mif,
which carries a header and `addr : data;` syntax.
"""

import argparse
import re
import sys

RADIX = {"HEX": 16, "BIN": 2, "OCT": 8, "DEC": 10, "UNS": 10}


def read_mif(path):
    """Return (width, depth, list-of-ints).  Missing cells come back as 0."""
    text = open(path, encoding="utf-8", errors="replace").read()
    # Strip both comment forms before anything else.
    text = re.sub(r"--[^\n]*", "", text)
    text = re.sub(r"%.*?%", "", text, flags=re.S)

    def header(key, default=None):
        m = re.search(rf"\b{key}\s*=\s*([A-Za-z0-9_]+)\s*;", text, re.I)
        if m:
            return m.group(1)
        if default is None:
            sys.exit(f"{path}: no {key} in header")
        return default

    width = int(header("WIDTH"))
    depth = int(header("DEPTH"))
    arad = RADIX[header("ADDRESS_RADIX", "HEX").upper()]
    drad = RADIX[header("DATA_RADIX", "HEX").upper()]

    body = re.search(r"CONTENT\s+BEGIN(.*?)\bEND\b", text, re.I | re.S)
    if not body:
        sys.exit(f"{path}: no CONTENT BEGIN .. END block")

    mem = [0] * depth
    for stmt in body.group(1).split(";"):
        stmt = stmt.strip()
        if not stmt:
            continue
        addr_part, _, data_part = stmt.partition(":")
        if not _:
            sys.exit(f"{path}: cannot parse entry {stmt!r}")
        value = int(data_part.strip(), drad)
        for chunk in addr_part.split(","):
            chunk = chunk.strip()
            rng = re.fullmatch(r"\[\s*(\w+)\s*\.\.\s*(\w+)\s*\]", chunk)
            if rng:
                lo, hi = int(rng.group(1), arad), int(rng.group(2), arad)
                if lo > hi:
                    lo, hi = hi, lo
                span = range(lo, hi + 1)
            else:
                span = [int(chunk, arad)]
            for a in span:
                if not 0 <= a < depth:
                    sys.exit(f"{path}: address {a} outside DEPTH {depth}")
                mem[a] = value
    return width, depth, mem


def write_mif(path, width, mem):
    digits = (width + 3) // 4
    with open(path, "w") as f:
        f.write(f"WIDTH = {width};\nDEPTH = {len(mem)};\n\n")
        f.write("ADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\n\nCONTENT BEGIN\n")
        for a, v in enumerate(mem):
            f.write(f"{a:04X} : {v:0{digits}X};\n")
        f.write("END;\n")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("mode", choices=["tohex", "tomif", "tobin", "binhex"])
    ap.add_argument("infile")
    ap.add_argument("outfile")
    ap.add_argument("-w", "--width", type=int, default=16,
                    help="bits per word, for tomif (default 16)")
    ap.add_argument("-d", "--depth", type=int,
                    help="pad or truncate to this many words, for tomif")
    ap.add_argument("--big-endian", action="store_true",
                    help="for tomif/tobin: word bytes are big-endian")
    args = ap.parse_args()

    if args.mode == "tohex":
        width, depth, mem = read_mif(args.infile)
        digits = (width + 3) // 4
        with open(args.outfile, "w") as f:
            for v in mem:
                f.write(f"{v:0{digits}X}\n")
        print(f"{args.infile}: {depth} words of {width} bits -> {args.outfile}")
        return

    order = "big" if args.big_endian else "little"

    if args.mode == "binhex":
        nbytes = args.width // 8
        data = open(args.infile, "rb").read()
        data += b"\0" * ((-len(data)) % nbytes)
        digits = (args.width + 3) // 4
        with open(args.outfile, "w") as f:
            for i in range(0, len(data), nbytes):
                v = int.from_bytes(data[i:i+nbytes], order)
                f.write(f"{v:0{digits}X}\n")
        print(f"{args.infile}: {len(data)//nbytes} words of {args.width} bits -> {args.outfile}")
        return

    if args.mode == "tomif":
        if args.width % 8:
            sys.exit("--width must be a whole number of bytes")
        nbytes = args.width // 8
        data = open(args.infile, "rb").read()
        if len(data) % nbytes:
            data += b"\0" * (nbytes - len(data) % nbytes)
        mem = [int.from_bytes(data[i:i + nbytes], order)
               for i in range(0, len(data), nbytes)]
        if args.depth:
            mem = (mem + [0] * args.depth)[:args.depth]
        write_mif(args.outfile, args.width, mem)
        print(f"{args.infile}: {len(mem)} words of {args.width} bits -> {args.outfile}")
        return

    width, depth, mem = read_mif(args.infile)
    if width % 8:
        sys.exit(f"{args.infile}: WIDTH {width} is not a whole number of bytes")
    nbytes = width // 8
    with open(args.outfile, "wb") as f:
        for v in mem:
            f.write(v.to_bytes(nbytes, order))
    print(f"{args.infile}: {depth} words of {width} bits -> {args.outfile}")


if __name__ == "__main__":
    main()
