# This must be run from the relevant (x86/x86_64) VS Native Tools command interpreter.

# I'm taking the lazy and reliable route for forcing manual specification of
# x86/64 rather than try to determine it here.

.PHONY: no_build_specified x86 x64

no_build_specified:
	@echo Build either 'x86' or 'x64' from the respective VS command-line environment, or after running vcvarsall.bat.

x86: win32\sqlite3.lib

x64: win64\sqlite3.lib

# The script below comes from https://stackoverflow.com/a/9946390
win32\sqlite3.lib: win32\sqlite3.dll
	+dumpbin /exports win32\sqlite3.dll > win32\exports.txt
	+echo LIBRARY SQLITE3 > win32\sqlite3.def
	+echo EXPORTS >> win32\sqlite3.def
	+for /f "skip=19 tokens=4" %A in (win32\exports.txt) do echo %A >> win32\sqlite3.def
	+lib /def:win32\sqlite3.def /out:win32\sqlite3.lib /machine:x86

win64\sqlite3.lib: win64\sqlite3.dll
	+dumpbin /exports win64\sqlite3.dll > win64\exports.txt
	+echo LIBRARY SQLITE3 > win64\sqlite3.def
	+echo EXPORTS >> win64\sqlite3.def
	+for /f "skip=19 tokens=4" %A in (win64\exports.txt) do echo %A >> win64\sqlite3.def
	+lib /def:win64\sqlite3.def /out:win64\sqlite3.lib /machine:x64
