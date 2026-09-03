# The machine

The МС0511 **УКНЦ** ("educational computing network complex", 1987) is a
two-processor PDP-11-compatible machine.  Everything
below is read out of the RTL in `tang/src/`, not out of a reference manual,
so where the implementation departs from the real machine it is the
implementation that is written down here.  Where a detail was inferred
rather than read, it says so.

## The two processors

Both are **К1801ВМ2** cores, and both are the same Verilog: `wm2wb/vm2_wb.v`
(the sequencer and bus interface, ~2000 lines) driven by `wm2wb/vm2_plm.v`
(the microcode PLA, ~800 lines).  They differ only in the wrapper around
them and in the address decode that wrapper does.

| | central processor | peripheral processor |
|---|---|---|
| wrapper | `cpu.v` (`cpu_wb`) | `ppu.v` (`ppu_wb`) |
| instance | `cpu1` | `ppu1` |
| clock | `clk4` - rPLL CLKOUTD, ≈4.18 MHz | `clk_3_12` - `horz[3]`, ≈3.13 MHz |
| own RAM | none; all through the window | 32 KB, `0000000-0077777` |
| job | the user program | screen, keyboard, floppies, sound, timer |

The PPU owns every peripheral.  The CPU reaches none of them directly: it
talks to the PPU over the channel (below), and it reaches memory only
through a two-register window.

## CPU address space (`cpu.v`)

```
0000000-0157777   RAM, straight through to the SDRAM arbiter
0160000-0177777   I/O
```

The I/O decode looks at **only `adr[9:1]`**, so every 1 KB page from
0160000 up aliases onto the same registers - `0176640`, `0177640` and
`0160640` all hit the same place.  Peripherals (`vp1_120`, `vp65`) decode
more of the address and ack for themselves; what `cpu.v` handles itself is:

| address | what `cpu.v` does |
|---|---|
| `0176560`-`0176576` | acks, reads back 0 - stubs, `adr[9:1]` = `'o270`-`'o277` |
| `0176640` | `R176640` - address latch into shared RAM |
| `0176642` | `R176642` - data; a write posts to RAM at `R176640`, a read fetches from it |

`wbm_adr_o` is 17 bits.  When `adr[16]` is set the access goes to RAM
regardless of the rest, which is how the core's own vector fetches get out.

## PPU address space (`ppu.v`)

Decoded on `adr[15:9]`:

```
0000000-0077777   RAM (32 KB, the PPU's own)
0100000-0117777   overlay: ROM if R177054[0], else RAM read if R177054[4],
                  else the ROM cartridge in slot R177054[3], bank R177054[2:1]
0120000-0137777   ROM
0140000-0157777   ROM
0160000-0176777   ROM
0177000-0177777   I/O
```

`R177054` is the mapping register and the only thing that moves the
boundary: bit 0 selects ROM over the `0100000` window, bit 4 enables the
RAM read underneath it, bits 2:1 name a cartridge bank (1..3) and bit 3 a
slot when neither bit 0 nor bit 4 is set, bit 8 forces the event line, bit
9 gates the CPU's timer (`pin_tmr_ena_o` out to `cpu.v`).  It resets to
`10'o1401`.  Cartridge mode is exported as `pin_cart_sel_o`/`_bank_o`
for the IDE cartridge below, and in that mode a write to the window no
longer falls through to the RAM behind it (it did for every mode until
Sep 2026; in cartridge mode it would be an IDE register write landing in
RAM at `0110000`+ as well).

Inside `0177000-0177777` the PPU's own registers are selected on
`adr[8:1]`:

| address | register | role |
|---|---|---|
| `0177010` | `R177010` | video/RAM address latch |
| `0177012` | `R177012` | byte data at that address |
| `0177014` | `R177014` | word data at that address |
| `0177016` | `R177016` | plane select (3 bits) |
| `0177020` | `R177020` | colour register, low half |
| `0177022` | `R177022` | colour register, high half |
| `0177024` | - | read: fetches the plane data at `R177010` into `R177020/22` |
| `0177026` | `R177026` | plane select for readback (3 bits) |
| `0177054` | `R177054` | mapping / control, see above |
| `0177030`-`0177052` | - | ack and read as 0 (`adr[8:1]` `'o14`..`'o25`) |

