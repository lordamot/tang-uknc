# Software for the machine: `soft/`

What runs *on* the УКНЦ, as opposed to what builds it.  `soft/` holds a
bootable RT-11 floppy image and four test programs for the hardware
this repository adds; `make soft-test-image` puts them together as
`build/RT11TST.DSK`, ready for the SD card.

```
soft/BASERT11.DSK   RT-11 V05.04 SJ, nothing else - the base disk
soft/MOUTST.SAV     the Kakave+ mouse test, lifted from build/moutst.dsk
soft/AYTEST.SAV     the three AY-3-8912s, one voice at a time      soft/src/aytest.mac
soft/COVTST.SAV     the Covox at 177372 and the printer port DAC    soft/src/covtst.mac
soft/RTCTST.SAV     the Kakave+ clock                               soft/src/rtctst.mac
soft/src/uknc.mac   what the three share: RT-11 requests, the PPU exchange, delays
```

The `.SAV` files are committed so that nobody needs the assembler; the
sources are the record of what they do.  `make soft` rebuilds them with
`tools/macro11` (fetched by `make toolchain`) and `tools/savlink.py`.

## The base disk

`BASERT11.DSK` is made from `build/moutst.dsk` by `tools/rt11fs.py new`,
keeping only the system: `RT11SJ.SYS`, `SWAP.SYS`, `TT.SYS`, `MZ.SYS`
(the floppy handler - the system device), `STARTS.COM`, and `PIP`,
`DUP`, `DIR`, `DATE`, `SYS`, `RESORC`.  The monitor announces itself as
`RT-11SJ (Y) V05.04 G`; the home block says `5.4G_Y2K`.  No hard-disk
handler, no mouse driver, nothing of the source disk's music players.
Plus, since 3 Sep 2026, **`UCL.SAV`** (`soft/UCL.SAV`, added with
`rt11fs.py put`): the User Command Linkage program KMON runs for a
command word it does not know and no program answers to.  This one is
the twenty-word kind from partition 0 of `build/WDC170inv_P.img` (dated
31 Dec 1999 there) - `MOV #msg,R0; .PRINT; .EXIT`, the message being
`!UCL-E-Bad command or file name` - so a typo gets that line instead of
`?KMON-F-File not found SY:UCL.SAV`.  It defines no commands of its
own; DEC's sample UCL, which kept a table of user-defined command
strings, is a different program.

Two things about how it was made that matter if it is remade:

- **Every kept file is at its original block.**  The boot block written
  by `DUP /BOOT` holds the monitor's block numbers, so `RT11SJ.SYS` at
  block 41 and `SWAP.SYS` at block 14 have to stay where they are or the
  disk stops booting.  `rt11fs.py new` keeps the source's entry order and
  turns every dropped file into an empty area, which is what keeps the
  numbers; blocks 0-5 are copied verbatim and the rest of the disk is
  zeroed.
- **`STARTS.COM` is the source disk's**: `SET TT NOSCOPE,QUIET`, `SET USR
  NOSWAP`, `SET EXIT NOSWAP`.  NOSCOPE is why a Backspace shows as `\`
  followed by the deleted character (CLAUDE.md's keyboard trap mentions
  it).  It was left alone rather than changed to SCOPE without a board
  to check the terminal's handling of the erase sequence on.

`tools/rt11fs.py` (`ls`, `get`, `put`, `rm`, `new`) is the whole of the
file-system side.  It uses DEC's status bits - permanent `002000`, empty
`001000`, end of segment `004000` - which are what these disks carry; the
sibling project's tool that this replaced had the last two swapped and
labelled the empties "tentative".  RT-11 file names are **six characters
and three**, RAD50, so `COVOXTST.SAV` was never a possible name; the
Covox test is `COVTST.SAV`.

## Running a .SAV from the OSD

Since 3 Sep 2026 the OSD's main form has **Run SAV:** under HDD 0
(`.claude/docs/mcu.md`).  It needs the base disk on the card as
`/sd/RT11BASE.DSK` (`BASERT11.DSK`, the name it has here, is accepted
too) and any number of `.SAV` files anywhere on the card, long FAT
names included.  Picking one makes `/sd/RT11SAV.DSK`: a copy of the
base, the program added under a six-character name - uppercase, RAD50
letters and digits only, the last extension dropped, `PROG` if nothing
is left, and five letters plus a digit if the base already has a file
of that name, so a program called `dir.sav` never lands on `DIR.SAV` -
and `STARTS.COM` rewritten with `R NAME` after whatever the base had in
it.  The disk goes into FDD 0 and the machine is reset, so RT-11 boots
and STARTS.COM runs the program; when it exits, the `.` prompt.

The image code is `mnano/rt11sav.c`, the same directory format as
`tools/rt11fs.py`, over two block callbacks so `make sav-test` can run
it on the host: `soft/RTCTST.SAV` under the name `Real Time Clock test
(Kakave+).SAV` becomes `REALTI.SAV` on `build/sav/RT11SAV.DSK`, reads
back identical, and STARTS.COM ends in `R REALTI`; booted in UKNCBTL
that disk goes straight into RTCTST's clock display.  On the board the
copy is 1600 sectors read and written over SPI while the OSD says
`making DSK`; how long that takes has not been measured.

## How a program reaches the hardware

Every device these programs test is on the **PPU** bus.  An RT-11
program runs on the CPU, which cannot see any of it, so each program
carries a few dozen words of PPU code and pushes them across with the
ROM's channel-2 protocol - the same one `KKVTST.MAC` in `build/rtc_kkve/`
uses, and that program ran on a real machine:

1. The CPU writes a two-word message `{address of a block, 177777}` a
   byte at a time into channel 2 (`176676`, ready in bit 7 of `176674`).
2. The block is `{result byte, command byte, 32 (= PPU memory), PPU
   address, CPU address, length in words}`.  Commands: `1` allocate
   (the ROM fills in the PPU address), `20` copy CPU→PPU, `30` call the
   code, `2` release.
3. The PPU code talks back through a mailbox in CPU memory - `MBOX`
   (the request), `MDONE` (0 → 1 when finished), `MARG` (24 words of
   arguments and results) - reached from the PPU through the window at
   `177010`/`177014`, where the **window address is the CPU byte address
   divided by two**: the CPU's RAM is planes 1 and 2 of the display
   memory, low bytes in one and high bytes in the other, one plane byte
   per CPU word.  UKNCBTL's `Memory.cpp` and KKVTST agree on that.
4. The CPU waits for `MDONE` with a tick-clock timeout (`.GTIM`, 50 Hz)
   and prints "PPU did not answer" instead of hanging.

All of that is `soft/src/uknc.mac`, with three rules the PPU side keeps:

- **It is position independent.**  The ROM decides where the code lands,
  so every reference inside it is PC-relative (macro11's default for a
  bare label) and never `#label`; a table is found with `MOV PC,R5; ADD
  #TABLE-.,R5`.  A check that no absolute relocation points into the
  blob is in the Sep 2026 prompt record and is worth repeating after any
  edit.
