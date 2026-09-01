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
#   make fw          build the BL616 firmware -> build/fw/
#   make mif         ROM images -> build/mif/*.hex for the sim models
#   make flash-fpga  openFPGALoader the shipped bitstream to SRAM
#   make flash-mcu   flash the firmware over UART (COMX=/dev/ttyACM0)
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

MIFS     := $(BUILD)/mif/uknc_rom.hex $(BUILD)/mif/rawtrk.hex

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
        flash-fpga flash-fpga-flash flash-mcu help

all: lint

help:
	@sed -n '2,20p' $(firstword $(MAKEFILE_LIST)) | sed 's/^# \?//'

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

clean:
	rm -rf $(BUILD) sim/out mnano/build mnano/build_out