The colour and plane logic proper is in `mkcolorreg.v`: `mkcolorg`
(instance `mc1`) turns a byte plus the plane registers into the four-bit
per-pixel write, and `rd_plan` (`mc2`) does the reverse for `0177024`.

## The channel (КР1801ВП1-120, `vp1_120.v`)

One module, two bus ports, because the part sits between the two
processors.  Three channels; each is a pair of one-byte registers with a
status word on each side.

| | CPU side | PPU side |
|---|---|---|
| channel 0 | `0177560` sos, `0177562` data (CPU→ receiver), `0177564` sos, `0177566` data (transmitter) | `0177060` data, `0177066` status |
| channel 1 | `0176660`, `0176662`, `0176664`, `0176666` | `0177062` data, `0177066` status |
| channel 2 | `0176674` sos, `0176676` data | `0177064` data, `0177066` status |

`0177076` is the PPU-side status for the CPU-directed channels; `0177066`
for the PPU-directed ones.  `P177076[2]` masks channel 0 on the CPU side
entirely - when it is set the CPU's accesses to `0177560`-`0177566` are
**not acked**, which on a 1801 is a bus timeout.

CPU-side interrupt vectors, taken straight from the RTL:

```
060  channel 0 receiver     460  channel 1 receiver
064  channel 0 transmitter  464  channel 1 transmitter
                            474  channel 2 transmitter
```

`vp1_120.v` also carries four 8-bit ports `portA`/`portB`/`portC`/`portW`
on the PPU side at `0177100`/`0177102` (`adr[6:1]` = `'o40`/`'o41`), byte
selected by `adr[0]`.

## System registers (МХ2-01, `xm2-01.v`)

Chip-selected by `&adr[15:6]`, i.e. **`0177700`-`0177777`**, decoded on
`adr[5:1]`:

| address | register | role |
|---|---|---|
| `0177700` | `R177700` | keyboard control; bit 6 enables the key interrupt |
| `0177702` | `R177702` | keyboard scan code, 8 bits |
| `0177710` | `R177710` | timer control: bit 0 run, bits 2:1 prescale, bit 3 overflow-seen, bit 4, bit 6 IRQ enable, bit 7 zero |
| `0177712` | `R177712` | timer reload, 12 bits |
| `0177714` | `R177714` | timer count, 12 bits, read-only |
| `0177716` | `R177716` | system: bit 4 → HALT, bit 5 → DCLO, bit 15 → ACLO (inverted), bit 7 beeper enable, bits 12:8 beeper tone select |

`R177716` resets to `16'o40`, i.e. DCLO asserted - this is what holds the
CPU in reset until the PPU releases it.  **The PPU boots the CPU**, not the
other way round.  `pin_vm_dclo_o`/`pin_vm_aclo_o`/`pin_vm_halt_o` from this
module are wired straight to `cpu1`'s reset inputs in `top.v`.

The one-bit beeper (`sound`) is generated here from `R177716[12:8]`
selecting among 8 kHz / 1 kHz / 500 Hz / 250 Hz / 60 Hz, ANDed together;
with all five zero and bit 7 set the line is simply held high.  It is
summed with the AY output in `top.v` and shown on `leds[1]`.

**Real software never uses those five bits.**  Over 234 seconds of a
running machine - boot screen, keypresses, a game playing beeper music -
the diagnostic monitor saw `R177716` take four values and no others:
`100000`, `100020`, `100200`, `100220`.  Bits 15, 4 and 7; never one of
`[12:8]`.  The music is made by toggling **bit 7** in a timing loop, 177 to
473 writes per 100 ms window, which is a square wave of 885 to 2365 Hz.  So
the divider chain is dead code as far as anything that actually runs is
concerned, and `sound` follows bit 7 directly.  Worth knowing before
spending time on the tone logic: the interesting path is the write rate,
not the dividers.

