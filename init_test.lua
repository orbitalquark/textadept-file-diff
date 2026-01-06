-- Copyright 2020-2026 Mitchell. See LICENSE.

local file_diff = require('file_diff')

test('file_diff.start should prompt for files to compare', function()
	local f1<close> = test.tmpfile()
	local f2<close> = test.tmpfile()
	local filenames = {f1.filename, f2.filename}
	local select_filename = function() return table.remove(filenames, 1) end
	local _<close> = test.mock(ui.dialogs, 'open', select_filename)

	file_diff.start()

	test.assert_equal(#_VIEWS, 2)
	test.assert_equal(_VIEWS[view], 1)
	test.assert_equal(view.buffer.filename, f1.filename)
	test.assert_equal(_VIEWS[2].buffer.filename, f2.filename)
end)

test('file_diff.start should use existing views', function()
	view:split()
	buffer.new()

	file_diff.start('-', '-')

	test.assert_equal(#_VIEWS, 2)
	test.assert_equal(_BUFFERS[buffer], 1)
	test.assert_equal(_BUFFERS[_VIEWS[2].buffer], 2)
end)

local original = test.lines{
	'', --
	'modify', --
	'unchanged', --
	'deleted', --
	''
}

local changed = test.lines{
	'', --
	'added', --
	'modified', --
	'unchanged', --
	''
}

local function start_basic_diff()
	buffer:append_text(original)
	view:split(true)
	buffer.new()
	buffer:append_text(changed)
	file_diff.start('-', '-')
	ui.goto_view(_VIEWS[1])
end

test('file_diff should mark added, modified, and deleted lines', function()
	start_basic_diff()

	local added_lines1 = test.get_marked_lines(file_diff.MARK_ADDITION, _VIEWS[1].buffer)
	local added_lines2 = test.get_marked_lines(file_diff.MARK_ADDITION, _VIEWS[2].buffer)
	local modified_lines1 = test.get_marked_lines(file_diff.MARK_MODIFICATION, _VIEWS[1].buffer)
	local modified_lines2 = test.get_marked_lines(file_diff.MARK_MODIFICATION, _VIEWS[2].buffer)
	local deleted_lines1 = test.get_marked_lines(file_diff.MARK_DELETION, _VIEWS[1].buffer)
	local deleted_lines2 = test.get_marked_lines(file_diff.MARK_DELETION, _VIEWS[2].buffer)
	test.assert_equal(added_lines1, {})
	test.assert_equal(added_lines2, {2})
	test.assert_equal(modified_lines1, {2})
	test.assert_equal(modified_lines2, {3})
	test.assert_equal(deleted_lines1, {4})
	test.assert_equal(deleted_lines2, {})
end)

test('file_diff should indicated added and deleted ranges', function()
	start_basic_diff()

	local deleted1 = test.get_indicated_text(file_diff.INDIC_DELETION, _VIEWS[1].buffer)
	local deleted2 = test.get_indicated_text(file_diff.INDIC_DELETION, _VIEWS[2].buffer)
	local added1 = test.get_indicated_text(file_diff.INDIC_ADDITION, _VIEWS[1].buffer)
	local added2 = test.get_indicated_text(file_diff.INDIC_ADDITION, _VIEWS[2].buffer)
	test.assert_equal(deleted1, {'y'}) -- from modify
	test.assert_equal(deleted2, {})
	test.assert_equal(added1, {})
	test.assert_equal(added2, {'ied'}) -- from modified
end)

test('file_diff should add dummy lines in place of additions and deletions', function()
	start_basic_diff()

	test.assert_equal(_VIEWS[1].buffer.annotation_text[1], ' ') -- across from 'added'
	test.assert_equal(_VIEWS[2].buffer.annotation_text[4], ' ') -- across from 'deleted'
end)

test('file_diff.goto_change(true) should jump to the next change (left view)', function()
	start_basic_diff()
	local lines = {}

	for _ = 1, 3 do
		file_diff.goto_change(true)
		lines[#lines + 1] = buffer:line_from_position(buffer.current_pos)
	end

	test.assert_equal(lines, {2, 4, 1}) -- wraps around back to 1
end)

test('file_diff.goto_change should jump to the previous change (left view)', function()
	start_basic_diff()
	local lines = {}

	for _ = 1, 3 do
		file_diff.goto_change()
		lines[#lines + 1] = buffer:line_from_position(buffer.current_pos)
	end

	test.assert_equal(lines, {4, 2, 1})
end)
expected_failure()

test('file_diff.goto_change(true) should jump to the next change (right view)', function()
	start_basic_diff()
	ui.goto_view(_VIEWS[2])
	local lines = {}

	for _ = 1, 3 do
		file_diff.goto_change(true)
		lines[#lines + 1] = buffer:line_from_position(buffer.current_pos)
	end

	test.assert_equal(lines, {2, 3, 4})
end)

test('file_diff.goto_change should jump to the previous change (right view)', function()
	start_basic_diff()
	ui.goto_view(_VIEWS[2])
	local lines = {}

	for _ = 1, 3 do
		file_diff.goto_change()
		lines[#lines + 1] = buffer:line_from_position(buffer.current_pos)
	end

	test.assert_equal(lines, {4, 3, 2})
end)

test('file_diff.goto_change should treat multi-line changes as a single change', function()
	buffer:append_text(test.lines{
		'', --
		'unchanged', --
		'modify', --
		'modify', --
		'unchanged', --
		'deleted', --
		'deleted', --
		''
	})
	view:split(true)
	buffer.new()
	buffer:append_text(test.lines{
		'', --
		'added', --
		'added', --
		'unchanged', --
		'modified', --
		'modified', --
		'unchanged', --
		''
	})
	file_diff.start('-', '-')
	ui.goto_view(_VIEWS[1])
	local lines = {}

	for _ = 1, 3 do
		file_diff.goto_change(true)
		lines[#lines + 1] = buffer:line_from_position(buffer.current_pos)
	end

	test.assert_equal(lines, {3, 6, 1})
end)

test('file_diff.merge should merge from left to right (left view)', function()
	start_basic_diff()

	file_diff.merge()

	test.assert_equal(_VIEWS[view], 1)
	test.assert_equal(buffer:line_from_position(buffer.current_pos), 1)
	test.assert_equal(buffer:get_text(), original)
	test.assert_equal(_VIEWS[2].buffer:get_text(), test.lines{
		'', --
		'modified', --
		'unchanged', --
		''
	})

	file_diff.goto_change(true)
	file_diff.merge()

	test.assert_equal(buffer:get_text(), original)
	test.assert_equal(_VIEWS[2].buffer:get_text(), test.lines{
		'', --
		'modify', --
		'unchanged', --
		'' --
	})

	file_diff.goto_change(true)
	file_diff.merge()

	test.assert_equal(buffer:get_text(), original)
	test.assert_equal(_VIEWS[2].buffer:get_text(), original)
end)

test('file_diff.merge should merge from right to left (left view)', function()
	start_basic_diff()

	file_diff.merge(true)

	test.assert_equal(_VIEWS[view], 1)
	test.assert(buffer:line_from_position(buffer.current_pos), 2)
	test.assert_equal(buffer:get_text(), test.lines{
		'', --
		'added', --
		'modify', --
		'unchanged', --
		'deleted', --
		''
	})
	test.assert_equal(_VIEWS[2].buffer:get_text(), changed)

	file_diff.goto_change(true)
	file_diff.merge(true)

	test.assert_equal(buffer:get_text(), test.lines{
		'', --
		'added', --
		'modified', --
		'unchanged', --
		'deleted', --
		''
	})
	test.assert_equal(_VIEWS[2].buffer:get_text(), changed)

	file_diff.goto_change(true)
	file_diff.merge(true)

	test.assert_equal(buffer:get_text(), changed)
	test.assert_equal(_VIEWS[2].buffer:get_text(), changed)
end)

test('file_diff.merge should merge from left to right (right view)', function()
	start_basic_diff()
	ui.goto_view(_VIEWS[2])

	file_diff.goto_change(true)
	file_diff.merge()

	test.assert_equal(_VIEWS[view], 2)
	test.assert_equal(buffer:line_from_position(buffer.current_pos), 2)
	test.assert_equal(buffer:get_text(), test.lines{
		'', --
		'modified', --
		'unchanged', --
		''
	})
	test.assert_equal(_VIEWS[1].buffer:get_text(), original)

	file_diff.merge() -- no need to go to next change

	test.assert_equal(buffer:get_text(), test.lines{
		'', --
		'modify', --
		'unchanged', --
		''
	})
	test.assert_equal(_VIEWS[1].buffer:get_text(), original)

	file_diff.goto_change(true)
	file_diff.merge()

	test.assert_equal(buffer:get_text(), original)
	test.assert_equal(_VIEWS[2].buffer:get_text(), original)
end)

test('file_diff.merge should merge from right to left (right view)', function()
	start_basic_diff()
	ui.goto_view(_VIEWS[2])

	file_diff.goto_change(true)
	file_diff.merge(true)

	test.assert_equal(_VIEWS[view], 2)
	test.assert_equal(buffer:line_from_position(buffer.current_pos), 2)
	test.assert_equal(buffer:get_text(), changed)
	test.assert_equal(_VIEWS[1].buffer:get_text(), test.lines{
		'', --
		'added', --
		'modify', --
		'unchanged', --
		'deleted', --
		''
	})

	file_diff.goto_change(true)
	file_diff.merge(true)

	test.assert_equal(buffer:get_text(), changed)
	test.assert_equal(_VIEWS[1].buffer:get_text(), test.lines{
		'', --
		'added', --
		'modified', --
		'unchanged', --
		'deleted', --
		''
	})

	file_diff.goto_change(true)
	file_diff.merge(true)

	test.assert_equal(buffer:get_text(), changed)
	test.assert_equal(_VIEWS[1].buffer:get_text(), changed)
end)

test('file_diff should fill space for a change with additional lines in the right buffer',
	function()
		buffer:append_text(test.lines{
			'', --
			'modify', --
			'unchanged'
		})
		view:split(true)
		buffer.new()
		buffer:append_text(test.lines{
			'', --
			'modified', --
			'added', --
			'unchanged'
		})

		file_diff.start('-', '-')

		test.assert_equal(_VIEWS[1].buffer.annotation_text[2], ' ')
	end)

test('file_diff should fill space for a change with additional lines in the left buffer', function()
	buffer:append_text(test.lines{
		'', --
		'added', --
		'added', --
		'unchanged'
	})
	view:split(true)
	buffer.new()
	buffer:append_text(test.lines{
		'', --
		'', --
		'unchanged'
	})

	file_diff.start('-', '-')

	test.assert_equal(_VIEWS[2].buffer.annotation_text[2], ' ')
end)

test('file_diff should fill space for a larger change in the right buffer', function()
	buffer:append_text(test.lines{
		'', --
		'modify', --
		'modify', --
		'unchanged'
	})
	view:split(true)
	buffer.new()
	buffer:append_text(test.lines{
		'', --
		'modified', --
		'unchanged'
	})

	file_diff.start('-', '-')

	test.assert_equal(_VIEWS[2].buffer.annotation_text[2], ' ')
end)

test('file_diff should fill space for an addition with additional lines in the right buffer',
	function()
		buffer:append_text(test.lines{
			'', --
			'modified', --
			'unchanged'
		})
		view:split(true)
		buffer.new()
		buffer:append_text(test.lines{
			'', --
			'modified more', --
			'added', --
			'unchanged'
		})

		file_diff.start('-', '-')

		test.assert_equal(_VIEWS[1].buffer.annotation_text[2], ' ')
	end)

test('file_diff should synchronize scrolling', function()
	local f1<close> = test.tmpfile(test.lines(100))
	local f2<close> = test.tmpfile(test.lines(100))

	file_diff.start(f1.filename, f2.filename)

	buffer:page_down()
	ui.update() -- trigger events.UPDATE_UI
	if CURSES then events.emit(events.UPDATE_UI, buffer.UPDATE_SELECTION) end

	test.assert_equal(_VIEWS[1].first_visible_line, _VIEWS[2].first_visible_line)
end)
if WIN32 and GUI then skip('crashes inside Scintilla') end -- TODO:

test('file_diff should stop when switching buffers', function()
	start_basic_diff()

	view:goto_buffer(-1)

	local added_lines = test.get_marked_lines(file_diff.MARK_ADDITION, _VIEWS[1].buffer)
	test.assert_equal(added_lines, {})
end)

-- Coverage tests.

test('file_diff.goto_change should notify when there are no more changes', function()
	view:split(true)
	buffer.new()
	file_diff.start('-', '-')

	file_diff.goto_change(true)

	test.assert_equal(ui.statusbar_text, _L['No more differences'])
end)
