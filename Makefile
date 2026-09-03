# MC0511 (UKNC) on the Tang Nano 20K.
#
# Everything this needs lives under tools/, fetched by `make toolchain`;
# nothing is installed on the host.  What can and cannot be built here is
# in .claude/docs/build.md.  Both halves build here: the bitstream through
# Gowin's headless shell, the firmware through the Bouffalo SDK, and the
# design lints and simulates besides.
#
#   make toolchain   fetch the toolchain into tools/  (~8 GB, once)
#   make lint        Verilator over the whole design - the fast check
#   make sim         run the machine, boot and all
#   make wave        the same, dumping a VCD, then open it (WAVE_MS=2)
#   make frames      the same, writing video frames as .ppm (needs 45 ms+)
#   make bitstream   build the FPGA bitstream with Gowin -> bin/tang.fs
#                    (refuses a layout that fails the timing gate)
#   make timing      the timing gate alone, on the last PnR report
#   make menu-test   the OSD menu on the host: forms, keys, layout
#   make fw          build the BL616 firmware -> build/fw/
#   make mif         ROM images -> build/mif/*.hex for the sim models
#   make flash-fpga  openFPGALoader the shipped bitstream to SRAM
#   make flash-mcu   flash the firmware over UART (COMX=/dev/ttyACM0)
#   make soft        assemble the test programs in soft/src -> soft/*.SAV
#   make soft-test-image  RT-11 + the test programs -> build/RT11TST.DSK
#   make clean       remove build/ and sim/out/

ROOT     := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
TOOLS    := $(ROOT)/tools
OSS      := $(TOOLS)/oss-cad-suite
BUILD    := $(ROOT)/build

GOWIN    := $(TOOLS)/gowin
GWSH     := $(GOWIN)/bin/gw_sh
# gw_sh ships its own Qt and its own libstdc++, and on a current Linux both
# fight the system's.  tools/fetch.sh moves the stale duplicates into
# _shadowed/; these three variables do the rest - put the bundled libraries
# first so nothing resolves half to one Qt and half to the other, point Qt
# at the bundled plugins, and run headless, since this is a console tool
# that has no business opening a window.
GWENV    := LD_LIBRARY_PATH="$(GOWIN)/lib:$(GOWIN)/bin" \
            QT_QPA_PLATFORM=offscreen \
            QT_PLUGIN_PATH="$(GOWIN)/plugins/qt"
VERILATOR:= $(OSS)/bin/verilator
YOSYS    := $(OSS)/bin/yosys
GTKWAVE  := $(OSS)/bin/gtkwave
OFL      := $(OSS)/bin/openFPGALoader
# The BL616 flasher.  It is a PyInstaller bundle inside the Bouffalo SDK
# and it needs nothing on PATH and nothing installed - an absolute path to
# it is enough.  There is one of these per host; -ubuntu is the x86-64
# Linux one, and project.build picks -arm on aarch64.
BLFLASH  := $(TOOLS)/bouffalo_sdk/tools/bflb_tools/bouffalo_flash_cube/BLFlashCommand-ubuntu
PYTHON   := python3

# The design's file list comes out of the Gowin project file, so it can
# never drift from what the IDE builds.
RTL      := $(shell $(PYTHON) $(TOOLS)/srcs.py)
STUBS    := sim/stubs/gowin_ip_sim.v sim/stubs/sdram_model.v
TB       := sim/tb/tb_top.v
SIMBIN   := $(BUILD)/sim/obj/tb_top
# A second binary, built with tracing on.  Verilator's --binary ignores
# $dumpfile/$dumpvars unless the model was generated with --trace, so
# `make wave` cannot share the fast one; and tracing costs enough that
# `make sim` should not carry it.
SIMBINW  := $(BUILD)/sim/objw/tb_top_w

# Verilator, not Icarus.  These sources use SystemVerilog assignment
# patterns and rely on declaration-after-use, and Icarus takes neither;
# Verilator reads them as they stand, so tang/src/ never has to be
# touched.  It is also about a hundred times faster, which matters when a
# video frame is a million cycles.
VFLAGS   := -Wno-fatal --timing -j 4

MIFS     := $(BUILD)/mif/uknc_rom.hex $(BUILD)/mif/rawtrk.hex $(BUILD)/mif/ide_wdrom.hex