## Keyboard

There is no PS/2 and no matrix scan in the live build.  `hid.v` receives a
byte from the BL616 over SPI and hands it to `xm2-01.v` as `but_data`; the
module latches it into `R177702` and raises the key interrupt.  So the
translation from USB HID to УКНЦ scan code happens **on the MCU**, in
`mnano/uknc.h` - see `.claude/docs/mcu.md`.

An older PS/2 keyboard path (`tang/src/ps2/`) was in the tree, outside
the project, until Sep 2026.

## Serial (КР1801ВП1-065, `vp65.v`)

Chip-selected on `adr[16:3] == 'o17657`, i.e. **`0176570`-`0176576`**:
receiver status/data at `0176570`/`0176572`, transmitter status/data at
`0176574`/`0176576`.  Bit 6 of either status word is the interrupt enable.
It drives the board's `uart_tx`/`uart_rx` pins through `uart/uart_rx.v` and
`uart/uart_tx.v` with a `uartfifo` IP FIFO in between.

## Floppy (`vp1-128fdd.v` + `fdd/fdd4.v`)

`vp1-128fdd.v` is the controller as the PPU sees it, chip-selected on
`adr[15:2] == 14'o37626`, i.e. **`0177130`-`0177136`** - `0177130` data and
`0177132` control.  It speaks a raw MFM-ish stream: `motor`, `step`, `dir`,
`head`, `drive`, and back `valid`, `sync`, `crc_ok`, `rdy`, `tr0`, `ind`.

`fdd/fdd4.v` is the drive: it fakes the rotation (25 MHz in, 3125 16-bit
words a revolution, one word every 64 µs, 1600 counts a track) and fetches
the sectors from the SD card through the MisterNano `sd_card`/`sd_rw`
blocks.  Four drives, `mount_dsk[3:0]`.  Write protection comes from the
OSD through `system_floppy_wprot`.

Image geometry: **819200 bytes = 1600 sectors of 512** - 80 tracks, 2
sides, 10 sectors of 512.  The older scheme, `load.v`, had the same
number as `204800` 32-bit words per image and stacked four images back to
back in RAM; it was never instantiated and left the tree in Sep 2026.

## Hard disk (`ide/ide.v`, `ide/ide_rom.v`)

Oleg H.'s IDE controller for the УКНЦ ("КНЖМД"), a ROM cartridge with the
drive's registers inside its address space, exactly as UKNCBTL emulates
it (`emubase/Hard.cpp`, `Board.cpp`, `Memory.cpp` - the reference for
every number here).  Added Sep 2026.  It occupies **cartridge slot 1**
and exists only while an image is mounted on SD slot 4 (the OSD's
"HDD 0:"); with none mounted the slot is empty and the window times out.

```
0100000-0107777   ROM bank R177054[2:1] - 1 of tang/rom/ide_wdromv0110.bin
                  (24 KB = three 8 KB banks; tools/bin2prom.py -> ide_rom.v)
0110000-0117777   the IDE registers, shadowing the upper 4 KB of every bank
                  while the disk is attached, index = ~adr[3:1]:
  0110016  data        0110014  error / precomp   0110012  sector count
  0110010  sector no.  0110006  cylinder low      0110004  cylinder high
  0110002  head        0110000  status / command
```

