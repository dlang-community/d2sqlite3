# SQLite3 for D makefile

CC = gcc
CFLAGS = -O3 -arch i386
DC = dmd
DFLAGS = 

LIBDIR = lib
LIBNAME = libdsqlite3
IMPORTDIR = import

all: $(LIBDIR)/$(LIBNAME).a $(IMPORTDIR)/dsqlite3.di

$(IMPORTDIR)/dsqlite3.di:
	dmd -o- -c -O -inline -release -H -Hd$(IMPORTDIR) c_source/sqlite3.o dsqlite3.d

$(LIBDIR)/$(LIBNAME).a: c_source/sqlite3.o dsqlite3.d
	dmd -O -inline -release -lib -od$(LIBDIR) -of$(LIBNAME) c_source/sqlite3.o dsqlite3.d

c_source/sqlite3.o: c_source/sqlite3.c
	$(CC) -o c_source/sqlite3.o -c c_source/sqlite3.c $(CFLAGS)

clean:
	rm -f c_source/sqlite3.o
	rm -f $(LIBDIR)/$(LIBNAME).a
	rm -f $(IMPORTDIR)/dsqlite3.di

unittest: c_source/sqlite3.o dsqlite3.d
	dmd -debug -w -unittest c_source/sqlite3.o -run dsqlite3.d
