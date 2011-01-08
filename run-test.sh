dmd -D -Dfsqlite.html -c -o- sqlite
rdmd -L-L/opt/local/lib -debug -unittest test.d
