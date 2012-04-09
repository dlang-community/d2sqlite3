# SQLite3 for D makefile
# © 2011, Nicolas Sicard

# Commands
DC = rdmd

# Configuration
SQLITE_LIB_DIR = /usr/local/lib
DOC_DIR = doc
D_SRC = d2sqlite3.d
D_SPECIAL_FLAGS = -version=SQLITE_ENABLE_ICU

all:

.PHONY: unittest

unittest:
	$(DC) -debug -w -property -unittest --main $(D_SPECIAL_FLAGS) -L-L$(SQLITE_LIB_DIR) $(D_SRC) 
