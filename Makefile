# SQLite3 for D makefile
# © 2011, Nicolas Sicard

# Commands
CC = cc
DC = dmd

# Configuration
CFLAGS = -O2 -arch i386 $(subst \c,, $(shell icu-config --cppflags))
LIBDIR = /opt/local/lib
DOC_DIR = doc
SQLITE_FLAGS = \
	SQLITE_ENABLE_COLUMN_METADATA \
	SQLITE_ENABLE_ICU \
	SQLITE_OMIT_AUTHORIZATION \
	SQLITE_OMIT_BUILTIN_TEST \
	SQLITE_OMIT_DEPRECATED \
	SQLITE_OMIT_GET_TABLE \
	SQLITE_OMIT_PROGRESS_CALLBACK \
	SQLITE_OMIT_TRACE \
	SQLITE_OMIT_WAL \

C_DEFINES = $(SQLITE_FLAGS:%=-D%)

C_SRC = c_source/sqlite3.c
C_OBJ = sqlite3.o
D_SRC = d2sqlite3.d

all: build doc unittest

build: $(C_OBJ)

$(C_OBJ): $(C_SRC)
	$(CC) $(CFLAGS) $(C_DEFINES) -c $< -o $@

.PHONY: clean doc unittest

unittest: $(C_OBJ) $(D_SRC)
	$(DC) -debug -w -unittest -cov $(C_OBJ) -version=SQLITE_ENABLE_ICU -L-L$(LIBDIR) -run $(D_SRC) 

doc: $(D_SRC)
	$(DC) -o- -c -Dd$(DOC_DIR) -D $(C_OBJ) $(D_SRC)

clean:
	-rm -f *.o
	-rm -f *.lst
	-rm -f $(DOC_DIR)/*html
	-rmdir $(DOC_DIR)
