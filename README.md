# d2sqlite3

This is a small wrapper around for SQLite (version 3) for the D programming language.
It provides a simple "object-oriented" interface to the SQLite database
engine.

## Features

1. `Database` is wrapper around a database connection. The connection is open at the time of its creation and it is automatically closed when no more references exist.

2. `Database` has facility functions create new functions, aggregates or collations.

3. `Query` is a wrapper around prepared statements and their results, with functionality to bind parameters, iterate on result rows with a lazy input range interface and convert column value to a built-in type or a Variant.

4. `QueryCache` is a helper struct that stores all the results of a query in memory in the form of a two-dimensional-array-like interface.

### Synopsis
```d
unittest
{
    // Note: exception handling is left aside for clarity.

    // Open a database in memory.
    auto db = Database(":memory:");

    // Create a table
    db.execute(
        "CREATE TABLE person (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            score FLOAT,
            photo BLOB
         )"
    );

    // Populate the table

    // Prepare an INSERT statement
    auto statement = db.prepare(
        "INSERT INTO person (name, score, photo)
         VALUES (:name, :score, :photo)"
    );

    // Bind values one by one (by parameter name or index)
    statement.bind(":name", "John");
    statement.bind(":score", 77.5);
    statement.bind(3, [0xDE, 0xEA, 0xBE, 0xEF]);
    statement.execute();

    statement.reset(); // Need to reset the statement after execution.

    // Bind muliple values at once
    statement.bindAll("John", 46.8, null);
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

        // Retrieve "score", which is at index 3, e.g. using the peek function.
        auto score = row.peek!double("score");

        // Retrieve "photo", e.g. using opIndex(index),
        // which returns a ColumnData.
        auto photo = row[3].as!(ubyte[]);

        // ... and use all these data!
    }

    // Read all the table in memory at once
    auto data = RowCache(db.execute("SELECT * FROM person"));
    foreach (row; data)
    {
        auto id = row[0].as!long;
        auto last = row["name"];
        auto score = row["score"].as!double;
        auto photo = row[3].as!(ubyte[]);
        // etc.
    }
}
```

---
License: BSL 1.0

Copyright 2011-14, Nicolas Sicard
