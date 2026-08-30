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
0100000-0117777   overlay: ROM if R177054[0], else RAM read if R177054[4]
0120000-0137777   ROM
0140000-0157777   ROM
0160000-0176777   ROM
0177000-0177777   I/O
```

`R177054` is the mapping register and the only thing that moves the
boundary: bit 0 selects ROM over the `0100000` window, bit 4 enables the
RAM read underneath it, bit 8 forces the event line, bit 9 gates the CPU's
timer (`pin_tmr_ena_o` out to `cpu.v`).  It resets to `10'o1401`.

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

## Keyboard

There is no PS/2 and no matrix scan in the live build.  `hid.v` receives a
byte from the BL616 over SPI and hands it to `xm2-01.v` as `but_data`; the
module latches it into `R177702` and raises the key interrupt.  So the
translation from USB HID to УКНЦ scan code happens **on the MCU**, in
`mnano/uknc.h` - see `.claude/docs/mcu.md`.

`tang/src/ps2/` is an older PS/2 path and is not in the project.

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
sides, 10 sectors of 512.  `load.v` (not instantiated; see
`.claude/docs/fpga.md`) has the same number as `204800` 32-bit words per
image and stacks four images back to back in RAM, which is the older
load-into-RAM scheme.

## Sound (`aberrant.v`)

Two `YM2149` instances (from `ay/ym2149.sv`), plus a third data path
stubbed to zero.  Left, right and mono outputs; `top.v` uses the mono one,
adds the МХ2-01 beeper, scales it by `system_volume` from the OSD, and
sends it through `fifo_audio` to `audio.v` (`audio_drive`), which is an I²S
transmitter on `HP_BCK`/`HP_WS`/`HP_DIN`.

**The chip select in `aberrant.v` is not what its comment says.**  See the
trap list in `CLAUDE.md`; the decode resolves to `0177360`-`0177366` and
`0177370`-`0177376`, with a full alias at `0177760`-`0177776` that lands
inside МХ2-01's range.
