## Shared BL616 companion

The firmware for UKNC, PK8000, Korvet, ZS-256 and BK now has one implementation
in the sibling `../tang-ultima` repository. `make fw`, direct `make -C mnano`
and CMake all use it. `COMPANION_ROOT=/path/to/tang-ultima` selects another
checkout. No per-core compiler switches are used.

`bin/bl616.bin` is the same shipped image in all five repositories;
`make fw` writes the new image to `build/fw/bl616.bin`. `make flash-mcu`
uses the shipped image by default and refuses stale binaries after a newer
build. To flash a fresh build, pass `FW_BIN=build/fw/bl616.bin`.

`make card` collects the common JSON profiles, bitstreams and all five
machines' assets into this repository's `build/card/`. It preserves existing
staged media. Copy the staged contents to the card root, preserving your
saved settings and writable images. `make card-config` stages JSON only.
JSON edits take effect after restarting the dock; firmware rebuilding is
needed for protocol changes. See `../tang-ultima/config/README.md`.

`make menu-test`, `make config-check` and `make storage-test` exercise the
actual shared companion. Local C files remain as historical references for
machine-specific regression tests; they are not separate firmware builds.
The FPGA build and machine code are unchanged. The new shared firmware is
host-tested, not yet verified on a board.
