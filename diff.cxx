// Copyright 2017-2020 Mitchell. See LICENSE.

#include "diff_match_patch.h"

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

/** diff() Lua function. */
static int diff(lua_State *L) {
  diff_match_patch<std::string> dmp;
  auto diffs = dmp.diff_main(
    luaL_checkstring(L, 1), luaL_checkstring(L, 2), false);
  dmp.diff_cleanupSemantic(diffs);
  lua_createtable(L, diffs.size() * 2, 0);
  int len = 1;
  for(auto& diff : diffs) {
    lua_pushnumber(L, diff.operation), lua_rawseti(L, -2, len++);
    lua_pushstring(L, diff.text.c_str()), lua_rawseti(L, -2, len++);
  }
  return 1;
}

extern "C" {
int luaopen_diff(lua_State *L) {
  return (lua_pushcfunction(L, diff), 1);
}

// Platform-specific Lua library entry points.
LUALIB_API int luaopen_file_diff_diff(lua_State *L) {
  return luaopen_diff(L);
}
LUALIB_API int luaopen_file_diff_diffosx(lua_State *L) {
  return luaopen_diff(L);
}
}
