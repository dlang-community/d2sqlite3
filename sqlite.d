// Written in the D programming language
/++
Simple SQLite interface.

This module provides a simple "object-oriented" interface to the SQLite
database engine. The complete C API is also available.

Objects in this interface (Database and Query) automatically create the SQLite
objects they need. They are reference-counted, so that when their last
reference goes out of scope, the underlying SQLite objects are automatically
closed and finalized. They are not thread-safe, while the SQLite database
engine itself can be.

Executables using this module must be linked to the SQLite library version
3.3.11 or later.

Usage:
$(OL
    $(LI Create a Database object, providing the path of the database file (or
    an empty path, or the reserved path ":memory:").)
    $(LI Execute SQL code according to your need:
    $(UL
        $(LI If you don't need parameter binding, create a Query object with a
        single SQL statement and either use Query.run() if you don't expect
        the query to return rows, or use Query.rows() directly in the other
        case.)
        $(LI If you need parameter binding, create a Query object with a
        single SQL statement that includes binding names, and use Query.bind()
        as many times as necessary to bind all values. Then either use
        Query.run() if you don't expect the query to return rows, or use
        Query.rows() directly in the other case.)
        $(LI If you don't need parameter bindings and if you can ignore the
        rows that the query could return, you can use the facility function
        Database.execute(). In this case, more than one statements can be run
        in one call, as long as they are separated by semi-colons.)
    ))
)

