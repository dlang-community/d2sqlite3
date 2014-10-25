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
// Open a database in memory.
Database db;
try
{
    db = Database(":memory:");
}
catch (SqliteException e)
{
    // Error creating the database
    assert(false, "Error: " ~ e.msg);
}

// Create a table.
try
{
    db.execute(
        "CREATE TABLE person (
            id INTEGER PRIMARY KEY,
            last_name TEXT NOT NULL,
            first_name TEXT,
            score REAL,
            photo BLOB
         )"
    );
}
catch (SqliteException e)
{
    // Error creating the table.
    assert(false, "Error: " ~ e.msg);
}

// Populate the table.
try
{
    auto query = db.query(
        "INSERT INTO person (last_name, first_name, score, photo)
         VALUES (:last_name, :first_name, :score, :photo)"
    );
    
    // Bind everything with chained calls to params.bind().
    query.bind(":last_name", "Smith");
    query.bind(":first_name", "John");
    query.bind(":score", 77.5);
    ubyte[] photo = cast(ubyte[]) "..."; // Store the photo as raw array of data.
    query.bind(":photo", photo);
    query.execute();
    
    query.reset(); // Need to reset the query after execution.
    query.bind(":last_name", "Doe");
    query.bind(":first_name", "John");
    query.bind(3, 46.8); // Use of index instead of name.
    query.bind(":photo", cast(ubyte[]) x"DEADBEEF");
    query.execute();
}
catch (SqliteException e)
{
    // Error executing the query.
    assert(false, "Error: " ~ e.msg);
}
assert(db.totalChanges == 2); // Two 'persons' were inserted.

// Reading the table
try
{
    // Count the Johns in the table.
    auto query = db.query("SELECT count(*) FROM person WHERE first_name == 'John'");
    assert(query.oneValue!long == 2);
    
    // Fetch the data from the table.
    query = db.query("SELECT * FROM person");
    foreach (row; query)
    {
        // Retrieve "id", which is the column at index 0, and contains an int,
        // e.g. using the peek function.
        auto id = row.peek!long(0);

        // Retrieve "score", which is at index 3, e.g. using the peek function.
        auto score = row.peek!double("score");

        // Retrieve "last_name" and "first_name", e.g. using opIndex(string),
        // which returns a Variant.
        auto name = format("%s, %s", row["last_name"].get!string, row["first_name"].get!string);

        // Retrieve "photo", e.g. using opIndex(index),
        // which returns a Variant.
        auto photo = row[4].get!(ubyte[]);
        
        // ... and use all these data!
    }
}
catch (SqliteException e)
{
    // Error reading the database.
    assert(false, "Error: " ~ e.msg);
}
```

---
License: BSL 1.0

Copyright 2011-14, Nicolas Sicard
