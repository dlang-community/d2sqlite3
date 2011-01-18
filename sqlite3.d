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
        single SQL statement that includes binding names, and use Parameter methods
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
        auto photo = row.photo.as!(void[]);
        ...
    }
}
catch (SqliteException e)
{
    // Error reading the database.
}
---

Warning:
These are not implemented:
$(UL
    $(LI Interfaces to $(LINK2 http://www.sqlite.org/c3ref/create_function.html, function creation API).)
    $(LI Interface to aggregate function creation API.)
    $(LI Interface to $(LINK2 http://www.sqlite.org/c3ref/create_collation.html, collation creation API).)
    $(LI $(LINK2 http://www.sqlite.org/c3ref/blob_open.html, BLOB I/O).)
)

Copyright:
    Copyright Nicolas Sicard, 2011.

License:
    No license yet.

Author:
    Nicolas Sicard.
+/
module sqlite3;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.string;
import std.range;
import std.traits;
import std.utf;
import std.variant;

debug=SQLITE;
debug(SQLITE) import std.stdio;
version(unittest) { void main() {} }

/++
Exception thrown then SQLite functions return errors.
+/
class SqliteException : Exception {
    int code;
    
    this(int code) {
        this.code = code;
        super(format("error %d", code));
    }
    
    this(string msg, int code = -1) {
        this.code = code;
        super(msg);
    }
}

/++
Metadata of the SQLite library.
+/
static struct Sqlite3 {
    /++
    Gets the default encoding.
    This function executes a query on a temporary database to 
    obtain its result.
    +/
    static @property string encoding() {
        auto db = Database(":memory:");
        auto query = db.query("PRAGMA encoding");
        auto rows = query.rows;
        assert(!rows.empty);
        return rows.front[0].as!string;
    }
    
    /++
    Gets the library's version string (e.g. 3.6.12).
    +/
    static @property string versionString() {
        return to!string(sqlite3_libversion());
    }

    /++
    Gets the library's version number (e.g. 3006012).
    +/
    static @property int versionNumber() nothrow {
        return sqlite3_libversion_number();
    }
}

unittest {
    assert(Sqlite3.encoding[0..4] == "UTF-");
    assert(Sqlite3.versionString[0..2] == "3.");
    assert(Sqlite3.versionNumber > 3003011, "incompatible SQLite version");
}

/++
An interface to a SQLite database connection.
+/
struct Database {
    private struct _core {
        sqlite3* handle;
        int refcount = 1;
    }
    private _core* core; // shared between copies of this Database object.
    
    private void _retain() nothrow {
        assert(core);
        core.refcount++;
    }
    
    private void _release() {
        assert(core);
        core.refcount--;
        assert(core.refcount >= 0);
        if (core.refcount == 0) {
            auto result = sqlite3_close(core.handle);
            enforce(result == SQLITE_OK, new SqliteException(result));
            core = null;
        }
    }

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
        core = new _core;
        auto result = sqlite3_open(cast(char*) path.toStringz, &core.handle);
        enforce(result == SQLITE_OK, new SqliteException(errorMsg, result));
    }

    nothrow this(this)  {
        _retain;
    }

    ~this() {
        _release;
    }

    void opAssign(Database rhs) nothrow {
        swap(core, rhs.core);
    }
    
    /++
    Transaction types.
    +/
    enum Transaction : string {
        deferred = "DEFERRED", /// Deferred transaction (the default).
        immediate = "IMMEDIATE", /// Transaction with write lock.
        exclusive = "EXCLUSIVE" /// Transaction with read and write lock.
    }
    
    /++
    Begins a transaction.
    +/
    void begin(Transaction type = Transaction.deferred) {
        execute("BEGIN " ~ type);
    }
    alias begin transaction; /// ditto
    
    /++
    Commits all transactions.
    +/
    void commit() {
        execute("COMMIT");
    }
    
    /++
    Rolls back to the given save point or rolls back all transaction if
    savepoint is null.
    Params:
        savepoint = the name of the save point.
    +/
    void rollback(string savepoint = null) {
        if (savepoint)
            execute("ROLLBACK TO " ~ savepoint);
        else
            execute("ROLLBACK");
    }
    
    /++
    Creates a transaction save point.
    +/
    void savepoint(string name) {
        execute("SAVEPOINT " ~ name);
    }
    
    /++
    Releases a transaction save point.
    +/
    void release(string savepoint) {
        execute("RELEASE " ~ savepoint);
    }
    
    /++
    Execute one or many SQL statements. Rows returned by any of these statements
    are ignored.
    Throws:
        SqliteException in one of the SQL statements cannot be executed.
    +/
    void execute(string sql) {
        checkHandle;
        char* errmsg;
        sqlite3_exec(core.handle, cast(char*) sql.toStringz, null, null, &errmsg);
        if (errmsg !is null) {
            auto msg = to!string(errmsg);
            sqlite3_free(errmsg);
            throw new SqliteException(msg);
        }
    }
    
    /++
    Creates a query on the database and returns it.
    Params:
        sql = the SQL code of the query.
    +/
    Query query(string sql) {
        checkHandle;
        return Query(&this, sql);
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted by
    the most recently completed query.
    +/
    @property int changes() {
        checkHandle;
        return sqlite3_changes(core.handle);
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted
    since the database was opened.
    +/
    @property int totalChanges() {
        checkHandle;
        return sqlite3_total_changes(core.handle);
    }

    /++
    Gets the SQLite error code of the last operation.
    +/
    @property int errorCode() {
        checkHandle;
        return sqlite3_errcode(core.handle);
    }

    /++
    Gets the SQLite error message of the last operation, including the error code.
    +/
    @property string errorMsg() {
        checkHandle;
        return to!string(sqlite3_errmsg(core.handle));
    }

    /++
    Gets the SQLite internal _handle of the database connection.
    +/
    @property sqlite3* handle() {
        checkHandle;
        return core.handle;
    }
    
    private void checkHandle() {
        assert(core);
        enforce(core.handle, new SqliteException("database not open"));
    }
}

unittest {
    // Test copy-construction and reference counting.
    Database db1 = void;
    {
        db1 = Database(":memory:");
        assert(db1.core.refcount == 1);
        auto db2 = db1;
        assert(db1.core.refcount == 2);
        assert(db2.core.refcount == 2);        
    }
    assert(db1.core.refcount == 1);
}

unittest {
    // Tests Database.changes() and Database.totalChanges()
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");
    assert(db.changes == 0);
    assert(db.totalChanges == 0);

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", 1024);
    query.run;
    assert(db.changes == 1);
    assert(db.totalChanges == 1);
}

/++
An interface to SQLite query execution.
+/
struct Query {
    private struct _core {
        Database* db;
        string sql;
        sqlite3_stmt* statement;
        int refcount = 1;
        Parameters params = void;
        RowSet rows = void;
    }
    private _core* core;
    
    private void _retain() nothrow {
        assert(core);
        core.refcount++;     
    }
    
    private void _release() {
        assert(core);
        core.refcount--;
        assert(core.refcount >= 0);
        if (core.refcount == 0) {
            if (core.statement) {
                auto result = sqlite3_finalize(core.statement);
                enforce(result == SQLITE_OK, new SqliteException(result));
            }
            if (core.db)
                core.db._release;              
            core = null;
        }
    }

    private this(Database* db, string sql) {
        assert(db);
        assert(db.core.handle);
        db._retain;
        core = new _core;
        core.db = db;
        core.sql = sql;
        auto result = sqlite3_prepare_v2(
            db.core.handle,
            cast(char*) core.sql.toStringz,
            core.sql.length,
            &core.statement,
            null
        );
        enforce(result == SQLITE_OK, new SqliteException(db.errorMsg, result));
        core.params = Parameters(core.statement);
    }

    nothrow this(this) {
        _retain;
    }

    ~this() {
        _release;
    }

    void opAssign(Query rhs) nothrow {
        swap(core, rhs.core);
    }
    
    /++
    Gets the SQLite internal handle of the query statement.
    +/
    @property sqlite3_stmt* statement() nothrow {
        assert(core);
        return core.statement;
    }
    
    /++
    Gets the bindable parameters of the query.
    Returns:
        A Parameters object. Becomes invalid when the Query goes out of scope.
    +/
    @property ref Parameters params() nothrow {
        assert(core);
        return core.params;
    }

    /++
    Gets the results of a query that returns _rows.
    Returns:
        A RowSet object that can be used as an InputRange. Becomes invalid
        when the Query goes out of scope.
    +/
    @property ref RowSet rows() {
        assert(core);
        if (!core.rows.isInitialized) {
            core.rows = RowSet(core.statement);
            core.rows.initialize;            
        }
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
    Resets a query.
    Throws:
        SqliteException when the query could not be reset.
    +/
    void reset() {
        assert(core && core.statement);
        if (core.statement) {
            auto result = sqlite3_reset(core.statement);
            enforce(result == SQLITE_OK, new SqliteException(core.db.errorMsg, result));
            core.rows = RowSet(core.statement);
        }
    }
}

unittest {
    // Test copy-construction and reference counting.
    Database db = Database(":memory:");
    auto q1 = db.query("SELECT 1024");
    {
        assert(q1.core.refcount == 1);
        auto q2 = q1;
        assert(q1.core.refcount == 2);
        assert(q2.core.refcount == 2);        
    }
    assert(q1.core.refcount == 1);
}

unittest {
    // Tests empty statements
    auto db = Database(":memory:");
    db.execute(";");
    auto query = db.query("-- This is a comment !");
    assert(query.rows.empty);
}

unittest {
    // Tests multiple statements in query string
    auto db = Database(":memory:");
    int result;
    try
        db.execute("CREATE TABLE test (val INTEGER);CREATE TABLE test (val INTEGER)");
    catch (SqliteException e)
        assert(e.msg.canFind("test"));
}

unittest {
    // Tests Query.rows()
    static assert(isInputRange!RowSet);
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", 1024);
    query.run;
    assert(query.rows.empty);
    query = db.query("SELECT * FROM test");
    assert(!query.rows.empty);
    assert(query.rows.front[0].as!int == 1024);
    query.rows.popFront();
    assert(query.rows.empty);
}

/++
The bound parameters of a query.
+/
struct Parameters {
    private sqlite3_stmt* statement;
    
    private this(sqlite3_stmt* statement) nothrow {
        this.statement = statement;
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
        // The binding key is either a string or an integer.
        static assert(isSomeString!K || isImplicitlyConvertible!(K, int),
                      "unexpected type for column reference: " ~ K.stringof);
        // Do the actual binding.
        opIndexAssign(value, key);
        // Recursive call for the next two arguments.
        static if (args.length >= 4)
            bind(args[2 .. $]);
    }
    
    /++
    Binds $(D_PARAM value) at the given $(D_PARAM index) or to the parameter named $(D_PARAM name).
    Throws:
        SqliteException when parameter refers to an invalid binding or when
        the value cannot be bound.
    Bugs:
        Does not work with Query.params due to DMD issue #5202
    +/
    void opIndexAssign(T)(T value, int index) {
        enforce(statement, new SqliteException("no parameter in prepared statement"));
        
        alias Unqual!T U;
        int result;
        
        static if (isImplicitlyConvertible!(U, long))
            result = sqlite3_bind_int64(statement, index, cast(long) value);
        else static if (isImplicitlyConvertible!(U, real))
            result = sqlite3_bind_double(statement, index, value);
        else static if (isSomeString!U) {
            if (value is null)
                result = sqlite3_bind_null(statement, index);
            else {
                string utf8 = value.toUTF8;
                result = sqlite3_bind_text(statement, index, cast(char*) utf8.toStringz, utf8.length, null);
            }
        }
        else static if (isPointer!U && !is(U == void*)) {
            if (value is null)
                result = sqlite3_bind_null(statement, index);
            else {
                bind(index, *value);
                return;
            }
        }
        else static if (is(U == void*))
            result = sqlite3_bind_null(statement, index);
        else static if (isArray!U) {
            void[] buffer = cast(void[]) value;
            result = sqlite3_bind_blob(statement, index, cast(void*) buffer.ptr, buffer.length, null);
        }
        else static if (!is(U == void)) {
            void[] buffer;
            buffer.length = U.sizeof;
            memcpy(buffer.ptr, &value, buffer.length);
            result = sqlite3_bind_blob(statement, index, cast(void*) buffer.ptr, buffer.length, null);
        }
        else
            static assert(false, "cannot bind a value of type " ~ U.stringof);

        enforce(result == SQLITE_OK, new SqliteException(result));
    }
    
    /// ditto
    void opIndexAssign(T)(T value, string name) {
        enforce(statement, new SqliteException("no parameter in prepared statement"));
        int index = sqlite3_bind_parameter_index(statement, cast(char*) name.toStringz);
        enforce(index > 0, new SqliteException(format("parameter named '%s' cannot be bound", name)));            
        opIndexAssign(value, index);
    }
    
    /++
    Gets the number of parameters.
    +/
    int length() nothrow {
        if (!statement)
            return 0;
        return sqlite3_bind_parameter_count(statement);
    }
    
    /++
    Clears the bindings.
    +/
    void clear() {
        if (statement) {
            auto result = sqlite3_clear_bindings(statement);
            enforce(result == SQLITE_OK, new SqliteException(result));
        }
    } 
}

unittest {
    // Tests Parmeters
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", 2048);
    query.run;
    query.reset;
    query.params.bind(1, 2048);
    query.run;
    query.reset;
    query.params.bind(1, 2048);
    query.run;
    query.reset;
    query.params.bind(":val", 2048);
    query.run;
    
    query = db.query("SELECT * FROM test");
    foreach (row; query.rows) {
        assert(row[0].as!int == 2048);
    }
}

unittest {
    // Tests multiple bindings
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto query = db.query("INSERT INTO test (i, f, t) VALUES (:i, :f, :t)");
    query.params.bind(":t", "TEXT", ":i", 1024, ":f", 3.14);
    query.run;
    query.reset;
    query.params.bind(3, "TEXT", 1, 1024, 2, 3.14);
    query.run;
    
    query = db.query("SELECT * FROM test");
    foreach (row; query.rows) {
        assert(row["i"].as!int == 1024);
        assert(row["f"].as!double == 3.14);
        assert(row["t"].as!string == "TEXT");
    }
}

/++
The results of a query that returns rows, with an InputRange interface.
+/
struct RowSet {
    private sqlite3_stmt* statement;
    private int sqliteResult = SQLITE_DONE;
    private bool isInitialized = false;

    private this(sqlite3_stmt* statement) nothrow {
        this.statement = statement;
    }

    private void initialize() {
        if (statement) {
            // Try to fetch first row
            sqliteResult = sqlite3_step(statement);
            enforce(sqliteResult == SQLITE_ROW || sqliteResult == SQLITE_DONE,
                    new SqliteException(sqliteResult));                        
        }
        else
            sqliteResult = SQLITE_DONE; // No statement, so RowSet is empty;
        isInitialized = true;
    }

    /++
    Tests whether no more rows are available.
    +/
    @property bool empty() nothrow {
        assert(isInitialized);
        return sqliteResult == SQLITE_DONE;
    }

    /++
    Gets the current row.
    +/
    @property Row front() {
        assert(isInitialized && !empty);
        assert(statement);
        Row row;
        auto colcount = sqlite3_column_count(statement);
        row.columns.reserve(colcount);
        for (int i = 0; i < colcount; i++) {
            /*
                TODO The name obtained from sqlite3_column_name is that of the query text. We should test first for the real name with sqlite3_column_database_name or sqlite3_column_table_name.
            */
            auto name = to!string(sqlite3_column_name(statement, i));
            auto type = sqlite3_column_type(statement, i);
            final switch (type) {
            case SQLITE_INTEGER:
                row.columns ~= Column(i, name, Variant(sqlite3_column_int64(statement, i)));
                break;

            case SQLITE_FLOAT:
                row.columns ~= Column(i, name, Variant(sqlite3_column_double(statement, i)));
                break;

            case SQLITE_TEXT:
                auto str = to!string(sqlite3_column_text(statement, i));
                row.columns ~= Column(i, name, Variant(str));
                break;

            case SQLITE_BLOB:
                auto ptr = sqlite3_column_blob(statement, i);
                auto length = sqlite3_column_bytes(statement, i);
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
    void popFront() nothrow {
        assert(isInitialized && !empty);
        assert(statement);
        sqliteResult = sqlite3_step(statement);
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
    @property int columnCount() nothrow {
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
    
    /++
    
    +/
    Column opDispatch(string name)() {
        return opIndex(name);
    }
}

/++
A SQLite column.
+/
struct Column {
    int index;
    string name;
    private Variant data;
    
    /++
    Gets the value of the column converted _to type T.
    If the value is NULL, it is replaced by value.
    +/
    T as(T, T value = T.init)() {
        alias Unqual!T U;
        if (data.hasValue) {
            static if (is(U == bool))
                return cast(T) data.coerce!long != 0;
            else static if (isIntegral!U)
                return cast(T) std.conv.to!U(data.coerce!long);
            else static if (isSomeChar!U)
                return cast(T) std.conv.to!U(data.coerce!string[0]);
            else static if (isFloatingPoint!U)
                return cast(T) std.conv.to!U(data.coerce!double);
            else static if (isSomeString!U)
                return cast(T) std.conv.to!U(data.coerce!string);
            else static if (isArray!U)
                return cast(T) data.get!(ubyte[]);
            else {
                U result = void;
                auto store = data.get!(ubyte[]);
                memcpy(&result, store.ptr, result.sizeof);
                return cast(T) result;
            }
        }
        else
            return value;
    }
    
    alias as!string toString;
}

unittest {
    // Tests Column
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", 2048);
    query.run;
    
    query = db.query("SELECT val FROM test");
    with (query.rows) {
        assert(front[0].as!int == 2048);
        assert(front["val"].as!int == 2048);
        assert(front.val.as!int == 2048);
    }
}

unittest {
    // Tests NULL values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", null);
    query.run;

    query = db.query("SELECT * FROM test");
    assert(query.rows.front["val"].as!(int, -1024) == -1024);
}

unittest {
    // Tests INTEGER values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    int i = 1;
    query.params.bind(":val", &i);
    query.run;
    query.reset;
    query.params.bind(":val", 1L);
    query.run;
    assert(db.changes == 1);
    assert(db.totalChanges == 2);
    query.reset;
    query.params.bind(":val", 1U);
    query.run;
    query.reset;
    query.params.bind(":val", 1UL);
    query.run;
    query.reset;
    query.params.bind(":val", true);
    query.run;
    query.reset;
    query.params.bind(":val", '\&copy;');
    query.run;
    query.reset;
    query.params.bind(":val", '\x72');
    query.run;
    query.reset;
    query.params.bind(":val", '\u1032');
    query.run;
    query.reset;
    query.params.bind(":val", '\U0000FF32');
    query.run;

    query = db.query("SELECT * FROM test");
    foreach (row; query.rows)
        assert(row["val"].as!long > 0);
}

unittest {
    // Tests FLOAT values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val FLOAT)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", 1.0F);
    query.run;
    query.reset;
    query.params.bind(":val", 1.0);
    query.run;
    query.reset;
    query.params.bind(":val", 1.0L);
    query.run;

    query = db.query("SELECT * FROM test");
    foreach (row; query.rows)
        assert(row["val"].as!real > 0);
}

unittest {
    // Tests TEXT values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val TEXT)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B"c);
    query.run;
    query.reset;
    query.params.bind(":val", "\uC720\uB2C8\uCF5B"w);
    query.run;
    query.reset;
    query.params.bind(":val", "\uC720\uB2C8\uCF5B"d);
    query.run;

    query = db.query("SELECT * FROM test");
    foreach (row; query.rows) {
        assert(row["val"].as!string ==  "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B"c);
        assert(row["val"].as!wstring ==  "\uC720\uB2C8\uCF5B"w);
    }
}

unittest {
    // Tests BLOB values with arrays
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val BLOB)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    int[] array = [1, 2, 3, 4];
    query.params.bind(":val", array);
    query.run;

    query = db.query("SELECT * FROM test");
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

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    auto original = Data(1024, 'z', 3.14159, "foo");
    query.params.bind(":val", original);
    query.run;

    query = db.query("SELECT * FROM test");
    auto copy = query.rows.front["val"].as!Data;
    assert(copy.toString == "1024 z 3.14 foo");
}

//-----------------------------------------------------------------------------
// SQLite C API
//-----------------------------------------------------------------------------

enum SQLITE_OK = 0;
enum SQLITE_ERROR = 1;
enum SQLITE_INTERNAL = 2;
enum SQLITE_PERM = 3;
enum SQLITE_ABORT = 4;
enum SQLITE_BUSY = 5;
enum SQLITE_LOCKED = 6;
enum SQLITE_NOMEM = 7;
enum SQLITE_READONLY = 8;
enum SQLITE_INTERRUPT = 9;
enum SQLITE_IOERR = 10;
enum SQLITE_CORRUPT = 11;
enum SQLITE_NOTFOUND = 12;
enum SQLITE_FULL = 13;
enum SQLITE_CANTOPEN = 14;
enum SQLITE_PROTOCOL = 15;
enum SQLITE_EMPTY = 16;
enum SQLITE_SCHEMA = 17;
enum SQLITE_TOOBIG = 18;
enum SQLITE_CONSTRAINT = 19;
enum SQLITE_MISMATCH = 20;
enum SQLITE_MISUSE = 21;
enum SQLITE_NOLFS = 22;
enum SQLITE_AUTH = 23;
enum SQLITE_FORMAT = 24;
enum SQLITE_RANGE = 25;
enum SQLITE_NOTADB = 26;
enum SQLITE_ROW = 100;
enum SQLITE_DONE = 101;
enum SQLITE_IOERR_READ = (SQLITE_IOERR | (1<<8));
enum SQLITE_IOERR_SHORT_READ = (SQLITE_IOERR | (2<<8));
enum SQLITE_IOERR_WRITE = (SQLITE_IOERR | (3<<8));
enum SQLITE_IOERR_FSYNC = (SQLITE_IOERR | (4<<8));
enum SQLITE_IOERR_DIR_FSYNC = (SQLITE_IOERR | (5<<8));
enum SQLITE_IOERR_TRUNCATE = (SQLITE_IOERR | (6<<8));
enum SQLITE_IOERR_FSTAT = (SQLITE_IOERR | (7<<8));
enum SQLITE_IOERR_UNLOCK = (SQLITE_IOERR | (8<<8));
enum SQLITE_IOERR_RDLOCK = (SQLITE_IOERR | (9<<8));
enum SQLITE_IOERR_DELETE = (SQLITE_IOERR | (10<<8));
enum SQLITE_IOERR_BLOCKED = (SQLITE_IOERR | (11<<8));
enum SQLITE_IOERR_NOMEM = (SQLITE_IOERR | (12<<8));
enum SQLITE_IOERR_ACCESS = (SQLITE_IOERR | (13<<8));
enum SQLITE_IOERR_CHECKRESERVEDLOCK = (SQLITE_IOERR | (14<<8));
enum SQLITE_IOERR_LOCK = (SQLITE_IOERR | (15<<8));
enum SQLITE_IOERR_CLOSE = (SQLITE_IOERR | (16<<8));
enum SQLITE_IOERR_DIR_CLOSE = (SQLITE_IOERR | (17<<8));
enum SQLITE_IOERR_SHMOPEN = (SQLITE_IOERR | (18<<8));
enum SQLITE_IOERR_SHMSIZE = (SQLITE_IOERR | (19<<8));
enum SQLITE_IOERR_SHMLOCK = (SQLITE_IOERR | (20<<8));
enum SQLITE_LOCKED_SHAREDCACHE = (SQLITE_LOCKED |  (1<<8));
enum SQLITE_BUSY_RECOVERY = (SQLITE_BUSY   |  (1<<8));
enum SQLITE_CANTOPEN_NOTEMPDIR = (SQLITE_CANTOPEN | (1<<8));
enum SQLITE_OPEN_READONLY = 0x00000001;
enum SQLITE_OPEN_READWRITE = 0x00000002;
enum SQLITE_OPEN_CREATE = 0x00000004;
enum SQLITE_OPEN_DELETEONCLOSE = 0x00000008;
enum SQLITE_OPEN_EXCLUSIVE = 0x00000010;
enum SQLITE_OPEN_AUTOPROXY = 0x00000020;
enum SQLITE_OPEN_MAIN_DB = 0x00000100;
enum SQLITE_OPEN_TEMP_DB = 0x00000200;
enum SQLITE_OPEN_TRANSIENT_DB = 0x00000400;
enum SQLITE_OPEN_MAIN_JOURNAL = 0x00000800;
enum SQLITE_OPEN_TEMP_JOURNAL = 0x00001000;
enum SQLITE_OPEN_SUBJOURNAL = 0x00002000;
enum SQLITE_OPEN_MASTER_JOURNAL = 0x00004000;
enum SQLITE_OPEN_NOMUTEX = 0x00008000;
enum SQLITE_OPEN_FULLMUTEX = 0x00010000;
enum SQLITE_OPEN_SHAREDCACHE = 0x00020000;
enum SQLITE_OPEN_PRIVATECACHE = 0x00040000;
enum SQLITE_OPEN_WAL = 0x00080000;
enum SQLITE_IOCAP_ATOMIC = 0x00000001;
enum SQLITE_IOCAP_ATOMIC512 = 0x00000002;
enum SQLITE_IOCAP_ATOMIC1K = 0x00000004;
enum SQLITE_IOCAP_ATOMIC2K = 0x00000008;
enum SQLITE_IOCAP_ATOMIC4K = 0x00000010;
enum SQLITE_IOCAP_ATOMIC8K = 0x00000020;
enum SQLITE_IOCAP_ATOMIC16K = 0x00000040;
enum SQLITE_IOCAP_ATOMIC32K = 0x00000080;
enum SQLITE_IOCAP_ATOMIC64K = 0x00000100;
enum SQLITE_IOCAP_SAFE_APPEND = 0x00000200;
enum SQLITE_IOCAP_SEQUENTIAL = 0x00000400;
enum SQLITE_IOCAP_UNDELETABLE_WHEN_OPEN = 0x00000800;
enum SQLITE_LOCK_NONE = 0;
enum SQLITE_LOCK_SHARED = 1;
enum SQLITE_LOCK_RESERVED = 2;
enum SQLITE_LOCK_PENDING = 3;
enum SQLITE_LOCK_EXCLUSIVE = 4;
enum SQLITE_SYNC_NORMAL = 0x00002;
enum SQLITE_SYNC_FULL = 0x00003;
enum SQLITE_SYNC_DATAONLY = 0x00010;
enum SQLITE_FCNTL_LOCKSTATE = 1;
enum SQLITE_GET_LOCKPROXYFILE = 2;
enum SQLITE_SET_LOCKPROXYFILE = 3;
enum SQLITE_LAST_ERRNO = 4;
enum SQLITE_FCNTL_SIZE_HINT = 5;
enum SQLITE_FCNTL_CHUNK_SIZE = 6;
enum SQLITE_ACCESS_EXISTS = 0;
enum SQLITE_ACCESS_READWRITE = 1;
enum SQLITE_ACCESS_READ = 2;
enum SQLITE_SHM_UNLOCK = 1;
enum SQLITE_SHM_LOCK = 2;
enum SQLITE_SHM_SHARED = 4;
enum SQLITE_SHM_EXCLUSIVE = 8;
enum SQLITE_SHM_NLOCK = 8;
enum SQLITE_CONFIG_SINGLETHREAD = 1;
enum SQLITE_CONFIG_MULTITHREAD = 2;
enum SQLITE_CONFIG_SERIALIZED = 3;
enum SQLITE_CONFIG_MALLOC = 4;
enum SQLITE_CONFIG_GETMALLOC = 5;
enum SQLITE_CONFIG_SCRATCH = 6;
enum SQLITE_CONFIG_PAGECACHE = 7;
enum SQLITE_CONFIG_HEAP = 8;
enum SQLITE_CONFIG_MEMSTATUS = 9;
enum SQLITE_CONFIG_MUTEX = 10;
enum SQLITE_CONFIG_GETMUTEX = 11; 
enum SQLITE_CONFIG_LOOKASIDE = 13;
enum SQLITE_CONFIG_PCACHE = 14;
enum SQLITE_CONFIG_GETPCACHE = 15;
enum SQLITE_CONFIG_LOG = 16;
enum SQLITE_DBCONFIG_LOOKASIDE = 1001;
enum SQLITE_DENY = 1;
enum SQLITE_IGNORE = 2;
enum SQLITE_CREATE_INDEX = 1;
enum SQLITE_CREATE_TABLE = 2;
enum SQLITE_CREATE_TEMP_INDEX = 3;
enum SQLITE_CREATE_TEMP_TABLE = 4;
enum SQLITE_CREATE_TEMP_TRIGGER = 5;
enum SQLITE_CREATE_TEMP_VIEW = 6;
enum SQLITE_CREATE_TRIGGER = 7;
enum SQLITE_CREATE_VIEW = 8;
enum SQLITE_DELETE = 9;
enum SQLITE_DROP_INDEX = 10;
enum SQLITE_DROP_TABLE = 11;
enum SQLITE_DROP_TEMP_INDEX = 12;
enum SQLITE_DROP_TEMP_TABLE = 13;
enum SQLITE_DROP_TEMP_TRIGGER = 14;
enum SQLITE_DROP_TEMP_VIEW = 15;
enum SQLITE_DROP_TRIGGER = 16;
enum SQLITE_DROP_VIEW = 17;
enum SQLITE_INSERT = 18;
enum SQLITE_PRAGMA = 19;
enum SQLITE_READ = 20;
enum SQLITE_SELECT = 21;
enum SQLITE_TRANSACTION = 22;
enum SQLITE_UPDATE = 23;
enum SQLITE_ATTACH = 24;
enum SQLITE_DETACH = 25;
enum SQLITE_ALTER_TABLE = 26;
enum SQLITE_REINDEX = 27;
enum SQLITE_ANALYZE = 28;
enum SQLITE_CREATE_VTABLE = 29;
enum SQLITE_DROP_VTABLE = 30;
enum SQLITE_FUNCTION = 31;
enum SQLITE_SAVEPOINT = 32;
enum SQLITE_COPY = 0;
enum SQLITE_LIMIT_LENGTH = 0;
enum SQLITE_LIMIT_SQL_LENGTH = 1;
enum SQLITE_LIMIT_COLUMN = 2;
enum SQLITE_LIMIT_EXPR_DEPTH = 3;
enum SQLITE_LIMIT_COMPOUND_SELECT = 4;
enum SQLITE_LIMIT_VDBE_OP = 5;
enum SQLITE_LIMIT_FUNCTION_ARG = 6;
enum SQLITE_LIMIT_ATTACHED = 7;
enum SQLITE_LIMIT_LIKE_PATTERN_LENGTH = 8;
enum SQLITE_LIMIT_VARIABLE_NUMBER = 9;
enum SQLITE_LIMIT_TRIGGER_DEPTH = 10;
enum SQLITE_INTEGER = 1;
enum SQLITE_FLOAT = 2;
enum SQLITE_BLOB = 4;
enum SQLITE_NULL = 5;
enum SQLITE_TEXT = 3;
enum SQLITE3_TEXT = 3;
enum SQLITE_UTF8 = 1;
enum SQLITE_UTF16LE = 2;
enum SQLITE_UTF16BE = 3;
enum SQLITE_UTF16 = 4;
enum SQLITE_ANY = 5;
enum SQLITE_UTF16_ALIGNED = 8;
enum SQLITE_INDEX_CONSTRAINT_EQ = 2;
enum SQLITE_INDEX_CONSTRAINT_GT = 4;
enum SQLITE_INDEX_CONSTRAINT_LE = 8;
enum SQLITE_INDEX_CONSTRAINT_LT = 16;
enum SQLITE_INDEX_CONSTRAINT_GE = 32;
enum SQLITE_INDEX_CONSTRAINT_MATCH = 64;
enum SQLITE_MUTEX_FAST = 0;
enum SQLITE_MUTEX_RECURSIVE = 1;
enum SQLITE_MUTEX_STATIC_MASTER = 2;
enum SQLITE_MUTEX_STATIC_MEM = 3;
enum SQLITE_MUTEX_STATIC_MEM2 = 4;
enum SQLITE_MUTEX_STATIC_OPEN = 4;
enum SQLITE_MUTEX_STATIC_PRNG = 5;
enum SQLITE_MUTEX_STATIC_LRU = 6;
enum SQLITE_MUTEX_STATIC_LRU2 = 7;
enum SQLITE_TESTCTRL_FIRST = 5;
enum SQLITE_TESTCTRL_PRNG_SAVE = 5;
enum SQLITE_TESTCTRL_PRNG_RESTORE = 6;
enum SQLITE_TESTCTRL_PRNG_RESET = 7;
enum SQLITE_TESTCTRL_BITVEC_TEST = 8;
enum SQLITE_TESTCTRL_FAULT_INSTALL = 9;
enum SQLITE_TESTCTRL_BENIGN_MALLOC_HOOKS = 10;
enum SQLITE_TESTCTRL_PENDING_BYTE = 11;
enum SQLITE_TESTCTRL_ASSERT = 12;
enum SQLITE_TESTCTRL_ALWAYS = 13;
enum SQLITE_TESTCTRL_RESERVE = 14;
enum SQLITE_TESTCTRL_OPTIMIZATIONS = 15;
enum SQLITE_TESTCTRL_ISKEYWORD = 16;
enum SQLITE_TESTCTRL_PGHDRSZ = 17;
enum SQLITE_TESTCTRL_SCRATCHMALLOC = 18;
enum SQLITE_TESTCTRL_LAST = 18;
enum SQLITE_STATUS_MEMORY_USED = 0;
enum SQLITE_STATUS_PAGECACHE_USED = 1;
enum SQLITE_STATUS_PAGECACHE_OVERFLOW = 2;
enum SQLITE_STATUS_SCRATCH_USED = 3;
enum SQLITE_STATUS_SCRATCH_OVERFLOW = 4;
enum SQLITE_STATUS_MALLOC_SIZE = 5;
enum SQLITE_STATUS_PARSER_STACK = 6;
enum SQLITE_STATUS_PAGECACHE_SIZE = 7;
enum SQLITE_STATUS_SCRATCH_SIZE = 8;
enum SQLITE_STATUS_MALLOC_COUNT = 9;
enum SQLITE_DBSTATUS_LOOKASIDE_USED = 0;
enum SQLITE_DBSTATUS_CACHE_USED = 1;
enum SQLITE_DBSTATUS_SCHEMA_USED = 2;
enum SQLITE_DBSTATUS_STMT_USED = 3;
enum SQLITE_DBSTATUS_MAX = 3;
enum SQLITE_STMTSTATUS_FULLSCAN_STEP = 1;
enum SQLITE_STMTSTATUS_SORT = 2;
enum SQLITE_STMTSTATUS_AUTOINDEX = 3;

struct sqlite3;
struct sqlite3_stmt;
struct sqlite3_context;
struct sqlite3_value;
struct sqlite3_blob;
struct sqlite3_module;
struct sqlite3_mutex;
struct sqlite3_backup;
struct sqlite3_vfs;

extern(C): nothrow:

alias int function(void*,int,char**,char**) sqlite3_callback;

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
