# Copyright 2017-2020 Mitchell. See LICENSE.

ta = ../..
ta_src = $(ta)/src
ta_lua = $(ta_src)/lua/src

CXX = g++
CXXFLAGS = -std=c++11 -pedantic -fPIC -Wall
LDFLAGS = -Wl,--retain-symbols-file -Wl,$(ta_src)/lua.sym

all: diff.so diff.dll diff-curses.dll diffosx.so
clean: ; rm -f *.o *.so *.dll

# Platform objects.

CROSS_WIN = i686-w64-mingw32-
CROSS_OSX = x86_64-apple-darwin17-c++

diff.so: diff.o ; $(CXX) -shared $(CXXFLAGS) -o $@ $^ $(LDFLAGS)
diff.dll: diff-win.o lua.la
	$(CROSS_WIN)$(CXX) -shared -static-libgcc -static-libstdc++ $(CXXFLAGS) -o \
		$@ $^ $(LDFLAGS)
diff-curses.dll: diff-win.o lua-curses.la
	$(CROSS_WIN)$(CXX) -shared -static-libgcc -static-libstdc++ $(CXXFLAGS) -o \
		$@ $^ $(LDFLAGS)
diffosx.so: diff-osx.o
	$(CROSS_OSX) -shared $(CXXFLAGS_OSX) -undefined dynamic_lookup -o $@ $^

diff.o: diff.cxx ; $(CXX) -c $(CXXFLAGS) -I$(ta_lua) -o $@ $^
diff-win.o: diff.cxx
	$(CROSS_WIN)$(CXX) -c $(CXXFLAGS) -DLUA_BUILD_AS_DLL -DLUA_LIB -I$(ta_lua) \
		-o $@ $^
diff-osx.o: diff.cxx ; $(CROSS_OSX) -c $(CXXFLAGS_OSX) -I$(ta_lua) -o $@ $^

lua.def:
	echo LIBRARY \"textadept.exe\" > $@ && echo EXPORTS >> $@
	grep -v "^#" $(ta_src)/lua.sym >> $@
lua.la: lua.def ; $(CROSS_WIN)dlltool -d $< -l $@
lua-curses.def:
	echo LIBRARY \"textadept-curses.exe\" > $@ && echo EXPORTS >> $@
	grep -v "^#" $(ta_src)/lua.sym >> $@
lua-curses.la: lua-curses.def ; $(CROSS_WIN)dlltool -d $< -l $@

# Documentation.

cwd = $(shell pwd)
docs: luadoc README.md
README.md: init.lua
	cd $(ta)/scripts && luadoc --doclet markdowndoc $(cwd)/$< > $(cwd)/$@
	sed -i -e '1,+4d' -e '6c# File Diff' -e '7d' -e 's/^##/#/;' $@
luadoc: init.lua
	cd $(ta)/modules && luadoc -d $(cwd) --doclet lua/tadoc $(cwd)/$< \
		--ta-home=$(shell readlink -f $(ta))
	sed -i 's/_HOME.\+\?_HOME/_HOME/;' tags

# External diff_match_patch dependency.

deps: diff_match_patch.h

diff_match_patch_zip = 7f95b37e554453262e2bcda830724fc362614103.zip
$(diff_match_patch_zip):
	wget https://github.com/leutloff/diff-match-patch-cpp-stl/archive/$@
diff_match_patch.h: | $(diff_match_patch_zip) ; unzip -j $| "*/$@"

# Releases.

ifneq (, $(shell hg summary 2>/dev/null))
  archive = hg archive -X ".hg*" $(1)
else
  archive = git archive HEAD --prefix $(1)/ | tar -xf -
endif

release: file_diff | $(diff_match_patch_zip)
	cp $| $<
	make -C $< deps && make -C $< -j ta="../../.."
	zip -r $<.zip $< -x "*.zip" "*.h" "*.o" "*.def" "*.la" "$</.git*" && rm -r $<
file_diff: ; $(call archive,$@)
