# This must be run from a VS Native Tools command interpreter, or after running
# vcvarsall.bat

.PHONY: all x86 x64

all: x86 x64

x86: win32\sqlite3.lib

x64: win64\sqlite3.lib

win32\sqlite3.lib: win32\sqlite3.dll
	+lib /def:win32\sqlite3.def /out:win32\sqlite3.lib /machine:x86

win64\sqlite3.lib: win64\sqlite3.dll
	+lib /def:win64\sqlite3.def /out:win64\sqlite3.lib /machine:x64
