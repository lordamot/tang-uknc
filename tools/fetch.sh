#!/bin/bash
# Fetch the project toolchain into tools/.  Everything lands under this
# repository; nothing is installed on the host.  Re-running is cheap: each
# step skips if its target already exists.
#
# About 5 GB on disk when it is done.  tools/ is in .gitignore.
set -u
cd "$(dirname "$0")/.."
ROOT="$PWD"
DL="$ROOT/tools/dl"
T="$ROOT/tools"
log(){ echo "[fetch] $*"; }
have(){ [ -e "$1" ]; }

mkdir -p "$DL" "$T/bin"

OSS_URL=https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2026-08-29/oss-cad-suite-linux-x64-20260829.tgz
CMAKE_URL=https://github.com/Kitware/CMake/releases/download/v3.31.6/cmake-3.31.6-linux-x86_64.tar.gz
NINJA_URL=https://github.com/ninja-build/ninja/releases/download/v1.13.2/ninja-linux.zip

# The Bouffalo SDK's master branch has moved on from what this firmware
# was written against in 2024: struct usbh_hid lost report_desc and
# usbh_initialize() grew arguments, so mnano/usb_host.c will not compile.
# master_legacy still carries the old CherryUSB API.  Its history does not
# reach back to 2024 either, so this is the closest thing to the right
# vintage that can still be fetched.
SDK_BRANCH=master_legacy

# 1. oss-cad-suite: yosys, nextpnr, iverilog, verilator, gtkwave, openFPGALoader
if have "$T/oss-cad-suite/bin/verilator"; then log "oss-cad-suite present"; else
  log "downloading oss-cad-suite (741 MB)"
  curl -fL --retry 3 -o "$DL/oss-cad-suite.tgz" "$OSS_URL" || exit 1
  log "extracting oss-cad-suite"
  tar -C "$T" -xzf "$DL/oss-cad-suite.tgz" || exit 1
fi

# 2. cmake.  The SDK bundles its own, but having one on PATH keeps the
#    sub-invocations in project.build happy.
if have "$T/cmake/bin/cmake"; then log "cmake present"; else
  log "downloading cmake"
  curl -fL --retry 3 -o "$DL/cmake.tgz" "$CMAKE_URL" || exit 1
  mkdir -p "$T/cmake"
  tar -C "$T/cmake" --strip-components=1 -xzf "$DL/cmake.tgz" || exit 1
fi

# 3. ninja
if have "$T/bin/ninja"; then log "ninja present"; else
  log "downloading ninja"
  curl -fL --retry 3 -o "$DL/ninja.zip" "$NINJA_URL" || exit 1
  unzip -o -q -d "$T/bin" "$DL/ninja.zip" || exit 1
  chmod +x "$T/bin/ninja"
fi

# 4. T-Head RISC-V toolchain - the one mnano/run_make expects by name
if have "$T/toolchain_gcc_t-head_linux/bin/riscv64-unknown-elf-gcc"; then
  log "riscv toolchain present"
else
  log "cloning toolchain_gcc_t-head_linux"
  git clone --depth 1 https://github.com/bouffalolab/toolchain_gcc_t-head_linux.git \
      "$T/toolchain_gcc_t-head_linux" || exit 1
fi

# 5. Bouffalo SDK, pinned to the branch with the API this firmware uses
if have "$T/bouffalo_sdk/CMakeLists.txt"; then log "bouffalo_sdk present"; else
  log "cloning bouffalo_sdk ($SDK_BRANCH)"
  git clone --depth 1 --branch "$SDK_BRANCH" \
      https://github.com/bouffalolab/bouffalo_sdk.git \
      "$T/bouffalo_sdk" || exit 1
fi

# 6. Patch the SDK's host-tool selection.
#
# cmake/bflb_flash.cmake picks the suffix for its host tools - the thing
# that turns the .elf into a flashable .bin - from CMAKE_SYSTEM_NAME.
# That is the TARGET system, and for a bare-metal RISC-V cross build it is
# always "Generic", so the stock SDK reaches for bflb_fw_post_proc.exe on
# every host and the build dies with "Exec format error" after linking.
# The suffix has to come from CMAKE_HOST_SYSTEM_NAME.
FLASH_CMAKE="$T/bouffalo_sdk/cmake/bflb_flash.cmake"
if [ -f "$FLASH_CMAKE" ]; then
  if grep -q 'CMAKE_HOST_SYSTEM_NAME.*Windows' "$FLASH_CMAKE"; then
    log "sdk host-tool patch already applied"
  else
    log "patching sdk host-tool selection"
    python3 - "$FLASH_CMAKE" <<'PY' || exit 1
import sys
p = sys.argv[1]
s = open(p).read()
subs = [
    ('if("${CMAKE_SYSTEM_NAME}" STREQUAL "Generic")',
     'if("${CMAKE_HOST_SYSTEM_NAME}" STREQUAL "Windows")'),
    ('elseif("${CMAKE_SYSTEM_NAME}" STREQUAL "Linux")',
     'elseif("${CMAKE_HOST_SYSTEM_NAME}" STREQUAL "Linux")'),
    ('elseif("${CMAKE_SYSTEM_NAME}" STREQUAL "Darwin")',
     'elseif("${CMAKE_HOST_SYSTEM_NAME}" STREQUAL "Darwin")'),
]
for old, new in subs:
    if old not in s:
        sys.exit("bflb_flash.cmake does not look as expected: %r missing" % old)
    s = s.replace(old, new)
open(p, "w").write(s)
PY
  fi
fi

# 7. Gowin EDA, Education edition - the only thing that can turn this
#    design into a bitstream.  Free and needs no licence file for the
#    GW2AR-18C on the Tang Nano 20K.  648 MB compressed, about 3 GB
#    unpacked, so it is fetched last.
GOWIN_URL=https://cdn.gowinsemi.com.cn/Gowin_V1.9.11.03_Education_Linux.tar.gz
if have "$T/gowin/IDE/bin/gw_sh"; then log "gowin present"; else
  log "downloading Gowin EDA Education (648 MB)"
  curl -fL --retry 3 -o "$DL/gowin_edu.tar.gz" "$GOWIN_URL" || exit 1
  log "extracting Gowin EDA"
  mkdir -p "$T/gowin"
  tar -C "$T/gowin" --strip-components=1 -xzf "$DL/gowin_edu.tar.gz" || exit 1
  chmod -R u+x "$T/gowin/IDE/bin" "$T/gowin/Programmer/bin" 2>/dev/null || true
fi

# 8. macro11, the MACRO-11 cross-assembler soft/src/ is written for.  A
#    few hundred KB of C; make soft needs it, nothing else does.
if have "$T/macro11/macro11"; then log "macro11 present"; else
  log "cloning macro11"
  git clone --depth 1 https://github.com/shattered/macro11.git "$T/macro11" || exit 1
  make -C "$T/macro11" -s || exit 1
fi

log "done"
