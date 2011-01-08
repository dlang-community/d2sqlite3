dmd -D -Dfsqlite.html -c -o- sqlite
rdmd -J. -L-L/opt/local/lib -debug -unittest --main sqlite.d
