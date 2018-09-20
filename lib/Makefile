# This must be run from the relevant (x86/x86_64) VS Native Tools command interpreter.

# I'm taking the lazy and reliable route for forcing manual specification of
# x86/64 rather than try to determine it here.

.PHONY: no_build_specified x86 x64

no_build_specified:
	@echo Build either 'x86' or 'x64' from the respective VS command-line environment, or after running vcvarsall.bat.

x86: win32\sqlite3.lib

x64: win64\sqlite3.lib

win32\sqlite3.lib: win32\sqlite3.dll
	+lib /def:win32\sqlite3.def /out:win32\sqlite3.lib /machine:x86

win64\sqlite3.lib: win64\sqlite3.dll
	+lib /def:win64\sqlite3.def /out:win64\sqlite3.lib /machine:x64
