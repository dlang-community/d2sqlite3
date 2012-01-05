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
    - convert column to D type: `as`
    
4. Optionnaly binds with ICU for more relevant collations.

## Issues

1. Alpha stage! Not thouroughly tested! (But in use as the database backend for one of my web applications).
2. BLOB handling is very basic (not taking advantage of BLOB I/O functions).

## Examples

Examples taken from the DDoc comments.

### Simple use
    // Open a database in memory.
    Database db;
    try
    {
        db = Database(":memory:");
    }
    catch (SqliteException e)
    {
        // Error opening the database.
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
                photo BLOB)"
        );
    }
    catch (SqliteException e)
    {
        // Error creating the table.
    }

    // Populate the table.
    try
    {
        auto query = db.query(
            "INSERT INTO person (last_name, first_name, score, photo)
             VALUES (:last_name, :first_name, :score, :photo)")
        );
    
        // Explicit transaction so that either all insertions succeed or none.
        db.begin();
        scope(failure) db.rollback();
        scope(success) db.commit();

        // Bind everything in one call to params.bind().
        query.params.bind(":last_name", "Smith",
                          ":first_name", "Robert",
                          ":score", 77.5);
        ubyte[] photo = ... // Store the photo as raw array of data.
        query.bind(":photo", photo);
        query.execute();

        query.reset(); // Need to reset the query after execution.
        query.params.bind(":last_name", "Doe",
                          ":first_name", "John",
                          3, null, // Use of index instead of name.
                          ":photo", null);
        query.execute();

        // Alternate use.
        query.params.bind(":last_name", "Amy");
        query.params.bind(":first_name", "Knight");
        query.params.bind(3, 89.1);
        query.params.bind(":photo", ...);
        query.execute();
    }
    catch (SqliteException e)
    {
        // Error executing the query.
    }
    assert(db.totalChanges == 3); // Three 'persons' were inserted.

    // Reading the table
    try
    {
        // Count the persons in the table (there should be two of them).
        auto query = db.query("SELECT count(*) FROM person");
        assert(query.rows.front[0].to!int == 2);

        // Fetch the data from the table.
        query = db.query("SELECT * FROM person");
        foreach (row; query.rows)
        {
            // "id" should be the column at index 0:
            auto id = row[0].as!int;
            // Some conversions are possible with the method as():
            auto name = format("%s, %s", row["last_name"].as!string, row["first_name"].as!(char[]));
            // The score can be NULL, so provide 0 (instead of NAN) as a default value to replace NULLs:
            auto score = row["score"].as!(real, 0.0);
            // Use of opDispatch with column name:
            auto photo = row.photo.as!(ubyte[]);
            ...
        }
    }
    catch (SqliteException e)
    {
        // Error reading the database.
    }

### Creating a function

    import std.string;

    static string my_repeat(string s, int i)
    {
        return std.string.repeat(s, i);
    }

    auto db = Database("");
    db.createFunction!my_repeat();

    auto query = db.query("SELECT my_repeat('*', 8)");
    assert(query.rows.front[0].as!string = "********");
    

### Creating an aggregate

    struct weighted_average
    {
        double total_value = 0.;
        double total_weight = 0.;

        void accumulate(double value, double weight)
        {
            total_value += value * weight;
            total_weight += weight;
        }

        double result()
        {
            return total_value / total_weight;
        }
    }

    auto db = Database("my_db.db");
    db.createAggregate!weighted_average();
    db.execute("CREATE TABLE test (value FLOAT, weight FLOAT)");
    ... // Populate the table.
    auto query = db.query("SELECT weighted_average(value, weight) FROM test");


---
Copyright 2011-12 by Nicolas Sicard