**Every word on the bus is inverted**, both ways: a register reads as
`{8'h00, ~value}`, a written value is `~bus[7:0]`.  Sector data is
inverted once more when the image is stored "inverted" - a raw dump of a
real drive, which holds `~software`; the MCU detects that from the
image's first sector (bytes `0x1f0`-`0x1fb` all `0xff`, or the `0xAB56`
signature of an "HD type" image) and sends it as SYS value `'I'` with the
geometry `'S'` (sectors/track) and `'H'` (heads) before the INSERTED
notice.  The net effect is that software always sees its own view of
the disk whichever way the image is stored - the same rule for the same
reason as in the emulator.  The detection is a heuristic (twelve bytes of
sector 0 all `0xff`), so the OSD's Drives menu has "HDD image:
Auto|Plain|Inverted" (`'J'`) to overrule it; the first image tried on
the board (2 Sep 2026) booted the WD ROM and was refused as a wrong boot
sector, which is what a wrong form looks like.

Commands: `20`/`21` read, `30`/`31` write (multi-sector through the
sector count, CHS advanced as `NextSector()` does), `91` set config
(sectors/track and heads from the registers, overriding the mounted
values), `EC` identify (the emulator's block, model "UKNC Nano Hard
Disk", cylinders from the MCU as file size / 512 / spt / heads, sent as
`'C'` low and `'Y'` high byte).  **IDENTIFY reaches the software
COMPLEMENTED, whatever form the image is in** - that is the bus
inverting the drive's own words, and the software knows it: WDINIT's
identify loop (`build/wdinit.dsk`, `MOV #177423,(R4)` then `MOV (R5),R0;
COM R0`) complements every word it reads, while its sector reads store
the words as they come.  A build that put identify on the bus plain
made WDINIT print 64555, 65525, 65501 - the complements of 980, 10 and
34.  The WD ROM does read IDENTIFY: `build/clue.txt`, a real-hardware
note, says the home block's geometry bytes have to match what the drive
reports or the boot fails, so the cylinder count has to be real too
(2 Sep 2026).  The Drives menu's "HDD prot." (`'K'`) makes writes fail
with ERROR and BAD_SECTOR, as the emulator does for a read-only image,
and leaves the card untouched.
Status `50` after reset, `58` with data ready.  Addressing is CHS and the
sector number on the SD path is `(cyl * heads + head) * spt + sector -
1`, computed in two multiply stages in the cartridge - **or LBA28** when
bit 6 of the head register is set (`0340` written to `0110002`): then
`{head[3:0], cyl, sector}` is the sector number itself, and a
multi-sector read counts it up in the registers.  The WD ROM and RT-11
use CHS; blairecas/badapple's hard-disk version reads its video by LBA,
and the emulator it ships is UKNCBTL with "LBA28 support for IDE
emulation" added - the stock Hard.cpp, which this cartridge was built
from, is CHS only and reads the wrong sectors, which on the board was
coloured vertical stripes and silence (Sep 2026).  A multi-sector read
is **read ahead**: the cartridge has two sector banks and fetches the
next sector while the software drains the current one, so a
drain-and-poll loop sees DRQ again at once - badapple takes its Covox
samples out of the sector stream in that loop, and without the
read-ahead every sector was a gap in the sound.  And every read of the
data register can be stretched: the OSD's **HDD delay** (`'D'`, 0-975
us in 25 us steps, default 750) is the extra time per 256-word sector,
dealt out over the reads as a fraction of a PPU cycle each, so a
program streaming sound from its sectors is slowed uniformly - for
badapple the board sounds right at 750, the default, which is well
past the 205 the emulator's timing predicted - with no gap
between sectors (a per-sector hold was tried and heard as a 461 Hz
modulation dulling the voice).  Images are `.img`,
raw 512-byte sectors, geometry in sector 0 as the WD driver writes it.

