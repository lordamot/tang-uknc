#!/usr/bin/env python3
"""savlink.py - MACRO-11 object file -> RT-11 .SAV, for one absolute module.

    savlink.py IN.obj OUT.sav [--stack ADDR]

Enough of a linker for a program that is a single .ASECT at a fixed
origin, which is what soft/src/*.mac are: the TXT records are laid into a
memory image, the RLD records are applied - macro11 leaves every
PC-relative operand as the target address plus a "displaced internal
relocation" entry, so a linker that only copies TXT records makes `MOV
VAR,R1` fetch from the wrong place, silently - the transfer address is
the GSD entry of type 3 that .END writes (NOT RLD type 7, which is a
location-counter definition and happens to say 1000), and block 0 gets
the words RT-11's R
command reads - 40 start, 42 initial stack, 50 high limit - filled the way
LINK fills them (checked against MOUTST.SAV, linked by the real thing).
No globals, no libraries, no second section: those are errors.
"""

import argparse
import struct
import sys

T_GSD, T_ENDGSD, T_TXT, T_RLD, T_ISD, T_ENDMOD = 1, 2, 3, 4, 5, 6
RLD_SIZE = {1: 4, 2: 6, 3: 4, 4: 6, 5: 8, 6: 8, 7: 8, 8: 4, 9: 4,
            0o10: 6, 0o12: 2, 0o13: 6, 0o14: 8, 0o15: 8}


def records(blob):
    i, n = 0, len(blob)
    while i < n:
        while i < n and blob[i] == 0:
            i += 1
        if i >= n:
            return
        if blob[i] != 1 or blob[i + 1] != 0:
            raise SystemExit(f"bad record framing at {i}")
        length = blob[i + 2] | blob[i + 3] << 8
        yield blob[i + 4], bytes(blob[i + 6:i + length])
        i += length + 1


def link(obj, sav, stack=None):
    blob = open(obj, "rb").read()
    mem = bytearray(0o1000)
    transfer = None
    high = 0
    txt_addr = None
    for t, p in records(blob):
        if t == T_GSD:
            for j in range(0, len(p) - 7, 8):
                if p[j + 5] == 3:                       # transfer address
                    transfer = p[j + 6] | p[j + 7] << 8
        elif t == T_TXT and len(p) > 2:
            addr = p[0] | p[1] << 8
            data = p[2:]
            if addr < 0o1000:
                raise SystemExit(f"{obj}: text below 1000 at {addr:o}")
            end = addr + len(data)
            if end > len(mem):
                mem.extend(b"\0" * (end - len(mem)))
            mem[addr:end] = data
            high = max(high, end)
            txt_addr = addr
        elif t == T_RLD:
            j = 0
            while j < len(p):
                et = p[j] & 0o177
                byte_mode = p[j] & 0o200
                if et in (1, 3):
                    # internal relocation, plain or displaced: the word in
                    # the last TXT record at (displacement - 4) is the
                    # target address; displaced means PC-relative to the
                    # word after it.  Section base is 0 in an .ASECT.
                    at = txt_addr + p[j + 1] - 4
                    value = p[j + 2] | p[j + 3] << 8
                    if et == 3:
                        value = (value - (at + 2)) & 0xFFFF
                    if byte_mode:
                        mem[at] = value & 0xFF
                    else:
                        struct.pack_into("<H", mem, at, value)
                elif et in (7, 8, 9, 0o12):
                    pass                                  # location counter, limits
                else:
                    raise SystemExit(f"{obj}: RLD entry type {et} (a global or a "
                                     f"relocatable section) - not a single .ASECT")
                j += RLD_SIZE.get(et, 4)
        elif t == T_ENDMOD:
            break
    if transfer is None:
        raise SystemExit(f"{obj}: no transfer address (.END START)")
    struct.pack_into("<H", mem, 0o40, transfer)
    struct.pack_into("<H", mem, 0o42, stack if stack is not None else transfer)
    struct.pack_into("<H", mem, 0o50, (high - 1) | 1)
    # The memory-usage bitmap at 360-377: one bit per 256-word block of
    # memory, MSB of byte 360 = block 0 (MOUTST.SAV, high 6712, has 376 =
    # blocks 0-6; PIP's root, 0-7777, has 377), set for every block the
    # image occupies, block 0 included.  The R command loads the file
    # without it; typing the program's name at the prompt loads by this
    # map, and with it zero, or in the other bit order, the program is
    # not in memory when its start address is jumped to.
    for blk in range(0, (high - 1) // 512 + 1):
        mem[0o360 + blk // 8] |= 0x80 >> (blk % 8)
    mem.extend(b"\0" * (-len(mem) % 512))
    open(sav, "wb").write(mem)
    print(f"{sav}: {len(mem) // 512} blocks, start {transfer:o}, high {high - 1:o}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("obj")
    ap.add_argument("sav")
    ap.add_argument("--stack", type=lambda s: int(s, 8),
                    help="initial SP, octal (default: the start address)")
    a = ap.parse_args()
    link(a.obj, a.sav, a.stack)


if __name__ == "__main__":
    main()
