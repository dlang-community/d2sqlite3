# Module `d2sqlite3`

[![Build Status](https://travis-ci.org/biozic/d2sqlite3.svg)](https://travis-ci.org/biozic/d2sqlite3)
[![Coverage Status](https://coveralls.io/repos/github/biozic/d2sqlite3/badge.svg?branch=master)](https://coveralls.io/github/biozic/d2sqlite3?branch=master)
[![Dub](https://img.shields.io/dub/v/d2sqlite3.svg)](http://code.dlang.org/packages/d2sqlite3)
[![Downloads](https://img.shields.io/dub/dt/d2sqlite3.svg)](https://code.dlang.org/packages/d2sqlite3)

This is a small wrapper around SQLite (version >= 3.8.7) for the D programming language.
It wraps the C API in an idiomatic manner and handles built-in D types and
`Nullable!T` automatically.

## Documentation

[Online documentation](http://biozic.github.io/d2sqlite3/d2sqlite3.html)

## `dub` configurations 

- **`with-lib`** (the default): assumes that SQLite is already installed and available to the linker. Set the right path for the SQLite library in your project's `dub.json` file using the `lflags` setting:
```json
    "lflags": ["-L/path/to/lib"]
```
- **`all-included`**: on Windows, use a prebuilt SQLite DLL (bundled with this library) -- **UNFINISHED**; on Posix systems, builds SQLite from the source amalgamation (also bundled with this library).
- **`without-lib`**: you manage linking SQLite yourself.

Set the right configuration for you project in its `dub.json` file using the `subConfigurations` setting, e.g.:
```json
    "subConfigurations": {
        "d2sqlite3": "all-included"
    }
```
