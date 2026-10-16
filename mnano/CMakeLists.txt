cmake_minimum_required(VERSION 3.15)
project(shared_companion NONE)
get_filename_component(COMPANION_DEFAULT "${CMAKE_CURRENT_LIST_DIR}/../../tang-ultima" ABSOLUTE)
set(COMPANION_ROOT "${COMPANION_DEFAULT}" CACHE PATH "Shared Tang Ultima companion repository")
if(NOT EXISTS "${COMPANION_ROOT}/mnano/companion.c")
  message(FATAL_ERROR "Shared firmware missing: clone tang-ultima beside this repository or set COMPANION_ROOT")
endif()
find_program(COMPANION_MAKE NAMES gmake make)
if(NOT COMPANION_MAKE)
  message(FATAL_ERROR "GNU Make is required to build the shared companion")
endif()
add_custom_target(shared_companion ALL
  COMMAND "${COMPANION_MAKE}" -C "${COMPANION_ROOT}" fw
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/build_out"
  COMMAND "${CMAKE_COMMAND}" -E copy_if_different
    "${COMPANION_ROOT}/build/fw/bl616.bin"
    "${CMAKE_CURRENT_BINARY_DIR}/build_out/misterynano_fw_bl616.bin"
  COMMENT "Build the common JSON-configured BL616 firmware" VERBATIM)
