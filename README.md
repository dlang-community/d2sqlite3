# D2-SQLite3

This is a small binding for SQLite (version 3) for the D programming language (D2).
It provides a simple "object-oriented" interface to the SQLite database
engine. The complete C API is also available.

## Features

1. `Database` is wrapper around a database connection. The connection is open
at the time of its creation and it is automatically closed when no more references
exist. Possibility to enable a shared cache.

2. `Database` has facility functions to:
    - manage transactions and save points: `begin`, `commit`, `rollback`, `savepoint`, etc.
    - create new functions, aggregates or collations: `createFunction`, `createAggregate`, `createCollation`
    - directly execute SQL statements: `execute`
    - manage the database: `analyze`, `vaccum`, etc.

3. `Query` is a wrapper around prepared statements and their results, with functionality
to:
    - bind parameters: `params.bind`
    - iterate on result rows with an InputRange interface: `rows`
    - convert column to D type: `get`
    
4. Optionnaly binds with ICU for more relevant collations.

## Issues

1. Alpha stage! Not thouroughly tested! (But in use as the database backend for one of my web applications).
2. BLOB handling is very basic (not taking advantage of BLOB I/O functions).

---
Copyright 2011-13 by Nicolas Sicard