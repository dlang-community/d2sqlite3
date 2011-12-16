# SQLite3 for D makefile
# © 2011, Nicolas Sicard

# Commands
CC = cc
DC = dmd

# Configuration
CFLAGS = -O2
#CFLAGS += -arch i386
#CFLAGS += $(subst \c,, $(shell icu-config --cppflags))
LIBDIR = /usr/local/lib
DOC_DIR = doc
SQLITE_FLAGS = \
	SQLITE_ENABLE_COLUMN_METADATA \
	SQLITE_OMIT_AUTHORIZATION \
	SQLITE_OMIT_BUILTIN_TEST \
	SQLITE_OMIT_DEPRECATED \
	SQLITE_OMIT_GET_TABLE \
	SQLITE_OMIT_PROGRESS_CALLBACK \
	SQLITE_OMIT_TRACE \
	SQLITE_OMIT_WAL
#SQLITE_FLAGS += SQLITE_ENABLE_ICU

C_SRC = c_source/sqlite3.c
C_OBJ = sqlite3.o
D_SRC = d2sqlite3.d

all: build unittest doc

build: $(C_OBJ)

$(C_OBJ): $(C_SRC)
	$(CC) $(CFLAGS) $(SQLITE_FLAGS:%=-D%) -c $< -o $@

.PHONY: clean doc unittest

unittest: $(C_OBJ) $(D_SRC)
	$(DC) -debug -w -property -unittest -cov $(C_OBJ) -version=NOT_SQLITE_ENABLE_ICU -L-L$(LIBDIR) -run $(D_SRC) 

doc: $(D_SRC)
	$(DC) -o- -c -Dd$(DOC_DIR) -D $(C_OBJ) $(D_SRC)

clean:
	-rm -f *.o
	-rm -f *.lst
	-rm -f $(DOC_DIR)/*html
	-rmdir $(DOC_DIR)