**Three incompatible hard-disk layouts exist for the УКНЦ**, and
`rt11dsk` (ukncbtl-utils) tells them apart: **WD** - bytes 0 and 1 of the
home block are sectors/track and sides, words 1..23 the partition sizes,
partitions laid out one after another from block 1, a checksum over the
block, `wdwaittime`/`wdhidden` at `0122`/`0124`; **HD** - signature
`54A9 FFEF FEFF` (or its complement), geometry in words 4 and 5,
partitions at cylinder boundaries from words 6..; **HZ** - 32 MB
partitions, no home block.  This ROM is the WD driver's: its boot block
is disk block 1, and an image in either other layout, or a WD image with
no system on its first partition, is refused with "wrong boot sector"
after the home block has been read correctly - and so does a correct WD
image if IDENTIFY disagrees with its home block.  WDINIT itself only
initialises drives reporting 16 heads and 63 sectors - CF cards - and
says so; it is not needed to boot an existing image.  `rt11dsk hi`
complements every byte of an image and nothing else, which is the
"inverted" form; `build/WDC170inv_P.img`, despite its name, is plain
(34 sectors, 10 heads, 980 cylinders, checksum words at `0x1fc`).

The cartridge shares `sd_card.v`'s one request interface with the four
floppies, and the MCU picks the drive out of a one-hot mask, so
`ide/sd_arbiter.v` grants the path to one owner at a time: the cartridge
gets it when it asks with no floppy request up and the card idle, keeps
it until the card reports done, and while it owns the floppies' request
bits are masked and `fdd4.v` holds back (`sd_taken`); the sector number,
the write data and the incoming-byte strobe all follow the owner.  The
first version muxed by "who is pending" and let both be visible for a
cycle or two, and on the board that put WDINIT's home block into block
21 of the image - the floppy's sector number for the track RT-11 was
reading at that moment (`make sdarb-test`).  Not bounds-checked: a CHS
beyond the image reads whatever the card holds past the file.

`sim/tb/tb_ide.v` (`make ide-test`) drives the bus and a stand-in card
through every command above and checks each word against Hard.cpp's
conventions.  **On the board since 2 Sep 2026**: WDINIT partitions an
empty image, RT-11 installs on WD0: and boots from the cartridge.

## Sound (`aberrant.v`)

**Three** `YM2149` instances (`ym2149.sv`), modelling the three AY-3-8912s
of the real Aberrant sound module - `aberranthacker/aberrant_sound_module`,
which is where the file gets its name.  Until Aug 2026 only two were built
and the third was a data path stubbed to zero.

The board's map.  The real module answers **only** the three AY word
addresses; this implementation answers those and, since Sep 2026, the
ЦАП at `0177372` (`covox.v`, below):

| | | | |
|---|---|---|---|
| `0177360` AY1 | `0177362` AY2 | `0177364` AY3 | `0177366` unused |
| `0177370` MIDI data | `0177372` ЦАП (Covox) | `0177374` YM3812 (OPL2) | `0177376` unused |

`0177366`-`0177377` are decoded onto the expansion connector P2 on the real
board, so apart from the ЦАП nothing must answer there - a bus timeout is
how software learns the MIDI and the OPL2 are absent.  The decode used to
leave `adr[3]` don't-care, which aliased `0177372` onto AY2 and `0177374`
onto AY3.

### The Covox (`covox.v`)

The "new covox" UKNC players probe for - blairecas/badapple: "~24kHz
8-bit mono covox output (LPT port A 177100 or new covox 177372 if
detected)" - is the Aberrant map's ЦАП.  No data sheet was found; the
interface is read out of the players (Sep 2026): a device is detected by
`TST @#177372` under a trap-4 handler, so reads are acknowledged and
answer with the last sample in the low byte; a sample is written as the
low byte of a `MOV` (spcplay's PPU loop is `mov R0,(R2)`) or as a `MOVB`,
and both land - a word or a byte to `0177372` takes the low byte, a byte
to `0177373` the high byte.  Mono, unsigned, 0..255, not inverted: the
bus and the printer port are inverted on the machine and UKNCBTL's Covox
on `0177100` XORs with 0xff, but polarity is inaudible on a DAC.  The
sample enters `top.v`'s mixer shifted up five (0..8160, one AY chip's
swing and a bit) and goes to HDMI and I²S with the rest.  `make
covox-test` (`sim/tb/tb_covox.v`) checks the writes, the read-back, and
that no address in `0177360`-`0177376` is acknowledged by both it and the
Aberrant.  The older Covox on the printer port `0177100` is **not**
implemented: `vp1_120.v`'s port A is a plain register there.


