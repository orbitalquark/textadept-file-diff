-- Copyright 2015-2020 Mitchell. See LICENSE.

local M = {}

--[[ This comment is for LuaDoc.
---
-- Two-way file comparison for Textadept.
--
-- Install this module by copying it into your *~/.textadept/modules/* directory
-- or Textadept's *modules/* directory, and then putting the following in your
-- *~/.textadept/init.lua*:
--
--     require('file_diff')
--
-- ### Usage
--
-- A sample workflow is this:
--
-- 1. Start comparing two files via the "Compare Files" submenu in the "Tools"
--    menu.
-- 2. The caret is initially placed in the file on the left.
-- 3. Go to the next change via menu or key binding.
-- 4. Merge the change from the other buffer into the current one (right to
--    left) via menu or key binding.
-- 5. Go to the next change via menu or key binding.
-- 6. Merge the change from the current buffer into the other one (left to
--    right) via menu or key binding.
-- 7. Repeat as necessary.
--
-- Note: merging can be performed wherever the caret is placed when jumping
-- between changes, even if one buffer has a change and the other does not
-- (additions or deletions).
--
-- ### Key Bindings
--
-- Windows, Linux, BSD|macOS|Terminal|Command
-- -------------------|-----|--------|-------
-- **Tools**          |     |        |
-- F6                 |F6   |F6      |Compare files...
-- Shift+F6           |⇧F6  |S-F6    |Compare the buffers in two split views
-- Alt+Down           |⌥⇣   |M-Down  |Goto next difference
-- Alt+Up             |⌥⇡   |M-Up    |Goto previous difference
-- Alt+Left           |⌥⇠   |M-Left  |Merge left
-- Alt+Right          |⌥⇢   |M-Right |Merge right
--
-- @field theme (string)
--   The theme to use, either 'dark' or 'light'.
--   This is not the theme used with Textadept.
--   Depending on this setting, additions will be colored 'dark_green' or
--   'light_green', deletions will be colored 'dark_red' or 'light_red', and so
--   on.
--   The default value is auto-detected.
-- @field MARK_ADDITION (number)
--   The marker for line additions.
-- @field MARK_DELETION (number)
--   The marker for line deletions.
-- @field MARK_MODIFICATION (number)
--   The marker for line modifications.
-- @field INDIC_ADDITION (number)
--   The indicator number for text added within lines.
-- @field INDIC_DELETION (number)
--   The indicator number for text deleted within lines.
module('file_diff')]]

M.theme = 'light'
local bg_color = view.property_expanded['style.default']:match('back:([^,]+)')
if bg_color and tonumber(bg_color) < 0x808080 and not CURSES then
  M.theme = 'dark'
end

M.MARK_ADDITION = _SCINTILLA.next_marker_number()
M.MARK_DELETION = _SCINTILLA.next_marker_number()
M.MARK_MODIFICATION = _SCINTILLA.next_marker_number()
M.INDIC_ADDITION = _SCINTILLA.next_indic_number()
M.INDIC_DELETION = _SCINTILLA.next_indic_number()
local MARK_ADDITION = M.MARK_ADDITION
local MARK_DELETION = M.MARK_DELETION
local MARK_MODIFICATION = M.MARK_MODIFICATION
local INDIC_ADDITION = M.INDIC_ADDITION
local INDIC_DELETION = M.INDIC_DELETION

-- Localizations.
local _L = _L
if not rawget(_L, 'Compare Files') then
  -- Dialogs.
  _L['Select the first file to compare'] = 'Select the first file to compare'
  _L['Select the file to compare to'] = 'Select the file to compare to'
  -- Status.
  _L['No more differences'] = 'No more differences'
  -- Menu.
  _L['Compare Files'] = 'Compare _Files'
  _L['Compare Files...'] = '_Compare Files...'
  _L['Compare This File With...'] = 'Compare This File _With...'
  _L['Compare Buffers'] = 'Compare _Buffers'
  _L['Next Change'] = '_Next Change'
  _L['Previous Change'] = '_Previous Change'
  _L['Merge Left'] = 'Merge _Left'
  _L['Merge Right'] = 'Merge _Right'
  _L['Stop Comparing'] = '_Stop Comparing'
end

local lib = 'file_diff.diff'
if OSX then
  lib = lib .. 'osx'
elseif WIN32 and CURSES then
  lib = lib .. '-curses'
end
local diff = require(lib)
local DELETE, INSERT = 0, 1 -- C++: "enum Operation {DELETE, INSERT, EQUAL};"

local view1, view2

-- Clear markers, indicators, and placeholder lines.
-- Used when re-marking changes or finished comparing.
local function clear_marked_changes()
  local buffer1 = _VIEWS[view1] and view1.buffer
  local buffer2 = _VIEWS[view2] and view2.buffer
  for _, mark in ipairs{MARK_ADDITION, MARK_DELETION, MARK_MODIFICATION} do
    if buffer1 then buffer1:marker_delete_all(mark) end
    if buffer2 then buffer2:marker_delete_all(mark) end
  end
  for _, indic in ipairs{INDIC_ADDITION, INDIC_DELETION} do
    if buffer1 then
      buffer1.indicator_current = indic
      buffer1:indicator_clear_range(1, buffer1.length)
    end
    if buffer2 then
      buffer2.indicator_current = indic
      buffer2:indicator_clear_range(1, buffer2.length)
    end
  end
  if buffer1 then buffer1:annotation_clear_all() end
  if buffer2 then buffer2:annotation_clear_all() end
end

local synchronizing = false
-- Synchronize the scroll and line position of the other buffer.
local function synchronize()
  synchronizing = true
  local line = buffer:line_from_position(buffer.current_pos)
  local visible_line = view:visible_from_doc_line(line)
  local first_visible_line = view.first_visible_line
  local x_offset = view.x_offset
  ui.goto_view(view == view1 and view2 or view1)
  buffer:goto_line(view:doc_line_from_visible(visible_line))
  view.first_visible_line, view.x_offset = first_visible_line, x_offset
  ui.goto_view(view == view2 and view1 or view2)
  synchronizing = false
end

-- Returns the number of lines contained in the given string.
local function count_lines(text)
  local lines = 1
  for _ in text:gmatch('\n') do lines = lines + 1 end
  return lines
end

-- Mark the differences between the two buffers.
local function mark_changes()
  if not _VIEWS[view1] or not _VIEWS[view2] then return end
  clear_marked_changes() -- clear previous marks
  local buffer1, buffer2 = view1.buffer, view2.buffer
  -- Perform the diff.
  local diffs = diff(buffer1:get_text(), buffer2:get_text())
  -- Parse the diff, marking modified lines and changed text.
  local pos1, pos2 = 1, 1
  for i = 1, #diffs, 2 do
    local op, text = diffs[i], diffs[i + 1]
    local text_len = #text
    if op == DELETE then
      local next_op, next_text = diffs[i + 2], diffs[i + 3]
      -- Mark partial lines as modified and full lines as deleted.
      local start_line = buffer1:line_from_position(pos1)
      local end_line = buffer1:line_from_position(pos1 + text_len)
      local mark = MARK_MODIFICATION -- assume partial initially
      if next_op ~= INSERT then
        -- Deleting full line(s), either from line start to next line(s) start,
        -- or from line end to next line(s) end. Adjust `start_line` and
        -- `end_line` accordingly for accurate line markers.
        if pos1 == buffer1:position_from_line(start_line) and
           pos1 + text_len == buffer1:position_from_line(end_line) then
          mark = MARK_DELETION
          end_line = end_line - 1
        elseif pos1 == buffer1.line_end_position[start_line] and
               pos1 + text_len == buffer1.line_end_position[end_line] then
          mark = MARK_DELETION
          start_line = start_line + 1
        end
      end
      for j = start_line, end_line do buffer1:marker_add(j, mark) end
      -- Highlight deletion from partially changed line(s) and mark other line
      -- as modified.
      if mark == MARK_MODIFICATION then
        buffer1.indicator_current = INDIC_DELETION
        buffer1:indicator_fill_range(pos1, text_len)
        buffer2:marker_add(buffer2:line_from_position(pos2), mark)
      end
      pos1 = pos1 + text_len
      -- Calculate net change in lines and fill in empty space in either buffer
      -- with annotations if necessary.
      if next_op == INSERT then
        -- Deleting line(s) in favor of other lines. If those other lines are
        -- more numerous, then fill empty space in this buffer.
        local num_lines = count_lines(text)
        local next_num_lines = count_lines(next_text)
        if num_lines < next_num_lines then
          local annotation_lines = next_num_lines - num_lines - 1
          local annotation_text = ' ' .. string.rep(
            '\n', annotation_lines + buffer1.annotation_lines[end_line])
          buffer1.annotation_text[end_line] = annotation_text
        end
      elseif mark == MARK_DELETION then
        -- Deleting full line(s) with no replacement, so fill empty space in
        -- other buffer.
        local offset = not text:find('^\n') and 1 or 0
        local line = math.max(buffer2:line_from_position(pos2) - offset, 1)
        local annotation_lines = end_line - start_line
        local annotation_text = ' ' .. string.rep('\n', annotation_lines)
        buffer2.annotation_text[line] = annotation_text
      else
        -- Deleting partial line(s) with no replacement, so fill empty space in
        -- other buffer.
        local extra_lines = count_lines(text) - 1
        if extra_lines > 0 then
          local line = buffer2:line_from_position(pos2)
          local annotation_lines = extra_lines - 1
          local annotation_text = ' ' .. string.rep('\n', annotation_lines)
          buffer2.annotation_text[line] = annotation_text
        end
      end
    elseif op == INSERT then
      local prev_op, prev_text = diffs[i - 2], diffs[i - 1]
      -- Mark partial lines as modified and full lines as deleted.
      local start_line = buffer2:line_from_position(pos2)
      local end_line = buffer2:line_from_position(pos2 + text_len)
      local mark = MARK_MODIFICATION -- assume partial initially
      if prev_op ~= DELETE then
        -- Adding full line(s), either from line start to next line(s) start, or
        -- from line end to next line(s) end. Adjust `start_line` and `end_line`
        -- accordingly for accurate line markers.
        if pos2 == buffer2:position_from_line(start_line) and
           pos2 + text_len == buffer2:position_from_line(end_line) then
          mark = MARK_ADDITION
          end_line = end_line - 1
        elseif pos2 == buffer2.line_end_position[start_line] and
               pos2 + text_len == buffer2.line_end_position[end_line] then
          mark = MARK_ADDITION
          start_line = start_line + 1
        end
      end
      for j = start_line, end_line do buffer2:marker_add(j, mark) end
      -- Highlight addition from partially changed line(s) and mark other line
      -- as modified.
      if mark == MARK_MODIFICATION then
        buffer2.indicator_current = INDIC_ADDITION
        buffer2:indicator_fill_range(pos2, text_len)
        buffer1:marker_add(buffer1:line_from_position(pos1), mark)
      end
      pos2 = pos2 + text_len
      -- Calculate net change in lines and fill in empty space in either buffer
      -- with annotations if necessary.
      if prev_op == DELETE then
        -- Adding line(s) in favor of other lines. If those other lines are
        -- more numerous, then fill empty space in this buffer.
        local num_lines = count_lines(text)
        local prev_num_lines = count_lines(prev_text)
        if num_lines < prev_num_lines then
          local annotation_lines = prev_num_lines - num_lines - 1
          local annotation_text = ' ' .. string.rep(
            '\n', annotation_lines + buffer2.annotation_lines[end_line])
          buffer2.annotation_text[end_line] = annotation_text
        end
      elseif mark == MARK_ADDITION then
        -- Adding full line(s) with no replacement, so fill empty space in other
        -- buffer.
        local offset = not text:find('^\n') and 1 or 0
        local line = math.max(buffer1:line_from_position(pos1) - offset, 1)
        local annotation_lines = end_line - start_line
        local annotation_text = ' ' .. string.rep('\n', annotation_lines)
        buffer1.annotation_text[line] = annotation_text
      else
        -- Adding partial line(s) with no replacement, so fill empty space in
        -- other buffer.
        local extra_lines = count_lines(text) - 1
        if extra_lines > 0 then
          local line = buffer1:line_from_position(pos1)
          local annotation_lines = extra_lines - 1
          local annotation_text = ' ' .. string.rep('\n', annotation_lines)
          buffer1.annotation_text[line] = annotation_text
        end
      end
    else
      pos1, pos2 = pos1 + text_len, pos2 + text_len
    end
  end
  synchronize()
end

local starting_diff = false

---
-- Highlight differences between files *file1* and *file2*, or the user-selected
-- files.
-- @param file1 Optional name of the older file. If `-`, uses the current
--   buffer. If `nil`, the user is prompted for a file.
-- @param file2 Optional name of the newer file. If `-`, uses the current
--   buffer. If `nil`, the user is prompted for a file.
-- @param horizontal Optional flag specifying whether or not to split the view
--   horizontally. The default value is `false`, comparing the two files
--   side-by-side.
-- @name start
function M.start(file1, file2, horizontal)
  file1 = file1 or ui.dialogs.fileselect{
    title = _L['Select the first file to compare'],
    with_directory = (buffer.filename or ''):match('^.+[/\\]') or
      lfs.currentdir(),
    width = CURSES and ui.size[1] - 2 or nil
  }
  if not file1 then return end
  file2 = file2 or ui.dialogs.fileselect{
    title = string.format(
      '%s %s', _L['Select the file to compare to'], file1:match('[^/\\]+$')),
    with_directory = file1:match('^.+[/\\]') or lfs.currentdir(),
    width = CURSES and ui.size[1] - 2 or nil
  }
  if not file2 then return end
  starting_diff = true
  if not _VIEWS[view1] or not _VIEWS[view2] and #_VIEWS > 1 then
    view1, view2 = _VIEWS[1], _VIEWS[2] -- preserve current split views
  end
  if _VIEWS[view1] and view ~= view1 then ui.goto_view(view1) end
  if file1 ~= '-' then io.open_file(file1) end
  view.annotation_visible = view.ANNOTATION_STANDARD -- view1
  if not _VIEWS[view1] or not _VIEWS[view2] then
    view1, view2 = view:split(not horizontal)
  else
    ui.goto_view(view2)
  end
  if file2 ~= '-' then io.open_file(file2) end
  view.annotation_visible = view.ANNOTATION_STANDARD -- view2
  ui.goto_view(view1)
  starting_diff = false
  if file1 == '-' or file2 == '-' then mark_changes() end
end

-- Stops comparing.
local function stop()
  if not _VIEWS[view1] or not _VIEWS[view2] then return end
  clear_marked_changes()
  view1, view2 = nil, nil
end

-- Stop comparing when one of the buffer's being compared is switched or closed.
events.connect(events.BUFFER_BEFORE_SWITCH, function()
  if not starting_diff then stop() end
end)
events.connect(events.BUFFER_DELETED, stop)

-- Retrieves the equivalent of line number *line* in the other buffer.
-- @param line Line to get the synchronized equivalent of in the other buffer.
-- @return line
local function get_synchronized_line(line)
  local visible_line = view:visible_from_doc_line(line)
  ui.goto_view(view == view1 and view2 or view1)
  line = view:doc_line_from_visible(visible_line)
  ui.goto_view(view == view2 and view1 or view2)
  return line
end

---
-- Jumps to the next or previous difference between the two files depending on
-- boolean *next*.
-- [`file_diff.start()`]() must have been called previously.
-- @param next Whether to go to the next or previous difference relative to the
--   current line.
-- @name goto_change
function M.goto_change(next)
  if not _VIEWS[view1] or not _VIEWS[view2] then return end
  -- Determine the line to start on, keeping in mind the synchronized line
  -- numbers may be different.
  local line1, line2
  local step = next and 1 or -1
  if view == view1 then
    line1 = buffer:line_from_position(buffer.current_pos) + step
    if line1 < 1 then line1 = 1 end
    line2 = get_synchronized_line(line1)
  else
    line2 = buffer:line_from_position(buffer.current_pos) + step
    if line2 < 1 then line2 = 1 end
    line1 = get_synchronized_line(line2)
  end
  -- Search for the next change or set of changes, wrapping as necessary.
  -- A block of additions, deletions, or modifications should be treated as a
  -- single change.
  local buffer1, buffer2 = view1.buffer, view2.buffer
  local diff_marker = 1 << MARK_ADDITION - 1 | 1 << MARK_DELETION - 1 |
    1 << MARK_MODIFICATION - 1
  local f = next and buffer.marker_next or buffer.marker_previous
  line1 = f(buffer1, line1, diff_marker)
  while line1 >= 1 and buffer1:marker_get(line1) & diff_marker ==
        buffer1:marker_get(line1 - step) & diff_marker do
    line1 = f(buffer1, line1 + step, diff_marker)
  end
  line2 = f(buffer2, line2, diff_marker)
  while line2 >= 1 and buffer2:marker_get(line2) & diff_marker ==
        buffer2:marker_get(line2 - step) & diff_marker do
    line2 = f(buffer2, line2 + step, diff_marker)
  end
  if line1 < 1 and line2 < 1 then
    line1 = f(buffer1, next and 1 or buffer1.line_count, diff_marker)
    line2 = f(buffer2, next and 1 or buffer2.line_count, diff_marker)
  end
  if line1 < 1 and line2 < 1 then
    ui.statusbar_text = _L['No more differences']
    return
  end
  -- Determine which change is closer to the current line, keeping in mind the
  -- synchronized line numbers may be different. (For example, one buffer may
  -- have a block of modifications next while the other buffer has a block of
  -- additions next, and those additions logically come first.)
  if view == view1 then
    if line2 >= 1 then
      ui.goto_view(view2)
      local visible_line = view:visible_from_doc_line(line2)
      ui.goto_view(view1)
      local line2_1 = view:doc_line_from_visible(visible_line)
      buffer:goto_line(
        line1 >= 1 and
        (next and line1 < line2_1 or not next and line1 > line2_1) and line1 or
        line2_1)
    else
      buffer:goto_line(line1)
    end
  else
    if line1 >= 1 then
      ui.goto_view(view1)
      local visible_line = view:visible_from_doc_line(line1)
      ui.goto_view(view2)
      local line1_2 = view:doc_line_from_visible(visible_line)
      buffer:goto_line(
        line2 >= 1 and
        (next and line2 < line1_2 or not next and line2 > line1_2) and line2 or
        line1_2)
    else
      buffer:goto_line(line2)
    end
  end
  view:vertical_center_caret()
end

---
-- Merges a change from one buffer to another, depending on the change under
-- the caret and the merge direction.
-- @param left Whether to merge from right to left or left to right.
-- @name merge
function M.merge(left)
  if not _VIEWS[view1] or not _VIEWS[view2] then return end
  local buffer1, buffer2 = view1.buffer, view2.buffer
  -- Determine whether or not there is a change to merge.
  local start_line = buffer:line_from_position(buffer.current_pos)
  local end_line = start_line + 1
  local diff_marker = 1 << MARK_ADDITION - 1 | 1 << MARK_DELETION - 1 |
    1 << MARK_MODIFICATION - 1
  local marker = buffer:marker_get(start_line) & diff_marker
  if marker == 0 then
    -- Look for additions or deletions from the other buffer, which are offset
    -- one line down (side-effect of Scintilla's visible line -> doc line
    -- conversions).
    local line = get_synchronized_line(start_line) + 1
    if (view == view1 and buffer2 or buffer1):marker_get(line) &
       diff_marker > 0 then
      ui.goto_view(view == view1 and view2 or view1)
      buffer:line_down()
      M.merge(left)
      ui.goto_view(view == view2 and view1 or view2)
    end
    return
  end
  -- Determine the bounds of the change target it.
  while buffer:marker_get(start_line - 1) & diff_marker == marker do
    start_line = start_line - 1
  end
  buffer.target_start = buffer:position_from_line(start_line)
  while buffer:marker_get(end_line) & diff_marker == marker do
    end_line = end_line + 1
  end
  buffer.target_end = buffer:position_from_line(end_line)
  -- Perform the merge, depending on context.
  if marker == 1 << MARK_ADDITION - 1 then
    if left then
      -- Merge addition from right to left.
      local line = get_synchronized_line(end_line)
      buffer1:insert_text(buffer1:position_from_line(line), buffer2.target_text)
    else
      -- Merge "deletion" (empty text) from left to right.
      buffer2:replace_target('')
    end
  elseif marker == 1 << MARK_DELETION - 1 then
    if left then
      -- Merge "addition" (empty text) from right to left.
      buffer1:replace_target('')
    else
      -- Merge deletion from left to right.
      local line = get_synchronized_line(end_line)
      buffer2:insert_text(buffer2:position_from_line(line), buffer1.target_text)
    end
  elseif marker == 1 << MARK_MODIFICATION - 1 then
    local target_text = buffer.target_text
    start_line = get_synchronized_line(start_line)
    end_line = get_synchronized_line(end_line)
    ui.goto_view(view == view1 and view2 or view1)
    if buffer.annotation_text[end_line] ~= '' then end_line = end_line + 1 end
    buffer.target_start = buffer:position_from_line(start_line)
    buffer.target_end = buffer:position_from_line(end_line)
    if view == view2 and left or view == view1 and not left then
      -- Merge change from opposite view.
      target_text = buffer.target_text
      ui.goto_view(view == view2 and view1 or view2)
      buffer:replace_target(target_text)
    else
      -- Merge change to opposite view.
      buffer:replace_target(target_text)
      ui.goto_view(view == view2 and view1 or view2)
    end
  end
  mark_changes() -- refresh
end

-- TODO: connect to these in `start()` and disconnect in `stop()`?

-- Ensure the diff buffers are scrolled in sync.
events.connect(events.UPDATE_UI, function(updated)
  if _VIEWS[view1] and _VIEWS[view2] and updated and not synchronizing then
    if updated &
       (view.UPDATE_H_SCROLL | view.UPDATE_V_SCROLL |
         buffer.UPDATE_SELECTION) > 0 then
      synchronize()
    end
  end
end)

-- Highlight differences as text is typed and deleted.
events.connect(events.MODIFIED, function(position, modification_type)
  if not _VIEWS[view1] or not _VIEWS[view2] then return end
  if modification_type & (0x01 | 0x02) > 0 then mark_changes() end
end)

events.connect(events.VIEW_NEW, function()
  local markers = {
    [MARK_ADDITION] = M.theme .. '_green', [MARK_DELETION] = M.theme .. '_red',
    [MARK_MODIFICATION] = M.theme .. '_yellow'
  }
  for mark, color in pairs(markers) do
    view:marker_define(mark, view.MARK_BACKGROUND)
    view.marker_back[mark] = view.property_int['color.' .. color]
  end
  local indicators = {
    [INDIC_ADDITION] = M.theme .. '_green', [INDIC_DELETION] = M.theme .. '_red'
  }
  for indic, color in pairs(indicators) do
    view.indic_style[indic] = view.INDIC_FULLBOX
    view.indic_fore[indic] = view.property_int['color.' .. color]
    view.indic_alpha[indic], view.indic_under[indic] = 255, true
  end
end)

args.register('-d', '--diff', 2, M.start, 'Compares two files')

-- Add a menu and configure key bindings.
-- (Insert 'Compare Files' menu in alphabetical order.)
local m_tools = textadept.menu.menubar[_L['Tools']]
local found_area
for i = 1, #m_tools - 1 do
  if not found_area and m_tools[i + 1].title == _L['Bookmarks'] then
    found_area = true
  elseif found_area then
    local label = m_tools[i].title or m_tools[i][1]
    if 'Compare Files' < label:gsub('^_', '') or m_tools[i][1] == '' then
      table.insert(m_tools, i, {
        title = _L['Compare Files'],
        {_L['Compare Files...'], M.start},
        {_L['Compare This File With...'], function()
          if buffer.filename then M.start(buffer.filename) end
        end},
        {_L['Compare Buffers'], function() M.start('-', '-') end},
        {''},
        {_L['Next Change'], function() M.goto_change(true) end},
        {_L['Previous Change'], M.goto_change},
        {''},
        {_L['Merge Left'], function() M.merge(true) end},
        {_L['Merge Right'], M.merge},
        {''},
        {_L['Stop Comparing'], stop}
      })
      break
    end
  end
end
local GUI = not CURSES
keys.f6 = M.start
keys['shift+f6'] = m_tools[_L['Compare Files']][_L['Compare Buffers']][2]
keys[GUI and 'alt+down' or 'meta+down'] =
  m_tools[_L['Compare Files']][_L['Next Change']][2]
keys[GUI and 'alt+up' or 'meta+up'] = M.goto_change
keys[GUI and 'alt+left' or 'meta+left'] =
  m_tools[_L['Compare Files']][_L['Merge Left']][2]
keys[GUI and 'alt+right' or 'meta+right'] = M.merge

return M

--[[ The function below is a Lua C function.
---
-- Returns a list that represents the differences between strings *text1* and
-- *text2*.
-- Each consecutive pair of elements in the returned list represents a "diff".
-- The first element is an integer: 0 for a deletion, 1 for an insertion, and 2
-- for equality. The second element is the associated diff text.
-- @param text1 String to compare against.
-- @param text2 String to compare.
-- @return list of differences
-- @usage diffs = diff(text1, text2)
--        for i = 1, #diffs, 2 do print(diffs[i], diffs[i + 1]) end
function _G.diff(text1, text2) end
]]
