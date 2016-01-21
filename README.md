# `d2sqlite3`

[![Build Status](https://travis-ci.org/biozic/d2sqlite3.svg)](https://travis-ci.org/biozic/d2sqlite3)
[![Coverage Status](https://coveralls.io/repos/github/biozic/d2sqlite3/badge.svg?branch=master)](https://coveralls.io/github/biozic/d2sqlite3?branch=master)

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

## Synopsis
```d
// Note: exception handling is left aside for clarity.

import std.typecons : Nullable;

// Open a database in memory.
auto db = Database(":memory:");

// Create a table
db.execute(
    "CREATE TABLE person (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        score FLOAT
     )"
);

// Populate the table

// Prepare an INSERT statement
auto statement = db.prepare(
    "INSERT INTO person (name, score)
     VALUES (:name, :score)"
);

// Bind values one by one (by parameter name or index)
statement.bind(":name", "John");
statement.bind(2, 77.5);
statement.execute();

statement.reset(); // Need to reset the statement after execution.

// Bind muliple values at once
statement.bindAll("John", null);
statement.execute();

// Count the changes
assert(db.totalChanges == 2);

// Count the Johns in the table.
auto count = db.execute("SELECT count(*) FROM person WHERE name == 'John'")
               .oneValue!long;
assert(count == 2);

// Read the data from the table lazily
auto results = db.execute("SELECT * FROM person");
foreach (row; results)
{
    // Retrieve "id", which is the column at index 0, and contains an int,
    // e.g. using the peek function (best performance).
    auto id = row.peek!long(0);

    // Retrieve "name", e.g. using opIndex(string), which returns a ColumnData.
    auto name = row["name"].as!string;

    // Retrieve "score", which is at index 2, e.g. using the peek function,
	// using a Nullable type
    auto score = row.peek!(Nullable!double)(2);
	if (!score.isNull) {
		// ...
	}
}

// Read all the table in memory at once
auto data = RowCache(db.execute("SELECT * FROM person"));
foreach (row; data)
{
    auto id = row[0].as!long;
    auto last = row["name"].as!string;
    auto score = row[2].as!(Nullable!double);
    // etc.
}
```