**A word write latches an AY register number; a byte write sends data to
it.**  `aberrant.v` turns that into the chips' BDIR/BC pair, which is why
`nwtbt` is `&sel`.  The chips are clocked by a phase accumulator at
1.773355 MHz, the AY-3-8912's specified 1.7734 MHz within 45 Hz, **with
`SEL` low**.  `ym2149.sv`'s `SEL` picks the prescaler - 0 divides the
enable by 8, as the chip does, 1 by 16 for a core fed at twice the chip
clock - and it was high until Sep 2026, so every tone was an octave low
and every envelope ran at half speed: period 252 played 220 Hz, not 440.
That, not the HDMI path, was the missing bass - a bass line an octave down
is 30-60 Hz, below a television speaker.  Before the phase accumulator the
chips free-ran at the 3.1339 MHz PPU clock, which through the same
divide-by-16 was 12% flat, not the 1.77 times sharp that was written down.

`sim/tb/tb_aberrant.v` (`make ab-test`) drives the wishbone port the way
`ppu.v`'s core really drives it and checks all three chips take registers,
produce a tone, and produce it at the right pitch - 880 edges a second for
period 252.  The full-machine testbench cannot: it has no SD card,
so no game or player ever runs and the boot ROM never touches the AYs.

**The mix is mono, at one level, and unipolar on purpose.**  `m_channel` -
all nine channels summed - shifted up three, plus the beeper at bit 13, is
26552 at most, inside the 32767 a signed sample allows.  `system_volume`
only divides that down; it must never scale up, which is what it did until
Aug 2026, when 100% multiplied by four and clamped, so the volume setting
changed which parts of the mix were audible rather than how loud they were.

The sum is still **unipolar** - 0 upwards, quiescent at exactly zero -
and until 1 Sep 2026 that was justified by measurement alone.  A DC
blocker was written for it in Aug 2026, on the sound reasoning that nine
unipolar channels carry an offset that the volume control then scales;
the offset is real and was measured at +3000 under one chip's music.  But
on the operator's television only the raw sum played:

| samples | quiescent | result |
|---|---|---|
| raw sum, 0..N | 0 | **plays** |
| raw sum minus a constant 512 | -512, dips negative | silent |
| DC blocked, bipolar | 0, dips negative | silent |
| DC blocked plus 8192, never negative | 8192 | silent |

and the blocker was removed on 31 Aug 2026 with the cause written up as
unknown.  The cause was `hdmi_tx.v`'s audio subpacket layout, which put
sample bits 15:12 where a sink reads the left channel's V, U, C and P
flags (see `.claude/docs/fpga.md` and the trap in `CLAUDE.md`).  Every
silent row has bit 15 or bit 14 set at some point and the playing row
never does; nor does one chip (peak 6120) or two (12240), while three at
once (18360) reach bit 14 and mute, which was the symptom that found it.
The beeper's "16384 mutes, 8192 does not" is the same bit.

So the raw sum is kept for one more build as the known-playing form, with
the layout fix the only change; then the blocker (`git show f2bb44b^`)
should go back, because its motive was never wrong.  The beeper stays at
8192 until then.  At 33% the beeper is -24 dBFS and inaudible.

## Mouse and real-time clock (`kakave.v`)

The **Kakave+** cartridge (yrust, oshwlab.com/yrust/uknz_kakave_mouse_rtc_ide;
its attachments are in `build/rtc_kkve/`) is a CPLD and an ATmega324 on
the PPU bus carrying a PS/2 mouse and a DS3231 clock, beside the same IDE
interface as the cartridge above.  The mouse and clock half is
implemented in `kakave.v` since Sep 2026: two words on the PPU bus, the
protocol read out of the sketch (`kakave_m_ide_rtc_v3_6.ino`) and the
three RT-11 programs beside it (KKVTST, KKVRTC, KKVDTS).  Nothing in the
boot ROM touches them, and the cartridge is a real product on real
machines, so acknowledging the two addresses changes nothing that ran
before.

