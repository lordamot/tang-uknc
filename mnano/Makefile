# The companion implementation and JSON profiles live in tang-ultima.
SIBLING_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
COMPANION_ROOT ?= $(abspath $(SIBLING_ROOT)/../tang-ultima)
.DEFAULT_GOAL := build
.PHONY: build fw ninja flash test sdl_menu_test clean term size
build fw ninja:
	$(MAKE) -C "$(SIBLING_ROOT)" fw COMPANION_ROOT="$(COMPANION_ROOT)"
	@mkdir -p "$(SIBLING_ROOT)/mnano/build/build_out"
	cp "$(SIBLING_ROOT)/build/fw/bl616.bin" "$(SIBLING_ROOT)/mnano/build/build_out/misterynano_fw_bl616.bin"
flash:
	$(MAKE) -C "$(SIBLING_ROOT)" flash-mcu COMPANION_ROOT="$(COMPANION_ROOT)"
test sdl_menu_test:
	$(MAKE) -C "$(SIBLING_ROOT)" menu-test COMPANION_ROOT="$(COMPANION_ROOT)"
size:
	$(MAKE) -C "$(COMPANION_ROOT)/mnano" size
term:
	term.sh $(COMX) $(BAUDRATE)
clean:
	rm -rf "$(SIBLING_ROOT)/mnano/build"
