# File Diff

Two-way file comparison for Textadept.

Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
*modules/* directory, and then putting the following in your *~/.textadept/init.lua*:

```lua
local file_diff = require('file_diff')
```

## Compiling

Releases include binaries, so building this modules should not be necessary. If you want
to build manually, use CMake. For example:

```bash
cmake -S . -B build_dir
cmake --build build_dir --target diff
cmake --install build_dir
```

## Usage

A sample workflow is this:
1. Start comparing two files via the "Compare Files" submenu in the "Tools" menu.
2. The caret is initially placed in the file on the left.
3. Go to the next change via menu or key binding.
4. Merge the change from the other buffer into the current one (right to left) via menu or
	key binding.
5. Go to the next change via menu or key binding.
6. Merge the change from the current buffer into the other one (left to right) via menu or
	key binding.
7. Repeat as necessary.

Note: merging can be performed wherever the caret is placed when jumping between changes,
even if one buffer has a change and the other does not (additions or deletions).

## Key Bindings

Windows and Linux | macOS | Terminal | Command
-|-|-|-
**Tools**| | |
F6 | F6 | None | Compare files...
Shift+F6 | ⇧F6 | None | Compare the buffers in two split views
Ctrl+F6 | ⌘F6 | None | Stop comparing
Ctrl+Alt+. | ^⌘. | None | Goto next difference
Ctrl+Alt+, | ^⌘, | None | Goto previous difference
Ctrl+Alt+< | ^⌘< | None | Merge left
Ctrl+Alt+> | ^⌘> | None | Merge right

<a id="file_diff.INDIC_ADDITION"></a>
## `file_diff.INDIC_ADDITION`

The indicator number for text added within lines.

<a id="file_diff.INDIC_DELETION"></a>
## `file_diff.INDIC_DELETION`

The indicator number for text deleted within lines.

<a id="file_diff.MARK_ADDITION"></a>
## `file_diff.MARK_ADDITION`

The marker for line additions.

<a id="file_diff.MARK_DELETION"></a>
## `file_diff.MARK_DELETION`

The marker for line deletions.

<a id="file_diff.MARK_MODIFICATION"></a>
## `file_diff.MARK_MODIFICATION`

The marker for line modifications.

<a id="_G.diff"></a>
## `_G.diff`(*text1*, *text2*)

Returns a list of the differences between strings.

Each consecutive pair of elements in the returned list represents a "diff". The first element
is an integer: 0 for a deletion, 1 for an insertion, and 2 for equality. The second element
is the associated diff text.

Parameters:
- *text1*:  String to compare against.
- *text2*:  String to compare.

Usage:

```lua
diffs = diff(text1, text2)
for i = 1, #diffs, 2 do print(diffs[i], diffs[i + 1]) end
```

<a id="file_diff.addition_color_name"></a>
## `file_diff.addition_color_name`

The name of the theme color used to mark additions.

The default value is 'green'. If your theme does not define that color, set this field to
your theme's equivalent.

<a id="file_diff.deletion_color_name"></a>
## `file_diff.deletion_color_name`

The name of the theme color used to mark deletions.

The default value is 'red'. If your theme does not define that color, set this field to your
theme's equivalent.

<a id="file_diff.goto_change"></a>
## `file_diff.goto_change`([*next*=false])

Jumps to the next or previous difference between the two files.

[`file_diff.start()`](#file_diff.start) must have been called previously.

Parameters:
- *next*:  Go to the next previous difference relative to the current line,
	as opposed to the previous one.

<a id="file_diff.merge"></a>
## `file_diff.merge`([*left*=false])

Merges a change from one buffer to another, depending on the change under the caret and the
merge direction.

Parameters:
- *left*:  Merge from right to left as opposed to left to right.

<a id="file_diff.modification_color_name"></a>
## `file_diff.modification_color_name`

The name of the theme color used to mark modifications.

The default value is 'yellow'. If your theme does not define that color, set this field to
your theme's equivalent.

<a id="file_diff.start"></a>
## `file_diff.start`([*file1*[, *file2*[, *horizontal*=false]]])

Highlight differences between files.

Parameters:
- *file1*:  String older filename. If `-`, uses the current buffer. If `nil`, the user
	is prompted for a file.
- *file2*:  String newer filename. If `-`, uses the current buffer. If `nil`, the user
	is prompted for a file.
- *horizontal*:  Split the view horizontally instead of vertically. The
	default is to compare files side-by-side.



