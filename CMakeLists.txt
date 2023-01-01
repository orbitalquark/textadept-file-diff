# Copyright 2022-2023 Mitchell. See LICENSE.

cmake_minimum_required(VERSION 3.16)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED true)
if(APPLE)
  set(CMAKE_OSX_DEPLOYMENT_TARGET 10.13 CACHE STRING "")
endif()

set(src ${CMAKE_SOURCE_DIR})

# Dependencies.
include(FetchContent)
set(FETCHCONTENT_QUIET OFF)
set(diff_match_patch_zip 7f95b37e554453262e2bcda830724fc362614103.zip)
FetchContent_Declare(diff_match_patch
  URL https://github.com/leutloff/diff-match-patch-cpp-stl/archive/${diff_match_patch_zip})
FetchContent_MakeAvailable(diff_match_patch)
set(lua_tgz lua-5.4.4.tar.gz)
set(lua_url file://${CMAKE_BINARY_DIR}/_deps/${lua_tgz})
if(NOT EXISTS ${CMAKE_BINARY_DIR}/_deps/${lua_tgz})
  set(lua_url https://www.lua.org/ftp/${lua_tgz})
endif()
FetchContent_Declare(lua URL ${lua_url})
FetchContent_MakeAvailable(lua)

# Build.
project(diff LANGUAGES CXX C)
if(WIN32)
  # On Windows, DLLs cannot do dynamic lookup. They need symbols to link to at build time.
  # Rather than fetching a Textadept build and creating separate DLLs linked to textadept.lib and
  # textadept-curses.lib, just embed a minimal copy of Lua in a single DLL.
  file(GLOB lua_src ${lua_SOURCE_DIR}/src/*.c)
  list(FILTER lua_src EXCLUDE REGEX "(lua|luac|[^x]lib|linit)\.c$") # of *lib.c, keep only lauxlib.c
endif()
add_library(diff SHARED diff.cxx ${lua_src})
target_include_directories(diff PRIVATE ${diff_match_patch_SOURCE_DIR} ${lua_SOURCE_DIR}/src)
if(WIN32)
  target_compile_definitions(diff PRIVATE LUA_BUILD_AS_DLL LUA_LIB)
elseif(APPLE)
  target_link_options(diff PRIVATE -undefined dynamic_lookup)
endif()

# Install.
install(TARGETS diff DESTINATION ${src})
if(NOT (WIN32 OR APPLE))
  install(CODE "file(RENAME ${src}/libdiff.so ${src}/diff.so)")
elseif(APPLE)
  install(CODE "file(RENAME ${src}/libdiff.dylib ${src}/diffosx.so)")
endif()
if(NOT (WIN32 OR APPLE))
  include(GNUInstallDirs)
  set(module_dir ${CMAKE_INSTALL_FULL_DATADIR}/textadept/modules/file_diff)
  install(CODE "file(MAKE_DIRECTORY ${module_dir})")
  install(FILES init.lua diff.so DESTINATION ${module_dir})
endif()

# Documentation.
get_filename_component(ta_dir ${src}/../../ ABSOLUTE)
add_custom_target(docs DEPENDS README.md luadoc)
add_custom_command(OUTPUT ${src}/README.md
  COMMAND luadoc --doclet markdowndoc ${src}/init.lua > ${src}/README.md
  COMMAND sed -i -e "1,+4d" -e "6c# File Diff" -e "7d" -e "s/^##/#/;" ${src}/README.md
  DEPENDS init.lua
  WORKING_DIRECTORY ${ta_dir}/scripts
  VERBATIM)
add_custom_target(luadoc DEPENDS tags api)
add_custom_command(OUTPUT ${src}/tags ${src}/api
  COMMAND luadoc -d ${src} --doclet tadoc ${src}/init.lua --ta-home=${ta_dir}
  DEPENDS init.lua
  WORKING_DIRECTORY ${ta_dir}/modules/lua)
