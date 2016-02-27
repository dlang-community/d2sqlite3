all: sqlite3.o
	
sqlite3.o: c/sqlite3.c
	gcc -c -O2 c/sqlite3.c
	
clean:
	rm -f *.o