Example:
---
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
    with (Query(db, "INSERT INTO person
                    (last_name, first_name, score, photo)
                    VALUES (:last_name, :first_name, :score, :photo)"))
    {
        // Explicit transaction so that either all insertions succeed or none.
        db.execute("BEGIN TRANSACTION");
        scope(failure) db.execute("ROLLBACK TRANSACTION");
        scope(success) db.execute("COMMIT TRANSACTION");

        bind(":last_name", "Smith",
             ":first_name", "Robert",
             ":score", 77.5);
        ubyte[] photo = ... // store the photo as raw array of data.
        bind(":photo", photo);
        run;

        reset; // need to reset the query after execution.
        bind(":last_name", "Doe",
             ":first_name", "John",
             ":score", null,
             ":photo", null);
        run;
    }
}
catch (SqliteException e)
{
    // Error executing the query.
}
assert(db.totalChanges == 2); // Two 'persons' were inserted.

// Reading the table
try
{
    // Count the persons in the table (there should be two of them).
    auto query = Query(db, "SELECT COUNT(*) FROM person");
    assert(query.rows.front[0].to!int == 2);

    // Fetch the data from the table.
    query = Query(db, "SELECT * FROM person");
    foreach (row; query.rows)
    {
        auto id = row["id"].as!int;
        auto name = format("%s, %s", row["last_name"].as!string, row["first_name"].as!string);
        // the score can be NULL, so provide 0 (instead of NAN) as a default value to replace NULLs.
        auto score = row["score"].as!(real, 0.0);
        auto photo = row["photo"].as!(void[]);
        ... // Use the data.
    }
}
catch (SqliteException e)
{
    // Error reading the database.
}
---

Copyright: Copyright Nicolas Sicard, 2011.

License: no license yet.

Author: Nicolas Sicard.
+/
module sqlite;

import std.algorithm;
import std.conv;
import std.exception;
import std.string;
import std.range;
import std.traits;
import std.utf;
import std.variant;

pragma(lib, "sqlite3");

//debug=SQLITE;
debug(SQLITE) import std.stdio;
version(unittest) { import std.stdio; }

/++
Exception thrown then SQLite functions return error codes.
+/
class SqliteException : Exception {
    int code;
    this(string msg, int code = -1) {
        string text;    
        if (code > 0)
            text = format("error %d: %s", code, msg);
        else
            text = msg;
        super(text);
        this.code = code;
    }
}

/++
Metadata of the SQLite library.
+/
struct Sqlite {
    /// Gets the library's version string (e.g. 3.6.12).
    static string versionString() {
        return to!string(sqlite3_libversion());
    }

    /// Gets the library's version number (e.g. 3006012).
    static int versionNumber() {
        return sqlite3_libversion_number();
    }
}

/++
An interface to a SQLite database connection.
+/
struct Database {
    private struct _core {
        double a;           // BUG if a.sizeof % 8 != 0
        sqlite3* handle;
        int refcount;
    }
    private _core core;

    /++
    Opens a database with the name passed in the parameter.
    Params:
        path = the path of the database file. Can be empty or set to
        ":memory:" according to the SQLite specification.
    Throws:
        SqliteException when the database cannot be opened.
    +/
    this(string path) {
        assert(path);
        auto result = sqlite3_open(cast(char*) path.toStringz, &core.handle);
        checkResultCode(result == SQLITE_OK, result);
        core.refcount = 1;
    }

    this(this) {
        core.refcount++;
    }

    ~this() {
        core.refcount--;
        if (core.refcount == 0) {
            auto result = sqlite3_close(core.handle);
            if (result != SQLITE_OK)
                throw new SqliteException("could not close database", result);
        }
    }

    void opAssign(Database rhs) {
        swap(core, rhs.core);
    }

    /++
    Execute one or many SQL statements. Rows returned by any of these statements
    are ignored.
    Throws:
        SqliteException in one of the SQL statements cannot be executed.
    +/
    void execute(string sql) {
        char* errmsg;
        sqlite3_exec(core.handle, cast(char*) sql.toStringz, null, null, &errmsg);
        if (errmsg !is null) {
            auto msg = to!string(errmsg);
            sqlite3_free(errmsg);
            throw new SqliteException(msg, errorCode);
        }
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted by
    the most recently completed query.
    +/
    @property int changes() {
        assert(core.handle);
        return sqlite3_changes(core.handle);
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted
    since the database was opened.
    +/
    @property int totalChanges() {
        assert(core.handle);
        return sqlite3_total_changes(core.handle);
    }

    /++
    Gets the SQLite error code of the last operation.
    +/
    @property int errorCode() {
        assert(core.handle);
        return sqlite3_errcode(core.handle);
    }

    /++
    Gets the SQLite error message of the last operation, including the error code.
    +/
    @property string errorMsg() {
        assert(core.handle);
        return to!string(sqlite3_errmsg(core.handle));
    }

    /++
    Gets the SQLite internal _handle of the database connection.
    +/
    @property sqlite3* handle() {
        assert(core.handle);
        return core.handle;
    }

    private void checkResultCode(bool pred, int code) {
        if (!pred) {
            string text = "";
            if (code == errorCode)
                text = errorMsg;
            throw new SqliteException(text, code);
        }
    }
}

/++
An interface to SQLite query execution.
+/
struct Query {
    private struct _core {
        Database* db;
        string sql;
        sqlite3_stmt* statement;
        int refcount;
        RowSet rows = void;
    }
    private _core core;

    /++
    Creates a new SQL query on an open database.
    Params:
        db = the database on which the query will be run.
        sql = the text of the query.
    Throws:
        SqliteException when the query cannot be prepared.
    +/
    this(ref Database db, string sql) {
        db.core.refcount++;
        core.db = &db;
        core.sql = sql;
        auto result = sqlite3_prepare_v2(
            core.db.handle,
            cast(char*) core.sql.toStringz,
            core.sql.length,
            &core.statement,
            null
        );
        core.db.checkResultCode(result == SQLITE_OK, result);
        core.refcount = 1;
        core.rows = RowSet(&this);
    }

    this(this) {
        core.refcount++;
    }

    ~this() {
        core.refcount--;
        if (core.refcount == 0) {
            if (core.statement)
                sqlite3_finalize(core.statement);
            core.db.core.refcount--;
        }
    }

    void opAssign(Query rhs) {
        swap(core, rhs.core);
    }

    /++
    Binds values to named parameters in the query.
    Params:
        args = a tuple of the parameters and bound values. Even positions in
        the tuple: the names or the indices of the parameters to _bind to in
        the SQL prepared statement (the name must include the symbol
        preceeding the actual name, e.g. ":id"). Odd positions in the tuple:
        the bound values.
    Throws:
        SqliteException when parameter refers to an invalid binding or when
        the value cannot be bound.
    +/
    void bind(T...)(T args) {
        static assert(args.length >=2 && args.length % 2 == 0, "unexpected number of parameters");

        alias args[0] key;
        alias typeof(key) K;
        alias args[1] value;
        alias typeof(args[1]) V;

        static assert(isSomeString!K || isImplicitlyConvertible!(K, int), "unexpected type for column reference: " ~ K.stringof);
        
        assert(core.statement);
        
        static if (isSomeString!K) {
            // If key is a string, find the correspondig index
            int index = sqlite3_bind_parameter_index(core.statement, cast(char*) key.toStringz);
            enforceEx!SqliteException(index > 0, format("parameter named '%s' cannot be bound", key));            
        } else
            int index = key;

        int result;
        static if (isImplicitlyConvertible!(Unqual!V, long))
            result = sqlite3_bind_int64(core.statement, index, cast(long) value);
        else static if (isImplicitlyConvertible!(Unqual!V, real))
            result = sqlite3_bind_double(core.statement, index, value);
        else static if (isSomeString!V) {
            if (value is null)
                result = sqlite3_bind_null(core.statement, index);
            else {
                string utf8 = value.toUTF8;
                result = sqlite3_bind_text(core.statement, index, cast(char*) utf8.toStringz, utf8.length, null);
            }
        }
        else static if (isPointer!V && !is(V == void*)) {
            if (value is null)
                result = sqlite3_bind_null(core.statement, index);
            else {
                bind(index, *value);
                return;
            }
        }
        else static if (is(V == void*))
            result = sqlite3_bind_null(core.statement, index);
        else static if (isArray!V) {
            void[] buffer = cast(void[]) value;
            result = sqlite3_bind_blob(core.statement, index, cast(void*) buffer.ptr, buffer.length, null);
        }
        else static if (!is(V == void)) {
            void[] buffer;
            buffer.length = V.sizeof;
            memcpy(buffer.ptr, &value, buffer.length);
            result = sqlite3_bind_blob( core.statement, index, cast(void*) buffer.ptr, buffer.length, null);
        }
        else
            static assert(false, "cannot bind a value of type " ~ V.stringof);

        core.db.checkResultCode(result == SQLITE_OK, result);
        
        static if (args.length >= 4)
            bind(args[2 .. $]);
    }

    /++
    Gets the results of a query that returns _rows.
    
    There is no need to call run() before a call to rows().
    +/
    @property ref RowSet rows() {
        if (!core.rows.isInitialized)
            core.rows.initialize;
        return core.rows;
    }
    
    /++
    Executes the query.
    
    Use rows() directly if the query is expected to return rows. 
    +/
    void run() {
        rows();
    }

    /++
    Resets a query, optionally clearing all bindings.
    Params:
        clearBindings = sets whether the bindings should also be cleared.
    Throws:
        SqliteException when the query could not be reset.
    +/
    void reset(bool clearBindings = true) {
        auto result = sqlite3_reset(core.statement);
        core.db.checkResultCode(result == SQLITE_OK, result);
        if (clearBindings)
            sqlite3_clear_bindings(core.statement);
        core.rows = RowSet(&this);
    }
}

/++
The results of a query that returns rows, with an InputRange interface.
+/
struct RowSet {
    private Query* query;
    private int sqliteResult = SQLITE_DONE;
    private bool isInitialized = false;

    private this(Query* query) {
        this.query = query;
    }

    private void initialize() {
        sqliteResult = sqlite3_step(query.core.statement);
        query.core.db.checkResultCode(sqliteResult == SQLITE_ROW || sqliteResult == SQLITE_DONE, sqliteResult);
        isInitialized = true;
    }

    /++
    Tests whether no more rows are available.
    +/
    @property bool empty() {
        assert(query.core.statement);
        return sqliteResult == SQLITE_DONE;
    }

    /++
    Gets the current row.
    +/
    @property Row front() {
        assert(query.core.statement);
        Row row;
        auto colcount = sqlite3_column_count(query.core.statement);
        row.columns.reserve(colcount);
        for (int i = 0; i < colcount; i++) {
            auto name = to!string(sqlite3_column_name(query.core.statement, i));
            auto type = sqlite3_column_type(query.core.statement, i);
            final switch (type) {
            case SQLITE_INTEGER:
                row.columns ~= Column(i, name, Variant(sqlite3_column_int64(query.core.statement, i)));
                break;

            case SQLITE_FLOAT:
                row.columns ~= Column(i, name, Variant(sqlite3_column_double(query.core.statement, i)));
                break;

            case SQLITE_TEXT:
                auto str = to!string(sqlite3_column_text(query.core.statement, i));
                row.columns ~= Column(i, name, Variant(str));
                break;

            case SQLITE_BLOB:
                auto ptr = sqlite3_column_blob(query.core.statement, i);
                auto length = sqlite3_column_bytes(query.core.statement, i);
                ubyte[] blob;
                blob.length = length;
                memcpy(blob.ptr, ptr, length);
                row.columns ~= Column(i, name, Variant(blob));
                break;

            case SQLITE_NULL:
                row.columns ~= Column(i, name, Variant());
                break;
            }
        }
        return row;
    }

    /++
    Jumps to the next row.
    +/
    void popFront() {
        assert(query.core.statement);
        sqliteResult = sqlite3_step(query.core.statement);
    }
}

/++
A SQLite row.
+/
struct Row {
    private Column[] columns;

    /++
    Gets the number of columns in this row.
    +/
    @property int columnCount() {
        return columns.length;
    }

    /++
    Gets the column at the given index.
    Params:
        index = the index of the column in the SELECT statement.
    Throws:
        SqliteException when the index is invalid.
    +/
    Column opIndex(int index) {
        auto f = filter!((Column c) { return c.index == index; })(columns);
        if (!f.empty)
            return f.front;
        else
            throw new SqliteException(format("invalid column index: %d", index));
    }

    /++
    Gets the column from its name.
    Params:
        name = the name of the column in the SELECT statement.
    Throws:
        SqliteException when the name is invalid.
    +/
    Column opIndex(string name) {
        auto f = filter!((Column c) { return c.name == name; })(columns);
        if (!f.empty)
            return f.front;
        else
            throw new SqliteException("invalid column name: " ~ name);
    }
}

/++
A SQLite column.
+/
struct Column {
    private int index;
    private string name;
    private Variant data;

    /++
    Gets the value of the column converted _to type T.
    If the value is NULL, it is replaced by value.
    +/
    @property T as(T, T value = T.init)() {
        if (data.hasValue) {
            static if (is(Unqual!T == bool))
                return cast(T) data.get!long != 0;
            else static if (isIntegral!T)
                return std.conv.to!T(data.get!long);
            else static if (isSomeChar!T)
                return std.conv.to!T(data.get!string[0]);
            else static if (isFloatingPoint!T)
                return std.conv.to!T(data.get!double);
            else static if (isSomeString!T) {
                static if (is(Unqual!T == string))
                    return cast(T) data.get!string;
                else static if (is(Unqual!T == wstring))
                    return cast(T) data.get!string.toUTF16;
                else
                    return cast(T) data.get!string.toUTF32;
            }
            else static if (isArray!T)
                return cast(T) data.get!(ubyte[]);
            else {
                Unqual!T result = void;
                auto store = data.get!(ubyte[]);
                memcpy(&result, store.ptr, result.sizeof);
                return result;
            }
        }
        else
            return value;
    }
}

//-----------------------------------------------------------------------------
// TESTS
//-----------------------------------------------------------------------------
unittest {
    assert(Sqlite.versionNumber > 3003011);
}

unittest {
    // Kind of tests copy-construction
    void makeDatabase(out Database db) {
        db = Database(":memory:");
    }
    void makeQuery(out Query query, Database db) {
        query = Query(db, "PRAGMA encoding");
    }
    string readEncoding(Query query) {
        return query.rows.front[0].as!string;
    }
    Database db;
    Query query;
    makeDatabase(db);
    makeQuery(query, db);
    assert(readEncoding(query).startsWith("UTF"));
}

unittest {
    // Tests empty statements
    auto db = Database(":memory:");
    
    try
        db.execute(";");
    catch (SqliteException e)
        assert(e.code == SQLITE_MISUSE);
    
    try {
        auto query = Query(db, ";");
        auto rows = query.rows;
    }
    catch (SqliteException e)
        assert(e.code == SQLITE_MISUSE);
}

unittest {
    // Tests multiple statements in query string
    auto db = Database(":memory:");
    int result;
    try
        db.execute("CREATE TABLE test (val INTEGER);CREATE TABLE test (val INTEGER)");
    catch (SqliteException e)
        assert(e.code == SQLITE_ERROR);
}

unittest {
    // Tests Query.rows()
    static assert(isInputRange!RowSet);
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", 1024);
    query.run;
    query = Query(db, "SELECT * FROM test");
    assert(!query.rows.empty);
    assert(query.rows.front["val"].as!int == 1024);
    query.rows.popFront();
    assert(query.rows.empty);
}

unittest {
    // Tests Database.changes() and Database.totalChanges()
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");
    assert(db.changes == 0);
    assert(db.totalChanges == 0);

    auto query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", 1024);
    query.run;
    assert(db.changes == 1);
    assert(db.totalChanges == 1);
}

unittest {
    // Tests NULL values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", null);
    query.run;

    query = Query(db, "SELECT * FROM test");
    assert(query.rows.front["val"].as!(int, -1024) == -1024);
}

unittest {
    // Tests INTEGER values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    int i = 1;
    query.bind(":val", &i);
    query.run;
    query.reset;
    query.bind(":val", 1L);
    query.run;
    assert(db.changes == 1);
    assert(db.totalChanges == 2);
    query.reset;
    query.bind(":val", 1U);
    query.run;
    query.reset;
    query.bind(":val", 1UL);
    query.run;
    query.reset;
    query.bind(":val", true);
    query.run;
    query.reset;
    query.bind(":val", '\&copy;');
    query.run;
    query.reset;
    query.bind(":val", '\x72');
    query.run;
    query.reset;
    query.bind(":val", '\u1032');
    query.run;
    query.reset;
    query.bind(":val", '\U0000FF32');
    query.run;

    query = Query(db, "SELECT * FROM test");
    foreach (row; query.rows)
        assert(row["val"].as!long > 0);
}

unittest {
    // Tests FLOAT values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val FLOAT)");

    auto query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", 1.0F);
    query.run;
    query.reset;
    query.bind(":val", 1.0);
    query.run;
    query.reset;
    query.bind(":val", 1.0L);
    query.run;

    query = Query(db, "SELECT * FROM test");
    foreach (row; query.rows)
        assert(row["val"].as!real > 0);
}

unittest {
    // Tests TEXT values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val TEXT)");

    auto query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B"c);
    query.run;
    query.reset;
    query.bind(":val", "\uC720\uB2C8\uCF5B"w);
    query.run;
    query.reset;
    query.bind(":val", "\uC720\uB2C8\uCF5B"d);
    query.run;

    query = Query(db, "SELECT * FROM test");
    foreach (row; query.rows) {
        assert(row["val"].as!string ==  "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B"c);
        assert(row["val"].as!wstring ==  "\uC720\uB2C8\uCF5B"w);
    }
}

unittest {
    // Tests BLOB values with arrays
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val BLOB)");

    auto query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    int[] array = [1, 2, 3, 4];
    query.bind(":val", array);
    query.run;

    query = Query(db, "SELECT * FROM test");
    assert(query.rows.front["val"].as!(int[]) == [1, 2, 3, 4]);
}

unittest {
    // Tests BLOB values with structs
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val BLOB)");

    struct Data {
        int integer;
        char character;
        real number;
        string text;
        
        string toString() {
            return format("%d %s %.2f %s", integer, character, number, text);
        }
        
    }

    auto query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    auto original = Data(1024, 'z', 3.14159, "foo");
    query.bind(":val", original);
    query.run;

    query = Query(db, "SELECT * FROM test");
    auto copy = query.rows.front["val"].as!Data;
    assert(copy.toString == "1024 z 3.14 foo");
}

unittest {
    // Tests multiple bindings
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto query = Query(db, "INSERT INTO test (i, f, t) VALUES (:i, :f, :t)");
    query.bind(":t", "TEXT", ":i", 1024, ":f", 3.14);
    query.run;
    query.reset;
    query.bind(3, "TEXT", 1, 1024, 2, 3.14);
    query.run;
    
    query = Query(db, "SELECT * FROM test");
    foreach (row; query.rows) {
        assert(row["i"].as!int == 1024);
        assert(row["f"].as!double == 3.14);
        assert(row["t"].as!string == "TEXT");
    }
}

//-----------------------------------------------------------------------------
// SQLite C API
//-----------------------------------------------------------------------------
private:

enum {
	SQLITE_OK = 0,
	SQLITE_ERROR,
	SQLITE_INTERNAL,
	SQLITE_PERM,
	SQLITE_ABORT,
	SQLITE_BUSY,
	SQLITE_LOCKED,
	SQLITE_NOMEM,
	SQLITE_READONLY,
	SQLITE_INTERRUPT,
	SQLITE_IOERR,
	SQLITE_CORRUPT,
	SQLITE_NOTFOUND,
	SQLITE_FULL,
	SQLITE_CANTOPEN,
	SQLITE_PROTOCOL,
	SQLITE_EMPTY,
	SQLITE_SCHEMA,
	SQLITE_TOOBIG,
	SQLITE_CONSTRAINT,
	SQLITE_MISMATCH,
	SQLITE_MISUSE,
	SQLITE_NOLFS,
	SQLITE_AUTH,
	SQLITE_FORMAT,
	SQLITE_RANGE,
	SQLITE_NOTADB,
	SQLITE_ROW = 100,
	SQLITE_DONE
}

enum {
    SQLITE_INTEGER = 1,
    SQLITE_FLOAT = 2,
    SQLITE_TEXT = 3,
    SQLITE_BLOB = 4,
    SQLITE_NULL = 5,
}

struct sqlite3 {}
struct sqlite3_stmt {}
struct sqlite3_context {}
struct sqlite3_value {}
struct sqlite3_blob {}
struct sqlite3_module {}
struct sqlite3_mutex {}
struct sqlite3_backup {}
struct sqlite3_vfs {}

alias int function(void*,int,char**,char**) sqlite3_callback;

extern(C):
void* sqlite3_aggregate_context(sqlite3_context*,int);
int sqlite3_aggregate_count(sqlite3_context*);
int sqlite3_bind_blob(sqlite3_stmt*,int,void*,int n,void function(void*));
int sqlite3_bind_double(sqlite3_stmt*,int,double);
int sqlite3_bind_int(sqlite3_stmt*,int,int);
int sqlite3_bind_int64(sqlite3_stmt*,int,long);
int sqlite3_bind_null(sqlite3_stmt*,int);
int sqlite3_bind_parameter_count(sqlite3_stmt*);
int sqlite3_bind_parameter_index(sqlite3_stmt*,char*);
char* sqlite3_bind_parameter_name(sqlite3_stmt*,int);
int sqlite3_bind_text(sqlite3_stmt*,int,char*,int n,void function(void*));
int sqlite3_bind_text16(sqlite3_stmt*,int,void*,int,void function(void*));
int sqlite3_bind_value(sqlite3_stmt*,int, sqlite3_value*);
int sqlite3_busy_handler(sqlite3*,int function(void*,int),void*);
int sqlite3_busy_timeout(sqlite3*,int);
int sqlite3_changes(sqlite3*);
int sqlite3_close(sqlite3*);
int sqlite3_collation_needed(sqlite3*,void*,void function(void*,sqlite3*,int,char*));
int sqlite3_collation_needed16(sqlite3*,void*,void function(void*,sqlite3*,int,void*));
void* sqlite3_column_blob(sqlite3_stmt*,int);
int sqlite3_column_bytes(sqlite3_stmt*,int);
int sqlite3_column_bytes16(sqlite3_stmt*,int);
int sqlite3_column_count(sqlite3_stmt*);
char* sqlite3_column_database_name(sqlite3_stmt*,int);
void* sqlite3_column_database_name16(sqlite3_stmt*,int);
char* sqlite3_column_decltype(sqlite3_stmt*,int);
void* sqlite3_column_decltype16(sqlite3_stmt*,int);
double sqlite3_column_double(sqlite3_stmt*,int);
int sqlite3_column_int(sqlite3_stmt*,int);
long sqlite3_column_int64(sqlite3_stmt*,int);
char* sqlite3_column_name(sqlite3_stmt*,int);
void* sqlite3_column_name16(sqlite3_stmt*,int);
char* sqlite3_column_origin_name(sqlite3_stmt*,int);
void* sqlite3_column_origin_name16(sqlite3_stmt*,int);
char* sqlite3_column_table_name(sqlite3_stmt*,int);
void* sqlite3_column_table_name16(sqlite3_stmt*,int);
char* sqlite3_column_text(sqlite3_stmt*,int);
void* sqlite3_column_text16(sqlite3_stmt*,int);
int sqlite3_column_type(sqlite3_stmt*,int);
sqlite3_value* sqlite3_column_value(sqlite3_stmt*,int);
void* sqlite3_commit_hook(sqlite3*,int function(void*),void*);
int sqlite3_complete(char*);
int sqlite3_complete16(void*);
int sqlite3_create_collation(sqlite3*,char*,int,void*,int function(void*,int,void*,int,void*));
int sqlite3_create_collation16(sqlite3*,void*,int,void*,int function(void*,int,void*,int,void*));
int sqlite3_create_function(sqlite3*,char*,int,int,void*,void function(sqlite3_context*,int,sqlite3_value**),void function(sqlite3_context*,int,sqlite3_value**),void function(sqlite3_context*));
int sqlite3_create_function16(sqlite3*,void*,int,int,void*,void function(sqlite3_context*,int,sqlite3_value**),void function(sqlite3_context*,int,sqlite3_value**),void function(sqlite3_context*));
int sqlite3_create_module(sqlite3*,char*,sqlite3_module*,void*);
int sqlite3_data_count(sqlite3_stmt*);
sqlite3* sqlite3_db_handle(sqlite3_stmt*);
int sqlite3_declare_vtab(sqlite3*,char*);
int sqlite3_enable_shared_cache(int);
int sqlite3_errcode(sqlite3*);
char* sqlite3_errmsg(sqlite3*);
void* sqlite3_errmsg16(sqlite3*);
int sqlite3_exec(sqlite3*,char*,sqlite3_callback,void*,char**);
int sqlite3_expired(sqlite3_stmt*);
int sqlite3_finalize(sqlite3_stmt*pStmt);
void sqlite3_free(void*);
void sqlite3_free_table(char**result);
int sqlite3_get_autocommit(sqlite3*);
void* sqlite3_get_auxdata(sqlite3_context*,int);
int sqlite3_get_table(sqlite3*,char*,char***,int*,int*,char**);
int sqlite3_global_recover();
void sqlite3_interruptx(sqlite3*);
long sqlite3_last_insert_rowid(sqlite3*);
char* sqlite3_libversion();
int sqlite3_libversion_number();
void* sqlite3_malloc(int);
char* sqlite3_mprintf(char*,...);
int sqlite3_open(char*,sqlite3**);
int sqlite3_open16(void*,sqlite3**);
int sqlite3_prepare(sqlite3*,char*,int,sqlite3_stmt**,char**);
int sqlite3_prepare16(sqlite3*,void*,int,sqlite3_stmt**,void**);
void* sqlite3_profile(sqlite3*,void function(void*,char*,ulong),void*);
void sqlite3_progress_handler(sqlite3*,int,int function(void*),void*);
void* sqlite3_realloc(void*,int);
int sqlite3_reset(sqlite3_stmt*);
void sqlite3_result_blob(sqlite3_context*,void*,int,void function(void*));
void sqlite3_result_double(sqlite3_context*,double);
void sqlite3_result_error(sqlite3_context*,char*,int);
void sqlite3_result_error16(sqlite3_context*,void*,int);
void sqlite3_result_int(sqlite3_context*,int);
void sqlite3_result_int64(sqlite3_context*,long);
void sqlite3_result_null(sqlite3_context*);
void sqlite3_result_text(sqlite3_context*,char*,int,void function(void*));
void sqlite3_result_text16(sqlite3_context*,void*,int,void function(void*));
void sqlite3_result_text16be(sqlite3_context*,void*,int,void function(void*));
void sqlite3_result_text16le(sqlite3_context*,void*,int,void function(void*));
void sqlite3_result_value(sqlite3_context*,sqlite3_value*);
void* sqlite3_rollback_hook(sqlite3*,void function(void*),void*);
int sqlite3_set_authorizer(sqlite3*,int function(void*,int,char*,char*,char*,char*),void*);
void sqlite3_set_auxdata(sqlite3_context*,int,void*,void function(void*));
char* sqlite3_snprintf(int,char*,char*,...);
int sqlite3_step(sqlite3_stmt*);
int sqlite3_table_column_metadata(sqlite3*,char*,char*,char*,char**,char**,int*,int*,int*);
void sqlite3_thread_cleanup();
int sqlite3_total_changes(sqlite3*);
void* sqlite3_trace(sqlite3*,void function(void*,char*),void*);
int sqlite3_transfer_bindings(sqlite3_stmt*,sqlite3_stmt*);
void* sqlite3_update_hook(sqlite3*,void function(void*,int ,char*,char*,long),void*);
void* sqlite3_user_data(sqlite3_context*);
void* sqlite3_value_blob(sqlite3_value*);
int sqlite3_value_bytes(sqlite3_value*);
int sqlite3_value_bytes16(sqlite3_value*);
double sqlite3_value_double(sqlite3_value*);
int sqlite3_value_int(sqlite3_value*);
long sqlite3_value_int64(sqlite3_value*);
int sqlite3_value_numeric_type(sqlite3_value*);
char* sqlite3_value_text(sqlite3_value*);
void* sqlite3_value_text16(sqlite3_value*);
void* sqlite3_value_text16be(sqlite3_value*);
void* sqlite3_value_text16le(sqlite3_value*);
int sqlite3_value_type(sqlite3_value*);
char* sqlite3_vmprintf(char*,...);
int sqlite3_overload_function(sqlite3*, char*, int);
int sqlite3_prepare_v2(sqlite3*,char*,int,sqlite3_stmt**,char**);
int sqlite3_prepare16_v2(sqlite3*,void*,int,sqlite3_stmt**,void**);
int sqlite3_clear_bindings(sqlite3_stmt*);
int sqlite3_create_module_v2(sqlite3*,char*, sqlite3_module*,void*,void function(void*));
int sqlite3_bind_zeroblob(sqlite3_stmt*,int,int);
int sqlite3_blob_bytes(sqlite3_blob*);
int sqlite3_blob_close(sqlite3_blob*);
int sqlite3_blob_open(sqlite3*,char*,char*,char*,long,int,sqlite3_blob**);
int sqlite3_blob_read(sqlite3_blob*,void*,int,int);
int sqlite3_blob_write(sqlite3_blob*,void*,int,int);
int sqlite3_create_collation_v2(sqlite3*,char*,int,void*,int function(void*,int,void*,int,void*),void function(void*));
int sqlite3_file_control(sqlite3*,char*,int,void*);
long sqlite3_memory_highwater(int);
long sqlite3_memory_used();
sqlite3_mutex* sqlite3_mutex_alloc(int);
void sqlite3_mutex_enter(sqlite3_mutex*);
void sqlite3_mutex_free(sqlite3_mutex*);
void sqlite3_mutex_leave(sqlite3_mutex*);
int sqlite3_mutex_try(sqlite3_mutex*);
int sqlite3_open_v2(char*,sqlite3**,int,char*);
int sqlite3_release_memory(int);
void sqlite3_result_error_nomem(sqlite3_context*);
void sqlite3_result_error_toobig(sqlite3_context*);
int sqlite3_sleep(int);
void sqlite3_soft_heap_limit(int);
sqlite3_vfs* sqlite3_vfs_find(char*);
int sqlite3_vfs_register(sqlite3_vfs*,int);
int sqlite3_vfs_unregister(sqlite3_vfs*);
int sqlite3_xthreadsafe();
void sqlite3_result_zeroblob(sqlite3_context*,int);
void sqlite3_result_error_code(sqlite3_context*,int);
int sqlite3_test_control(int, ...);
void sqlite3_randomness(int,void*);
sqlite3* sqlite3_context_db_handle(sqlite3_context*);
int sqlite3_extended_result_codes(sqlite3*,int);
int sqlite3_imit(sqlite3*,int,int);
sqlite3_stmt* sqlite3_next_stmt(sqlite3*,sqlite3_stmt*);
char* sqlite3_sql(sqlite3_stmt*);
int sqlite3_status(int,int*,int*,int);
int sqlite3_backup_finish(sqlite3_backup*);
sqlite3_backup* sqlite3_backup_init(sqlite3*,char*,sqlite3*,char*);
int sqlite3_backup_pagecount(sqlite3_backup*);
int sqlite3_backup_remaining(sqlite3_backup*);
int sqlite3_backup_step(sqlite3_backup*,int);
char* sqlite3_compileoption_get(int);
int sqlite3_compileoption_used(char*);
int sqlite3_create_function_v2(sqlite3*,char*,int,int,void*,void function(sqlite3_context*,int,sqlite3_value**),void function(sqlite3_context*,int,sqlite3_value**),void function(sqlite3_context*),void function(void*));
int sqlite3_db_config(sqlite3*,int,...);
sqlite3_mutex* sqlite3_db_mutex(sqlite3*);
int sqlite3_db_status(sqlite3*,int,int*,int*,int);
int sqlite3_extended_errcode(sqlite3*);
void sqlite3_log(int,char*,...);
long sqlite3_soft_heap_limit64(long);
char* sqlite3_sourceid();
int sqlite3_stmt_status(sqlite3_stmt*,int,int);
int sqlite3_strnicmp(char*,char*,int);
int sqlite3_unlock_notify(sqlite3*,void function(void**,int),void*);
int sqlite3_wal_autocheckpoint(sqlite3*,int);
int sqlite3_wal_checkpoint(sqlite3*,char*);
void* sqlite3_wal_hook(sqlite3*,int function(void*,sqlite3*,char*,int),void*);
