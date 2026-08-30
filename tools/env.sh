# Source this to put the vendored toolchain on PATH.
#
#   . tools/env.sh
#
# Nothing here is installed on the host; everything lives under tools/,
# fetched by tools/fetch.sh.  The Makefile does this for itself, so this
# file is only needed for running the tools by hand.

_TANG_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"

export PATH="$_TANG_ROOT/tools/bin:$PATH"
export PATH="$_TANG_ROOT/tools/cmake/bin:$PATH"
export PATH="$_TANG_ROOT/tools/toolchain_gcc_t-head_linux/bin:$PATH"

# oss-cad-suite ships its own environment script: it sets PATH plus the
# library and Python paths its binaries need.  Prefer it over adding
# tools/oss-cad-suite/bin to PATH by hand, which leaves yosys unable to
# find its share/ directory.
if [ -f "$_TANG_ROOT/tools/oss-cad-suite/environment" ]; then
    . "$_TANG_ROOT/tools/oss-cad-suite/environment"
fi

export BL_SDK_BASE="$_TANG_ROOT/tools/bouffalo_sdk"
export CROSS_COMPILE="$_TANG_ROOT/tools/toolchain_gcc_t-head_linux/bin/riscv64-unknown-elf-"

unset _TANG_ROOT
