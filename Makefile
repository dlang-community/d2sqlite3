# SQLite3 for D makefile
# © 2011, Nicolas Sicard

# Configuration
LIB_NAME = d2sqlite3
LIB_PREFIX = lib
LIB_EXT = .a
BUILD_DIR = lib
CFLAGS = -Os -arch i386
DFLAGS = -O -inline -release
#D_OPTIMIZATION = -debug
DOC_DIR = doc
DI_DIR = import

# Commands
CC = cc
DC = dmd

# Build
LIB_FILENAME = $(LIB_PREFIX)$(LIB_NAME)$(LIB_EXT)
BUILD_TARGET = $(BUILD_DIR)/$(LIB_FILENAME)

# Sources
D_SRC = sqlite3.d

C_SRC_DIR = c_source
C_SRC = $(wildcard $(C_SRC_DIR)/*.c)
C_OBJ = $(C_SRC:.c=.o)

all: build doc unittest

build: $(C_OBJ) $(D_SRC)
	$(DC) $(DFLAGS) -lib -od$(BUILD_DIR) -of$(LIB_FILENAME) -H -Hd$(DI_DIR) $(C_OBJ) $(D_SRC)

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

#%.di: %.d
#	$(DC) -o- -c $(D_OPTIMIZATION) $<

.PHONY: clean doc unittest

unittest: $(C_OBJ) $(D_SRC)
	dmd -debug -w -unittest -cov $(C_OBJ) -run $(D_SRC) 

doc: $(D_SRC)
	dmd -o- -c -Dd$(DOC_DIR) -D $(C_OBJ) $(D_SRC)

clean:
	-rm -f $(C_SRC_DIR)/*.o
	-rm -f $(BUILD_TARGET)
	-rmdir $(BUILD_DIR)
	-rm -f $(DI_DIR)/*.di
	-rmdir $(DI_DIR)
	-rm -f *.lst
	-rm -f $(DOC_DIR)/*html
	-rmdir $(DOC_DIR)
