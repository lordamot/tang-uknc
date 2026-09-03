#!/usr/bin/env python3
"""rt11fs.py - a small RT-11 volume tool for the УКНЦ floppy images.

    rt11fs.py ls   IMAGE
    rt11fs.py get  IMAGE NAME.EXT OUTFILE
    rt11fs.py put  IMAGE NAME.EXT INFILE      (replaces an existing NAME.EXT)
    rt11fs.py rm   IMAGE NAME.EXT
    rt11fs.py new  SRC DST NAME.EXT...        (a fresh volume from SRC's boot
                                               blocks and the named files,
                                               each kept at its block)

The format is the one in the RT-11 Volume and File Formats manual: block 1
is the home block, word 0724 of it names the first directory segment
(block 6 on every disk seen here), a segment is two blocks with a five-word
header (segments available, next segment, highest in use, extra bytes per
entry, first data block) followed by 14-byte entries - status, three RAD50
words of name and type, length in blocks, a job/channel byte pair and a
date - until one carrying E.EOS.  Status bits are DEC's:

    E.TENT 000400   E.MPTY 001000   E.PERM 002000   E.EOS 004000

Files lie one after another in entry order from the header's first data
block, empties included, which is why "new" can keep a file where it was:
the boot block written by DUP /BOOT holds the monitor's block numbers, so
RT11SJ.SYS and SWAP.SYS have to stay put or the disk stops booting.

Only the first directory segment is written by "new"; "put" walks the
chain and needs one free entry in the segment that holds the empty it
splits.  Nothing here allocates a new segment.
"""

import argparse
import datetime
import struct
import sys

BLOCK = 512
E_TENT, E_MPTY, E_PERM, E_EOS = 0o400, 0o1000, 0o2000, 0o4000
HB_FIRST_DIR = 0o724
ENTRY = 14

RAD50 = " ABCDEFGHIJKLMNOPQRSTUVWXYZ$.?0123456789"


def r50_enc(s):
    s = s.upper().ljust(3)[:3]
    v = 0
    for c in s:
        i = RAD50.find(c)
        if i < 0:
            raise SystemExit(f"not a RAD50 character: {c!r}")
        v = v * 40 + i
    return v


def r50_dec(v):
    out = ""
    for _ in range(3):
        out = RAD50[v % 40] + out
        v //= 40
    return out


def split_name(name):
    name = name.upper()
    base, _, ext = name.partition(".")
    if len(base) > 6 or len(ext) > 3 or not base:
        raise SystemExit(f"bad RT-11 file name: {name}")
    return r50_enc(base[:3]), r50_enc(base[3:6]), r50_enc(ext)


def rt11_date(d=None):
    d = d or datetime.date.today()
    y = d.year - 1972
    return ((y >> 5) << 14) | (d.month << 10) | (d.day << 5) | (y & 31)


class Entry:
    __slots__ = ("status", "n1", "n2", "ext", "length", "jc", "date",
                 "extra", "block", "seg", "index")

    @property
    def name(self):
        return (r50_dec(self.n1) + r50_dec(self.n2)).rstrip() + "." + r50_dec(self.ext).rstrip()

    def pack(self):
        return struct.pack("<7H", self.status, self.n1, self.n2, self.ext,
                           self.length, self.jc, self.date) + self.extra


