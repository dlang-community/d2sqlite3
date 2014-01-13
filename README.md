# d2sqlite3

This is a small wrapper around for SQLite (version 3) for the D programming language.
It provides a simple "object-oriented" interface to the SQLite database
engine.

## Features

1. `Database` is wrapper around a database connection. The connection is open
at the time of its creation and it is automatically closed when no more references
exist. Possibility to enable a shared cache.

2. `Database` has facility functions create new functions, aggregates or collations.

3. `Query` is a wrapper around prepared statements and their results, with functionality
to:
    - bind parameters: `params.bind`
    - iterate on result rows with an InputRange interface: `rows`
    - convert column to D type: `get`

## Issues

1. Alpha stage! Not thouroughly tested! (But in use as the database backend for one of my web applications).
2. BLOB handling is very basic (not taking advantage of BLOB I/O functions).

---
License: BSL 1.0

Copyright 2011-14, Nicolas Sicard