RUN_MS   ?= 300
PPM_MAX  ?= 4
# The PPU does not release the CPU until about 45 ms, so the first frames
# are always of a machine that has not started yet.  PPM_FROM skips them.
PPM_FROM ?= 0
# A VCD of this design is about 25 MB per simulated millisecond with
# $dumpvars(0, tb_top) - and the first video frame does not end until
# 39 ms - so `wave` gets its own much shorter default.  Raise it
# deliberately: make wave WAVE_MS=40 is a gigabyte.
WAVE_MS  ?= 2

# Flashing knobs.  COMX is the BL616's bootloader port - /dev/ttyACM0 on
# a stock Linux, and the Bouffalo dock also offers /dev/m0s_debugger if
# the udev rule is installed.  2 Mbaud is what the SDK uses.
COMX     ?= /dev/ttyACM0
BAUDRATE ?= 2000000
FW_BIN   ?= bin/bl616.bin

# The BL616 firmware, and the two things it needs said about it:
#  * -DM0S_DOCK=1 picks the SPI pinout in mnano/spi.c that matches this
#    board's wiring (GPIO 12/13/10/11/14) - see README.md.
#  * CONFIG_BT_STACK_CLI=0 drops the BLE debug shell, which will not build
#    against this SDK (its cli.h is gone).  Nothing in this firmware uses
#    it.  The SDK reads extra -D's through BOARD; mnano/Makefile already
#    does the same thing for CMAKE_C_FLAGS, so nothing here is edited.
FW_BOARD := bl616dk -DCMAKE_C_FLAGS=-DM0S_DOCK=1 -DCONFIG_BT_STACK_CLI=0
FW_OUT   := mnano/build/build_out/misterynano_fw_bl616.bin

.PHONY: all toolchain lint sim wave frames fw mif clean bitstream \
        flash-fpga flash-fpga-flash flash-mcu help soft soft-test-image \
        hwen-test menu-test

all: lint

help:
	@sed -n '2,24p' $(firstword $(MAKEFILE_LIST)) | sed 's/^# \?//'

#-----------------------------------------------------------------------
# Toolchain
#-----------------------------------------------------------------------
toolchain:
	$(TOOLS)/fetch.sh

$(VERILATOR):
	@echo "toolchain missing - run: make toolchain" >&2; exit 1

#-----------------------------------------------------------------------
# ROM images.  The sim models read $readmemh hex, which a .mif is not.
#-----------------------------------------------------------------------
mif: $(MIFS)

$(BUILD)/mif/uknc_rom.hex: tang/rom/uknc_rom.mif $(TOOLS)/mif.py
	@mkdir -p $(dir $@)
	$(PYTHON) $(TOOLS)/mif.py tohex $< $@

$(BUILD)/mif/rawtrk.hex: tang/src/fdd/rom128/rawtrk.mif $(TOOLS)/mif.py
	@mkdir -p $(dir $@)
	$(PYTHON) $(TOOLS)/mif.py tohex $< $@

# The IDE cartridge ROM, for the sim stub of ide_rom.  The synthesised
# form is tang/src/ide/ide_rom.v, made from the same binary by
# tools/bin2prom.py (make ide-rom) and committed like the other ROM
# images are.
$(BUILD)/mif/ide_wdrom.hex: tang/rom/ide_wdromv0110.bin $(TOOLS)/mif.py
	@mkdir -p $(dir $@)
	$(PYTHON) $(TOOLS)/mif.py binhex $< $@

ide-rom:
	$(PYTHON) $(TOOLS)/bin2prom.py tang/rom/ide_wdromv0110.bin tang/src/ide/ide_rom.v -m ide_rom

#-----------------------------------------------------------------------
# Lint and simulation
#-----------------------------------------------------------------------
# `lint` is the cheap check to run before handing any RTL change over for
# a Gowin build: it catches the things that otherwise cost a 40-minute
# round trip - missing modules, port mismatches, bad widths, inferred
# latches.  It reports zero errors on the tree as it stands, so any error
# is yours.  It reports plenty of warnings, which are the author's.
lint: $(VERILATOR)
	$(VERILATOR) --lint-only $(VFLAGS) --top-module top $(RTL) $(STUBS)
	@echo "lint: ok"

$(SIMBIN): $(TB) $(STUBS) $(RTL) $(VERILATOR)
	@mkdir -p $(BUILD)/sim
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_top -o tb_top --Mdir $(BUILD)/sim/obj \
	  $(TB) $(STUBS) $(RTL)