- **It runs at priority 7** for the whole request, because the ROM's own
  interrupt handlers use the same window register and would corrupt an
  address set between two instructions.
- **A probed address is touched only by a one-word instruction with
  register operands** (`TST (R3)`, `MOV R4,(R3)`), under a trap-4
  handler installed at PPU vector 4.  A bus timeout leaves the PC on the
  next instruction only if the instruction has no index or immediate
  word after the faulting access; `INC PPTRPF; RTI` is the handler and
  the flag says whether the address answered.  An address that does not
  answer is a timeout, not a zero.

Long-running work stays on the PPU only while it has to: the Covox
player generates its samples there (a busy loop cannot be paced from the
other processor), the AY program keeps every voice on the CPU and sends a
whole 3 × 16 register image per tick.

## The programs

**AYTEST** - chip 1 channel A, B, C, then A+B+C, then chips 2 and 3 the
same, 1.5 s each with 0.3 s of silence between, the terminal naming the
voice as it starts.  A4 440 Hz (period 252), C#5 554 Hz (200), E5 659 Hz
(168) - an A major chord together - with an eight-step vibrato of ±4 in
the period at 6.25 Hz.  Any key stops it.  The PPU side is one loop:
word write = register select, byte write = data, for 14 registers of 3
chips.

**COVTST** - probes `177372` (the Aberrant map's ЦАП, `covox.v`) and
`177100` (port A of the printer port, where the older Covox hangs) under
the trap handler, prints present/absent for each, and plays C5 E5 G5 C6
of a 256-byte sine through each one that answered, 4000 samples a note.
The sample rate is a busy loop on the PPU - about 8.4 kHz in UKNCBTL -
and the board's PPU is known to run such loops faster (the HDD delay
story in `platform.md`), so the notes are higher there; it is a test
that the port carries sound, not a tuner.  `177100` answers on every
machine because it is a register in the ВП1-120; on the Tang Nano build
a DAC is behind it only when the OSD's "Covox" says *Port 177100 LPT* or
*Both* (Sep 2026, `platform.md`), and `177372` answers only on *Port
177372* or *Both* - so which halves COVTST finds and which are heard
is the OSD setting.  Nothing but the AYs has been heard on a board.

**RTCTST** - probes the Kakave+ words `177400` and `177410`, asks the
mouse word for the RTC-installed flag (command 0) and the firmware
version (command 7), then shows `YYYY-MM-DD HH:MM:SS weekday` from
`177410`'s four selectors twice a second until a key.  Weekday 1 is
**Sunday**, as `kakave.v` and the cartridge's DS3231 library count it;
KKVTST prints 1 as Monday and is a day off on the real cartridge too.

**MOUTST** is yrust's, unchanged, from the same disk the system came
from.

## Seeing what a program does with the hardware

