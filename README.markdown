# D2 SQLite

This is a small binding for SQLite (version 3) for the D programming language.
It provides a simple "object-oriented" interface to the SQLite database
engine. The complete C API is also available.

## Example of use

    // Open a database in memory.
    Database db;
    try
    {
        db = Database(":memory:");
    }
    catch (SqliteException e)
    {
        // Error opening the database.
        return;
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
        with (db.query("INSERT INTO person
                        (last_name, first_name, score, photo)
                        VALUES (:last_name, :first_name, :score, :photo)"))
        {
            // Explicit transaction so that either all insertions succeed or none.
            db.begin;
            scope(failure) db.rollback;
            scope(success) db.commit;

            // Bind everything in one call to params.bind().
            params.bind(":last_name", "Smith",
                        ":first_name", "Robert",
                        ":score", 77.5);
            ubyte[] photo = ... // Store the photo as raw array of data.
            bind(":photo", photo);
            run;

            reset; // Need to reset the query after execution.
            params.bind(":last_name", "Doe",
                        ":first_name", "John",
                        3, null, // Use of index instead of name.
                        ":photo", null);
            run;
        }

        // Alternate use.
        with (db.query("INSERT INTO person
                        (last_name, first_name, score, photo)
                        VALUES (:last_name, :first_name, :score, :photo)"))
        {
            params.bind(":last_name", "Amy");
            params.bind(":first_name", "Knight");
            params.bind(3, 89.1);
            params.bind(":photo", ...);
            run;
        }
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


Copyright 2011, Nicolas Sicard