$(SIMBINW): $(TB) $(STUBS) $(RTL) $(VERILATOR)
	@mkdir -p $(BUILD)/sim
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style --trace \
	  --trace-structs --trace-max-array 256 \
	  --top-module tb_top -o tb_top_w --Mdir $(BUILD)/sim/objw \
	  $(TB) $(STUBS) $(RTL)

sim: $(SIMBIN) mif
	@mkdir -p sim/out
	$(SIMBIN) +RUN_MS=$(RUN_MS)

wave: $(SIMBINW) mif
	@mkdir -p sim/out
	$(SIMBINW) +VCD +RUN_MS=$(WAVE_MS)
	@ls -la sim/out/tb_top.vcd
	$(GTKWAVE) sim/out/tb_top.vcd &

# Frames as .ppm - the only way to see the screen without a board.
# A frame is written on the vsync that ends it, so RUN_MS has to reach the
# second one: about 45 ms at the 51 Hz this generates.  They are binary P6
# at 1280x600, 2.3 MB each, and +PPM_MAX caps how many get written.
frames: $(SIMBIN) mif
	@mkdir -p sim/out
	$(SIMBIN) +VIDEO_PPM +RUN_MS=$(RUN_MS) +PPM_MAX=$(PPM_MAX) \
	  +PPM_FROM=$(PPM_FROM)
	@ls -la sim/out/*.ppm 2>/dev/null || echo "no frames produced"

# There is no `synth` target.  Yosys is in the toolchain and it was worth
# a try as a second opinion on the RTL, but it SEGFAULTS on these sources
# at read_verilog, before it gets as far as elaborating.  It could never
# have produced a bitstream anyway - dvi_tx, fifo_audio and uartfifo are
# encrypted - so the loss is only the extra front end, and Verilator's
# lint covers that.  Do not re-add the target without checking that
# `yosys -p "read_verilog -sv ..."` over $(RTL) has stopped crashing.

#-----------------------------------------------------------------------
# FPGA bitstream
#-----------------------------------------------------------------------
# gw_sh is the Gowin IDE's headless shell.  The Tcl it runs is generated
# from tang/test003.gprj, so the command-line build and the IDE build read
# the same file list and cannot drift.  The result lands where the IDE
# would put it, tang/impl/pnr/test003.fs, and is copied to bin/ - which is
# the point, since bin/ is what a user without a toolchain flashes.
bitstream:
	@test -x $(GWSH) || { \
	  echo "gowin missing - run: make toolchain" >&2; exit 1; }
	$(PYTHON) $(TOOLS)/gowin_tcl.py > tang/build.tcl
	cd tang && $(GWENV) $(GWSH) build.tcl
	@$(PYTHON) $(TOOLS)/timing_check.py || { \
	  echo "bitstream NOT copied to bin/: the layout fails the timing gate" >&2; \
	  echo "(.claude/rules/timing.md; make timing to see it again)" >&2; exit 1; }
	@cp tang/impl/pnr/test003.fs bin/tang.fs
	@echo
	@echo "bitstream: bin/tang.fs"
	@ls -l bin/tang.fs
	@echo "resources and timing:"
	@grep -iE "Timing Constraints|Logic|Register|BSRAM|PLL" \
	    tang/impl/pnr/test003.rpt.txt 2>/dev/null | head -12 || true

#-----------------------------------------------------------------------
# MCU firmware
#-----------------------------------------------------------------------
fw:
	@test -d $(TOOLS)/bouffalo_sdk || { \
	  echo "bouffalo_sdk missing - run: make toolchain" >&2; exit 1; }
	@test -x $(TOOLS)/toolchain_gcc_t-head_linux/bin/riscv64-unknown-elf-gcc || { \
	  echo "riscv toolchain missing - run: make toolchain" >&2; exit 1; }
	$(MAKE) -C mnano \
	  CROSS_COMPILE=$(TOOLS)/toolchain_gcc_t-head_linux/bin/riscv64-unknown-elf- \
	  BL_SDK_BASE=$(TOOLS)/bouffalo_sdk \
	  BOARD='$(FW_BOARD)' \
	  PATH="$(TOOLS)/cmake/bin:$(TOOLS)/bin:$$PATH"
	@mkdir -p $(BUILD)/fw
	@cp $(FW_OUT) $(BUILD)/fw/bl616.bin
	@echo
	@echo "firmware: build/fw/bl616.bin"
	@ls -l $(BUILD)/fw/bl616.bin bin/bl616.bin

#-----------------------------------------------------------------------
# Flashing.  The bitstream is the shipped one - this tree cannot build a
# new one; see .claude/docs/build.md.
#-----------------------------------------------------------------------
flash-fpga:
	$(OFL) -b tangnano20k bin/tang.fs

flash-fpga-flash:
	$(OFL) -b tangnano20k -f -r bin/tang.fs

# The BL616 flashes over its own UART bootloader.  Two things it needs
# that this Makefile cannot supply: the board has to be in boot mode
# (hold BOOT, tap RESET, release BOOT) and it has to say which port that
# put on the host.  COMX is the one thing you normally pass:
#
#   make flash-mcu COMX=/dev/ttyACM0
#   make flash-mcu COMX=/dev/ttyACM0 FW_BIN=build/fw/bl616.bin
#
# FW_BIN defaults to the shipped bin/bl616.bin, which is what a user who
# has not built anything wants; point it at build/fw/bl616.bin to flash
# what `make fw` just produced.
#
# The flasher is driven through a generated .ini rather than the SDK's own
# mnano/flash_prog_cfg.ini, because that one globs
# ./build/build_out/misterynano_fw*_bl616.bin relative to the current
# directory and so only works after a firmware build, from mnano/.  An
# absolute filedir works either way and takes no build tree.
flash-mcu:
	@test -x $(BLFLASH) || { \
	  echo "bouffalo_sdk missing - run: make toolchain" >&2; exit 1; }
	@test -f $(FW_BIN) || { \
	  echo "no firmware at $(FW_BIN)" >&2; exit 1; }
	@test -w $(COMX) || { \
	  echo "cannot write $(COMX) - is the board in boot mode, and are" >&2; \
	  echo "you in the 'dialout' group?  See .claude/docs/build.md." >&2; \
	  exit 1; }
	@mkdir -p $(BUILD)/flash
	@printf '[cfg]\nerase = 1\nskip_mode = 0x0, 0x0\nboot2_isp_mode = 0\n\n[FW]\nfiledir = %s\naddress = 0x000000\n' \
	  "$(abspath $(FW_BIN))" > $(BUILD)/flash/bl616.ini
	@echo "flashing $(abspath $(FW_BIN)) -> $(COMX)"
	$(BLFLASH) --interface=uart --baudrate=$(BAUDRATE) --port=$(COMX) \
	  --chipname=bl616 --config=$(BUILD)/flash/bl616.ini

# A unit test for the sound module alone.  The full-machine testbench has
# no SD card, so no game or player ever runs and the boot ROM never
# touches the AYs - which left the whole write path unexercised while
# three bugs in it were guessed at from the outside.  This drives the
# wishbone port the way ppu.v's core really drives it, measured with
# +BUSTRACE on the full machine.
ab-test: $(VERILATOR)
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_aberrant -Mdir $(BUILD)/sim/ab -o tb_aberrant \
	  sim/tb/tb_aberrant.v tang/src/aberrant.v tang/src/ay/ym2149.sv >/dev/null
	$(BUILD)/sim/ab/tb_aberrant

# The Covox at 0177372 beside the Aberrant: writes land, reads answer, and
# no address in 0177360-0177376 is acknowledged by both.
covox-test: $(VERILATOR)
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_covox -Mdir $(BUILD)/sim/covox -o tb_covox \
	  sim/tb/tb_covox.v tang/src/covox.v tang/src/aberrant.v tang/src/ay/ym2149.sv >/dev/null
	$(BUILD)/sim/covox/tb_covox

# The Kakave+ mouse and RTC registers at 0177400/0177410 (kakave.v) with
# hid.v in front: decode over the whole I/O page, motion, buttons, clipping,
# the command answers, the clock's set/read protocol, calendar rollover and
# weekday, the exact second, the OSD set path, reset.  sim/tb/tb_kakave.v.
kakave-test: $(VERILATOR)
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_kakave -Mdir $(BUILD)/sim/kakave -o tb_kakave \
	  sim/tb/tb_kakave.v tang/src/kakave.v tang/src/mister/hid.v >/dev/null
	$(BUILD)/sim/kakave/tb_kakave

# The keyboard byte queue in xm2-01.v: a burst of bytes at SPI speed
# against a PPU that reads slowly must come out complete and in order.
kbd-test: $(VERILATOR)
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_kbd -Mdir $(BUILD)/sim/kbd -o tb_kbd \
	  sim/tb/tb_kbd.v tang/src/xm2-01.v >/dev/null
	$(BUILD)/sim/kbd/tb_kbd

# The PPU's interrupt-vector chain, xm2-01 in front of vp1_120 as top.v
# wires them: a channel interrupt taken while a timer or key request is
# set but disabled must still get its vector (sim/tb/tb_virq.v).
virq-test: $(VERILATOR)
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_virq -Mdir $(BUILD)/sim/virq -o tb_virq \
	  sim/tb/tb_virq.v tang/src/xm2-01.v tang/src/vp1_120.v >/dev/null
	$(BUILD)/sim/virq/tb_virq

# The floppy controller before and after its re-clocking (Sep 2026): the
# old module comes out of git as fdd4_old and runs beside the new one.
fdd-test: $(VERILATOR) mif
	@mkdir -p $(BUILD)/sim/fdd
	git show 9cf04ca:tang/src/fdd/fdd4.v | sed 's/^module fdd4(/module fdd4_old(/' > $(BUILD)/sim/fdd/fdd4_old.v
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_fdd4 -Mdir $(BUILD)/sim/fdd -o tb_fdd4 \
	  sim/tb/tb_fdd4.v tang/src/fdd/fdd4.v $(BUILD)/sim/fdd/fdd4_old.v $(STUBS) >/dev/null
	$(BUILD)/sim/fdd/tb_fdd4

# The OSD's hardware switches that live in modules without a test of
# their own: the floppy controller's fdd_en (vp1-128fdd.v) and the
# printer port A read-out (vp1_120.v) that the LPT Covox mixes.
hwen-test: $(VERILATOR)
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_hwen -Mdir $(BUILD)/sim/hwen -o tb_hwen \
	  sim/tb/tb_hwen.v tang/src/vp1-128fdd.v tang/src/vp1_120.v >/dev/null
	$(BUILD)/sim/hwen/tb_hwen

# The timing gate on its own.  What it checks is in .claude/rules/timing.md.
timing:
	$(PYTHON) $(TOOLS)/timing_check.py

# The IDE cartridge alone: PPU bus in, SD request interface out, with a
# stand-in card that streams a known pattern.  sim/tb/tb_ide.v.
ide-test: $(VERILATOR) mif
	@mkdir -p $(BUILD)/sim/ide
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_ide -Mdir $(BUILD)/sim/ide -o tb_ide \
	  sim/tb/tb_ide.v tang/src/ide/ide.v $(STUBS) >/dev/null
	$(BUILD)/sim/ide/tb_ide

# The SD path arbiter between the floppies and the IDE cartridge.
sdarb-test: $(VERILATOR)
	@mkdir -p $(BUILD)/sim/sdarb
	$(VERILATOR) --binary $(VFLAGS) -Wno-lint -Wno-style \
	  --top-module tb_sdarb -Mdir $(BUILD)/sim/sdarb -o tb_sdarb \
	  sim/tb/tb_sdarb.v tang/src/ide/sd_arbiter.v >/dev/null
	$(BUILD)/sim/sdarb/tb_sdarb

#-----------------------------------------------------------------------
# Software for the machine: soft/
#-----------------------------------------------------------------------
# soft/BASERT11.DSK is RT-11 V05.04 SJ alone - the monitor, the floppy
# and terminal handlers, PIP, DUP, DIR, DATE, SYS and RESORC, plus the
# two-block UCL.SAV that turns a mistyped command into a message - made
# from build/moutst.dsk by tools/rt11fs.py new, which keeps every file
# at its original block so the boot block stays right, and one put.
# soft/*.SAV are the test programs, MOUTST.SAV lifted from that same disk
# and the other three assembled from soft/src/ (make soft, needs the
# macro11 that make toolchain fetches).  soft-test-image puts them all on
# a copy of the base disk: build/RT11TST.DSK, ready for the SD card.
MACRO11  := $(TOOLS)/macro11/macro11
SOFTSRC  := aytest covtst rtctst
SOFTSAVS := $(foreach s,$(SOFTSRC),soft/$(shell echo $(s) | tr a-z A-Z).SAV)
SOFTALL  := soft/MOUTST.SAV $(SOFTSAVS)

soft: $(SOFTSAVS)

$(BUILD)/soft/%.obj: soft/src/%.mac soft/src/uknc.mac
	@test -x $(MACRO11) || { \
	  echo "macro11 missing - run: make toolchain" >&2; exit 1; }
	@mkdir -p $(BUILD)/soft
	cd soft/src && $(MACRO11) -o $(abspath $@) -l $(abspath $(BUILD)/soft/$*.lst) $*.mac

# soft/AYTEST.SAV from build/soft/aytest.obj: make's pattern rules cannot
# change case, so one rule per program.
define SOFT_LINK
soft/$(shell echo $(1) | tr a-z A-Z).SAV: $(BUILD)/soft/$(1).obj $(TOOLS)/savlink.py
	$(PYTHON) $(TOOLS)/savlink.py $$< $$@
endef
$(foreach s,$(SOFTSRC),$(eval $(call SOFT_LINK,$(s))))

soft-test-image: $(BUILD)/RT11TST.DSK

$(BUILD)/RT11TST.DSK: soft/BASERT11.DSK $(SOFTALL) $(TOOLS)/rt11fs.py
	@mkdir -p $(BUILD)
	cp soft/BASERT11.DSK $@
	@for f in $(SOFTALL); do \
	  $(PYTHON) $(TOOLS)/rt11fs.py put $@ $$(basename $$f) $$f || exit 1; done
	$(PYTHON) $(TOOLS)/rt11fs.py ls $@

# The OSD's "Run SAV:" image maker (mnano/rt11sav.c) built for the host
# over plain files: the base disk plus one .SAV under a long FAT name
# becomes build/sav/RT11SAV.DSK, listed back by rt11fs.py.  The same
# code writes the card on the BL616; this is the only place it can be
# watched.
sav-test: soft/BASERT11.DSK soft/RTCTST.SAV $(TOOLS)/rt11fs.py
	@mkdir -p $(BUILD)/sav
	$(CC) -O1 -Wall -Wextra -DRT11SAV_HOST -o $(BUILD)/sav/rt11sav mnano/rt11sav.c
	cp soft/RTCTST.SAV "$(BUILD)/sav/Real Time Clock test (Kakave+).SAV"
	$(BUILD)/sav/rt11sav soft/BASERT11.DSK "$(BUILD)/sav/Real Time Clock test (Kakave+).SAV" $(BUILD)/sav/RT11SAV.DSK
	$(PYTHON) $(TOOLS)/rt11fs.py ls $(BUILD)/sav/RT11SAV.DSK | grep -E "REALTI|STARTS"
	$(PYTHON) $(TOOLS)/rt11fs.py get $(BUILD)/sav/RT11SAV.DSK REALTI.SAV $(BUILD)/sav/back.sav
	cmp $(BUILD)/sav/back.sav soft/RTCTST.SAV
	$(PYTHON) $(TOOLS)/rt11fs.py get $(BUILD)/sav/RT11SAV.DSK STARTS.COM $(BUILD)/sav/starts.com
	@grep -a -q "^R REALTI" $(BUILD)/sav/starts.com && echo "sav-test: ok"

# The OSD menu on the host (mnano/menu_test.c): menu.c with its SDL host
# switch, u8g2 drawing into a bitmap, FatFs with no card, the core and
# the SD layer stubbed.  Walks every UKNC form with the keys usb_host.c
# sends, asserts what the core was told and where the cursor landed, and
# leaves every screen it looked at under build/menu/ as text and as PNG.
FATFS_SRC := $(TOOLS)/bouffalo_sdk/components/fs/fatfs
MENU_TEST_SRC := mnano/menu_test.c mnano/menu.c \
  $(wildcard mnano/u8g2/csrc/*.c) mnano/u8g2/sys/bitmap/common/u8x8_d_bitmap.c \
  $(FATFS_SRC)/ff.c $(FATFS_SRC)/ffunicode.c
menu-test: $(MENU_TEST_SRC) mnano/menu.h VERSION
	@test -d $(FATFS_SRC) || { echo "bouffalo_sdk missing - run: make toolchain" >&2; exit 1; }
	@mkdir -p $(BUILD)/menu
	rm -f $(BUILD)/menu/*.txt $(BUILD)/menu/*.png
	@$(CC) -O1 -w -DSDL -DUKNC_VERSION='"$(shell head -1 VERSION)"' \
	  -Imnano -Imnano/u8g2/csrc -I$(FATFS_SRC) -o $(BUILD)/menu/menu_test $(MENU_TEST_SRC)
	$(BUILD)/menu/menu_test $(BUILD)/menu
	$(PYTHON) $(TOOLS)/osd_png.py $(BUILD)/menu/*.txt

clean:
	rm -rf $(BUILD) sim/out mnano/build mnano/build_out
