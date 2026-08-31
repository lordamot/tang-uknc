# Tools and ROM data

The toolchain is fetched into `tools/` and driven from the `Makefile`;
`.claude/docs/build.md` says what builds here and what does not.  Beside
that there is a handful of small scripts, one opaque committed binary, and
a pile of ROM data.

## `tools/`

Nothing here is installed on the host and none of it is committed -
`tools/` is in `.gitignore` and `make toolchain` (`tools/fetch.sh`) puts
it back, about 8 GB of it: oss-cad-suite (Verilator, Yosys, GTKWave,
openFPGALoader), CMake, Ninja, the T-Head RISC-V GCC, the Bouffalo SDK and
**Gowin EDA Education**, which is the half that builds the bitstream.
`tools/env.sh` puts the same set on `PATH` for use by hand.

What *is* committed is the six scripts:

| script | what |
|---|---|
| `fetch.sh` | fetches the above, patches the SDK's host-tool selection, and shadows Gowin's stale bundled libraries |
| `srcs.py` | prints the design's source list, read out of `tang/test003.gprj` |
| `gowin_tcl.py` | emits the `gw_sh` build script, from the same `.gprj` |
| `mif.py` | converts between flat binaries, `.mif` and `$readmemh` hex |
| `sim_patch.py` | Icarus-compatible copies of the sources it cannot parse |
| `dbgmon.py` | reads and names the board's diagnostic serial line |

`srcs.py` is the one that matters most: the Gowin project file is the
source of truth for what gets built, so lint and simulation read it rather
than keeping a second file list that would drift out of date.  `--ip`
lists just the vendor IP (which `sim/stubs/gowin_ip_sim.v` replaces),
`--all` includes it, `--cst` gives the constraint files.

`dbgmon.py` is the host end of `src/dbg/dbgmon.v`, which is not in the
build as of 31 Aug 2026 - the tool only has something to read once the
monitor is instantiated again.  It finds the port by
`/dev/serial/by-id/*if01*`, not by `ttyUSBn` - that number changes every
time the board re-enumerates, and hardcoding it cost a test run.  It drops
malformed lines rather than guessing at them, so a magic word mismatch
shows up as missing lines and never as wrong numbers.

`sim_patch.py` is **not** on any live path.  Verilator parses every source
in this tree as it stands, so `make sim` reads `tang/src/` directly; the
script is what an Icarus flow would need, kept because it documents which
three constructs Icarus chokes on.  If Verilator is ever the problem
rather than the answer, start there.

## `bin2mif`

A committed **x86-64 ELF binary** (16120 bytes, March 2023, not stripped),
present three times over as `tang/rom/bin2mif`, `tang/rom128/bin2mif` and
`tang/src/fdd/rom128/bin2mif` - identical copies.  There is no source for
it in the repository.

It turns a flat binary into a Gowin/Altera `.mif`:

```
WIDTH = 16;
DEPTH = 16384;
ADDRESS_RADIX = HEX;
DATA_RADIX = HEX;
CONTENT BEGIN
0000 : 0977;
...
```

Since there is no source, do not assume its arguments.  **`tools/mif.py`
replaces it** and does both directions - `tomif` from a flat binary,
`tobin` back, and `tohex` for the `$readmemh` the simulation models need,
which a `.mif` is not (it carries a header and `addr : data;` syntax).
Prefer it over guessing at an undocumented binary.

## ROM and data files

### `tang/rom/`

| file | what |
|---|---|
| `uknc_rom.mif` | the machine's ROM, 16384 words of 16 bits |
| `uknc_rom_orig.bin` | 32256 bytes, the binary it came from |
| `font8.bin` / `font8.mif` / `font8x8.mif` | the 8x8 font |
| `osd.txt` | OSD text |
| `rawtrk.dat` / `rawtrk.mif` | the raw-track template |
| `status.dat` / `status.mif`, `stat_sw.dat` / `stat_sw.mif` | sector status tables |
| `rom/1/`, `rom/2/` | earlier `rawtrk` revisions |

`uknc_rom_orig.bin` is 32256 bytes and `uknc_rom.mif` is 16384 words - so
the `.mif` is not a straight conversion of that `.bin`; something was added
or rearranged.  Whatever did that is not in the repository.

### `tang/rom128/` and `tang/src/fdd/rom128/`

Identical pairs: `rawtrk.bin` (722 bytes) and `rawtrk.mif` (361 words).
The second copy is the one next to the IP that reads it -
`fdd/ip/rawtr_prom/` initialises from it, and that IP is what
`fdd/fdd4.v` uses to synthesise a track image.

**Which `.mif` an IP core actually reads is recorded in its `.ipc`/`.mod`,
not in any Verilog.** `grep` for `.mif` under `tang/src/ip/` and
`tang/src/fdd/ip/` to find out, and change it there rather than swapping
files around.

## What is missing and would be worth having

- An `.sdc` for the FPGA project (see `.claude/docs/fpga.md`) - the single
  most valuable thing that could be added, and the only one of the three
  originally listed here that is still open.  A `.mif` writer and a
  Makefile now exist.