The quickest instrument for "it runs in the emulator and not on the
board" (3 Sep 2026, MKLAD): in a scratch copy of UKNCBTL's `emubase`,
put a call at the top of `GetPortWord`, `SetPortWord` and
`SetPortByte` of both `CFirstMemoryController` (CPU) and
`CSecondMemoryController` (PPU) that records `{side, direction,
address, PC}` in a set and prints each new combination once, switched
on by a script command after RT-11 is up.  PPU accesses with a PC
below `0100000` are the program's own PPU code; CPU accesses with a
PC below the program's high limit are its own.  The resulting list is
short - a few dozen lines for a game - and every line is a register
whose behaviour has to match `tang/src/`.  `soft/uknc-iolog.py
<workdir>` builds that runner (the first copy lived in /tmp and went
with a host restart), with `iolog`, `pputrace`, `pregs`, `disppu` and
`discpu` commands and a script that boots `build/MKLAD.DSK` into the
game.  For MKLAD the log plus a disassembly of its PPU code (a jump
table at `023666`, the timer handler at `024222`) showed a handler
that stops the timer, writes the next period and spins on `177714`
until it reads back - and, once the register model was cleared, left
the interrupt chain as the only suspect, which it was: with the chain
decision latched the game runs on the board.

## What was checked, and where

Nothing here has run on a board.  What has run is UKNCBTL - the headless
runner in `../mc0511-dicewars/tools/uknc-headless/` against its
`emubase`, in two forms:

- **Stock**, which has the AY module at `177360` and nothing at `177372`,
  `177400` or `177410`: the disk boots to the `.` prompt, `DIR` lists the
  fifteen files, COVTST says `177372: absent (bus timeout)` and plays
  through `177100` alone, RTCTST says both words are absent and exits.
  That is the trap-4 path, and the printer-port write path.
- **Patched** (a scratchpad copy, not kept): `177372` as a byte latch,
  `177100` mixed as a DAC, `177400`/`177410` answering as `kakave.v`
  does with the host's clock.  The patch is three `case` groups in
  `CSecondMemoryController::GetPortWord/SetPortByte/SetPortWord` and one
  line in `CMotherboard::DoSound` adding `(cov372 << 5) + (cov100 << 5)`
  to `value`; a debug print in `SetSoundAYReg/Val` behind an environment
  variable is the quickest way to see what a program really sends.  With
  it: AYTEST's register log is exactly the twelve-voice sequence with
  the vibrato, the WAV shows three distinct pitches per chip in the
  ratio 1 : 1.26 : 1.50 and all three in each chord (the emulator's AY
  runs about 1.26 times flat of the real 1.7734 MHz - its clock model,
  not the program); COVTST's log shows 16008 samples to each port with
  the full 28..228 swing; RTCTST prints the host's time and the right
  weekday.

Two things the emulator found on the way, both fixed and worth knowing
if a program of this shape misbehaves:

- **`?MON-F-Trap to 10` right at start** was the linker: macro11 puts
  the transfer address in a GSD entry of type 3, and RLD type 7 - which
  the sibling's `savlink.py` read as the transfer address, and this one
  copied - is a location-counter definition that happens to say 1000.
  Invisible while the entry point sat at 1000; wrong the moment the
  include file put data there first.  Same again with PC-relative
  operands: macro11 leaves them as target addresses plus RLD type-3
  entries for the linker, and a linker that only copies TXT records
  makes `MOV VAR,R1` read from the wrong place.  `tools/savlink.py`
  applies both.
- **`?MON-F-Trap to 10` on the way out** was the stack: `MOV #START,SP`
  grew it down over the include's routines.  It is a `.BLKW 128.` at the
  end of each program now.
- **Every voice on chip 1 channel A** was a register clobber (`SILENT`
  uses R1); the emulator's register log showed it in one line where the
  WAV had only said "all the same pitch".
- **`RTCTST` typed alone died, `R RTCTST` ran** (reported from the
  board, 3 Sep 2026, reproduced in UKNCBTL as `?BOOT-U-I/O error` and a
  halt).  This monitor runs a program by its bare name - a bare `PIP`
  works - but that path loads the file by the **memory-usage bitmap at
  360-377 of block 0**, one bit per 256-word block, bit 7 of byte 360 =
  block 0 (MOUTST has 376: blocks 0-6; PIP's root 377), which LINK
  writes and this linker did not.  With the map empty nothing is loaded
  and the start address is jumped to over whatever was in memory: the
  primary bootstrap still sitting at 0-777, which reread the disk,
  failed and halted.  The `R` command loads the whole file regardless,
  which is why it worked.  An unknown word that names no file goes to
  `UCL.SAV` instead (`?KMON-F-File not found SY:UCL.SAV` - it is not on
  the disk).  `savlink.py` writes the map now and all three programs
  run either way.

The board is still the only test of the hardware itself: the FPGA's AY
select/data decode, the Covox latch, the clock's protocol timing (the
three NOPs KKVTST puts after a selector write are kept), and whether the
ROM's channel-2 `30` command behaves on this PPU as it does in the
emulator.
