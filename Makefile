# SQLite3 for D makefile
# © 2011, Nicolas Sicard

# Commands
CC = gcc
CFLAGS = -Os -arch i386
DC = dmd
DFLAGS = 

# Build
LIB_NAME = d2sqlite3
LIB_PREFIX = lib
LIB_EXT = .a
LIB_FILENAME = $(LIB_PREFIX)$(LIB_NAME)$(LIB_EXT)
BUILD_DIR = lib
BUILD_TARGET = $(BUILD_DIR)/$(LIB_FILENAME)
D_OPTIMIZATION = -O -inline -release
D_OPTIMIZATION = -debug
D_FLAGS = $(D_OPTIMIZATION) -of$(BUILD_DIR)/$(LIB_NAME)

# Sources
D_SRC = sqlite3.d \
        sql3fun.d \
		sql3schema.d

# DI files
DI_DIR = import
DI_FILES = $(D_SRC:.d=.di)

all: $(BUILD_TARGET) $(DI_FILES)

%.di: %.d
	dmd -o- -c -O -inline -release -H -Hd$(DI_DIR) $<

$(BUILD_TARGET): c_source/sqlite3.o $(D_SRC)
	dmd -O -inline -release -lib -od$(BUILD_DIR) -of$(LIB_FILENAME) c_source/sqlite3.o $(D_SRC)

c_source/sqlite3.o: c_source/sqlite3.c
	$(CC) -o c_source/sqlite3.o -c c_source/sqlite3.c $(CFLAGS)

clean:
	rm -f c_source/sqlite3.o
	rm -f $(BUILD_TARGET)
	rm -f $(DI_DIR)/*.di

unittest: c_source/sqlite3.o $(D_SRC)
	dmd -debug -w -unittest c_source/sqlite3.o -run $(D_SRC) 

doc: c_source/sqlite3.o $(D_SRC)
	dmd -o- -c -unittest c_source/sqlite3.o -Dddoc -D $(D_SRC)