# `d2sqlite3`

[![Build Status](https://travis-ci.org/biozic/d2sqlite3.svg)](https://travis-ci.org/biozic/d2sqlite3)
[![Coverage Status](https://coveralls.io/repos/github/biozic/d2sqlite3/badge.svg?branch=master)](https://coveralls.io/github/biozic/d2sqlite3?branch=master)
 [![Dub](https://img.shields.io/dub/v/d2sqlite3.svg)](http://code.dlang.org/packages/d2sqlite3)

This is a small wrapper around SQLite for the D programming language.
It wraps the C API in an idiomatic manner and handles built-in D types and
`Nullable!T` automatically.

[Online documentation](http://biozic.github.io/d2sqlite3/d2sqlite3.html)

The SQLite library itself is not included: you have to link your projects to a version
of **SQLite >= 3.8.7**. If you use `dub`, add the following line to your `dub.json` file:
```json
    "libs": ["sqlite3"],
    "lflags": ["-L/path/to/lib"]
```