| address | role |
|---|---|
| `0177400` | mouse: read motion, or write a command and read its answer |
| `0177410` | RTC: write a selector, then read a pair or write a field |

**The mouse.**  A read returns `[dy7..1 L dx7..1 R]`: the motion since
the previous read as two signed 7-bit counts, each clipped to ±63, the
left button in bit 8 and the right in bit 0 - the current button state,
not an event.  The counts are in the **PS/2 sense, Y up is positive**,
which is why KKVTST does `sub R1, MouY`; a USB report has Y down
positive and `kakave.v` negates it.  A read clears the counts.  A write
leaves a command whose answer the next read returns in place of motion:
0 → `0001` (RTC present), 1 → `00AA` (a standard PS/2 mouse) if a USB
mouse is attached and `0000` if not, 7 → `3336` (the sketch's version
"3.6"), anything else is echoed.  KKVTST's sequence is write 7 / read,
write 0 / read, write 1 / read, then the motion loop once per vsync.

The report comes from the BL616: `usb_host.c` sends every USB mouse
report over SPI as buttons, dx, dy (HID target, command 2), `hid.v`
hands one report at a time to `kakave.v` with a toggle, and the counts
accumulate there on the PPU clock until the machine reads them.  Whether
a mouse is attached is `sysctrl.v`'s `'M'`, sent by the MCU when the
number of mice changes.

**The clock.**  A write of 0..3 selects what the next reads return -
0 `{minutes, seconds}`, 1 `{weekday, hours}`, 2 `{month, date}`, 3 the
year (e.g. 2026) - all binary, 24-hour, months 1..12.  A write of 4..7
makes the next write the data for one field - 4 year, 5 `{month, date}`,
6 hours, 7 `{minutes, seconds}`; the sketch's comments say otherwise, its
code does this and KKVRTC agrees - and the clock loads when all four have
been given, seconds restarting at that instant.  Other selectors are
ignored.  **The weekday is 1 = Sunday .. 7 = Saturday**, which is what the
sketch's `microDS3231::getWeekDay()` computes; the bundled RT-11 programs
print index 1 as "Monday", so on the real cartridge the printed name is
one day off, and `kakave.v` follows the hardware rather than the printout.

There is no battery anywhere on this board and no time source on the
BL616, so the calendar counts in the FPGA on the PPU clock and starts
from whatever the MCU sends at power-up: the OSD's **Clock** form
(`menu.c`; letters `'y'` year-2020, `'m'` month-1, `'d'` date-1, `'h'`
hours, `'n'` minutes, applied one field at a time, minutes also zeroing
the seconds) has its values saved with the rest of the settings and
re-sent at every start, so a saved date is the power-on date.  The
machine's own KKVRTC sets the same clock from RT-11's date and time and
KKVDTS reads it back into RT-11.  The second is exact by construction:
the PPU clock is 27 MHz × 13 / 7 / 16, so seven seconds are 21937500 of
its cycles, and `kakave.v` adds 7 per cycle and takes a second every
21937500 - the crystal is the only error.  Neither the PPU reset nor a
cold boot touches the time.  Leap years are `year % 4` (right until
2100).

`make kakave-test` (`sim/tb/tb_kakave.v`) drives `hid.v` and `kakave.v`
together: the decode over the whole I/O page (only `0177400/1` and
`0177410/1` answer), motion, buttons, clipping, the command answers, the
four-field set and the read-back, 28 Feb into 29 Feb in 2024 and into 1
Mar in 2023, the year end, the weekday against known dates, seven
seconds counted as exactly 21937500 clocks, the OSD set path, and that a
reset clears a pending command and leaves the time.  It takes about
three minutes, most of it the seven seconds.