class Volume:
    def __init__(self, path):
        self.path = path
        self.img = bytearray(open(path, "rb").read())
        if len(self.img) % BLOCK:
            raise SystemExit(f"{path}: not a whole number of blocks")
        self.nblocks = len(self.img) // BLOCK
        self.dir_start = struct.unpack_from("<H", self.img, BLOCK + HB_FIRST_DIR)[0]
        if not 1 < self.dir_start < self.nblocks:
            self.dir_start = 6

    def seg_off(self, seg):
        return (self.dir_start + 2 * (seg - 1)) * BLOCK

    def read_dir(self):
        """All entries of all segments, each with its data block filled in."""
        entries, headers = [], {}
        seg = 1
        while seg:
            off = self.seg_off(seg)
            hdr = struct.unpack_from("<5H", self.img, off)
            headers[seg] = list(hdr)
            extra = hdr[3]
            blk = hdr[4]
            p = off + 10
            i = 0
            while p + ENTRY <= off + 2 * BLOCK:
                e = Entry()
                (e.status, e.n1, e.n2, e.ext, e.length, e.jc, e.date) = \
                    struct.unpack_from("<7H", self.img, p)
                e.extra = bytes(self.img[p + ENTRY:p + ENTRY + extra])
                e.block, e.seg, e.index = blk, seg, i
                entries.append(e)
                if e.status & E_EOS:
                    break
                blk += e.length
                p += ENTRY + extra
                i += 1
            seg = hdr[1]
        return headers, entries

    def write_segment(self, seg, hdr, entries):
        off = self.seg_off(seg)
        extra = hdr[3]
        room = (2 * BLOCK - 10) // (ENTRY + extra)
        if len(entries) > room:
            raise SystemExit(f"directory segment {seg} full ({room} entries)")
        buf = bytearray(2 * BLOCK)
        struct.pack_into("<5H", buf, 0, *hdr)
        p = 10
        for e in entries:
            buf[p:p + ENTRY + extra] = e.pack()[:ENTRY + extra].ljust(ENTRY + extra, b"\0")
            p += ENTRY + extra
        self.img[off:off + 2 * BLOCK] = buf

    def save(self, path=None):
        open(path or self.path, "wb").write(self.img)

    def find(self, name):
        n1, n2, ext = split_name(name)
        for e in self.read_dir()[1]:
            if e.status & E_PERM and (e.n1, e.n2, e.ext) == (n1, n2, ext):
                return e
        return None

    # -- commands ---------------------------------------------------------
    def ls(self):
        headers, entries = self.read_dir()
        print(f"{self.path}: {self.nblocks} blocks, directory at block {self.dir_start}, "
              f"{headers[1][0]} segments, {headers[1][2]} in use")
        used = free = 0
        for e in entries:
            if e.status & E_EOS:
                break
            kind = "PERM" if e.status & E_PERM else "MPTY" if e.status & E_MPTY else \
                   "TENT" if e.status & E_TENT else f"{e.status:06o}"
            if e.status & E_PERM:
                used += e.length
                y = (e.date & 31) + ((e.date >> 14) << 5) + 1972
                date = f"{e.date >> 5 & 31:02d}.{e.date >> 10 & 15:02d}.{y}" if e.date else ""
                print(f"  {e.name:<12} {e.length:5d} blocks at {e.block:5d}  {date}")
            else:
                free += e.length
                print(f"  {'<' + kind + '>':<12} {e.length:5d} blocks at {e.block:5d}")
        print(f"  {used} blocks used, {free} free")

    def get(self, name, out):
        e = self.find(name)
        if not e:
            raise SystemExit(f"{name}: not found on {self.path}")
        data = self.img[e.block * BLOCK:(e.block + e.length) * BLOCK]
        open(out, "wb").write(data)
        print(f"{name}: {e.length} blocks from block {e.block} -> {out}")

    def rm(self, name, quiet=False):
        e = self.find(name)
        if not e:
            if quiet:
                return
            raise SystemExit(f"{name}: not found on {self.path}")
        headers, entries = self.read_dir()
        seg = [x for x in entries if x.seg == e.seg]
        seg[e.index].status = E_MPTY
        self.write_segment(e.seg, headers[e.seg], self._coalesce(seg))

    @staticmethod
    def _coalesce(seg):
        out = []
        for e in seg:
            if out and e.status & E_MPTY and out[-1].status & E_MPTY:
                out[-1].length += e.length
            else:
                out.append(e)
        return out

    def put(self, name, infile):
        data = open(infile, "rb").read()
        need = (len(data) + BLOCK - 1) // BLOCK
        self.rm(name, quiet=True)
        headers, entries = self.read_dir()
        for e in entries:
            if e.status & E_MPTY and e.length >= need:
                break
        else:
            raise SystemExit(f"{name}: no free area of {need} blocks on {self.path}")
        seg = [x for x in entries if x.seg == e.seg]
        n = Entry()
        n.status = E_PERM
        n.n1, n.n2, n.ext = split_name(name)
        n.length, n.jc, n.date = need, 0, rt11_date()
        n.extra = b"\0" * headers[e.seg][3]
        rest = e.length - need
        e.length = rest
        i = seg.index(e)
        seg[i:i + 1] = [n] + ([e] if rest else [])
        self.write_segment(e.seg, headers[e.seg], seg)
        start = e.block * BLOCK
        self.img[start:start + need * BLOCK] = data.ljust(need * BLOCK, b"\0")
        print(f"{name}: {need} blocks at block {e.block} <- {infile}")

    def new(self, dst, keep):
        """A fresh volume: SRC's boot and home blocks, a one-segment
        directory holding only the named files, each at its original
        block, everything else empty and zeroed."""
        headers, entries = self.read_dir()
        want = {split_name(k) for k in keep}
        hdr = headers[1]
        out, found = [], set()
        for e in entries:
            if e.status & E_EOS:
                break
            key = (e.n1, e.n2, e.ext)
            if e.status & E_PERM and key in want:
                found.add(key)
                out.append(e)
            else:
                m = Entry()
                m.status, m.length, m.jc, m.date = E_MPTY, e.length, 0, 0
                m.n1, m.n2, m.ext = split_name("EMPTY.FIL")
                m.extra = b"\0" * hdr[3]
                m.block = e.block
                out.append(m)
        missing = want - found
        if missing:
            raise SystemExit("not on the source volume: " +
                             ", ".join(r50_dec(a) + r50_dec(b) + "." + r50_dec(c)
                                       for a, b, c in missing))
        # the tail, up to the end of the disk, then the end marker
        last = out[-1]
        end = last.block + last.length
        if end < self.nblocks:
            t = Entry()
            t.status, t.length, t.jc, t.date = E_MPTY, self.nblocks - end, 0, 0
            t.n1, t.n2, t.ext = split_name("EMPTY.FIL")
            t.extra = b"\0" * hdr[3]
            t.block = end
            out.append(t)
        out = self._coalesce(out)
        eos = Entry()
        eos.status, eos.n1, eos.n2, eos.ext, eos.length, eos.jc, eos.date = E_EOS, 0, 0, 0, 0, 0, 0
        eos.extra = b"\0" * hdr[3]
        out.append(eos)
        # zero everything that is not kept, directory blocks included
        img = bytearray(len(self.img))
        first_data = hdr[4]
        img[:self.dir_start * BLOCK] = self.img[:self.dir_start * BLOCK]
        for e in out:
            if e.status & E_PERM:
                s, n = e.block * BLOCK, e.length * BLOCK
                img[s:s + n] = self.img[s:s + n]
        self.img = img
        self.write_segment(1, [hdr[0], 0, 1, hdr[3], first_data], out)
        self.save(dst)
        print(f"{dst}: {len(found)} files kept from {self.path}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("ls"); p.add_argument("image")
    p = sub.add_parser("get"); p.add_argument("image"); p.add_argument("name"); p.add_argument("out")
    p = sub.add_parser("put"); p.add_argument("image"); p.add_argument("name"); p.add_argument("infile")
    p = sub.add_parser("rm"); p.add_argument("image"); p.add_argument("name")
    p = sub.add_parser("new"); p.add_argument("src"); p.add_argument("dst"); p.add_argument("keep", nargs="+")
    a = ap.parse_args()
    if a.cmd == "new":
        Volume(a.src).new(a.dst, a.keep)
        return
    v = Volume(a.image)
    if a.cmd == "ls":
        v.ls()
    elif a.cmd == "get":
        v.get(a.name, a.out)
    elif a.cmd == "put":
        v.put(a.name, a.infile); v.save()
    elif a.cmd == "rm":
        v.rm(a.name); v.save()


if __name__ == "__main__":
    main()
