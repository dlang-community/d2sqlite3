// Written in the D programming language
/++
Simple and easy SQLite interface.

Executable must be linked to the SQLite library version 3.3.11 or later.

Objects in this interface (Database and Query) are
reference-counted. When the last reference goes out of scope, the objects are
automatically closed and finalized. The user does not have to explicitly open
or close them.

Example:
---
writeln("Opening a database in memory...");
Database db;
try {
    db = Database(":memory:");
}
catch (SqliteException e) {
    writefln("Error opening database: %s.", e.msg);
    return;
}

writeln("Creating a table...");
try {
    auto query = Query(db,
        "CREATE TABLE person (
            id INTEGER PRIMARY KEY,
            last_name TEXT NOT NULL,
            first_name TEXT,
            score REAL,
            photo BLOB
        )");
    query.execute;
}
catch (SqliteException e) {
    writefln("Error creating the table: %s.", e.msg);
}

writeln("Populating the table...");
try {
    with (Query(db, "INSERT INTO person
                    (last_name, first_name, score, photo)
                    VALUES (:last_name, :first_name, :score, :photo)")) {
        db.transaction;
        scope(failure) db.rollback;
        scope(success) db.commit;

        bind(":last_name", "Smith");
        bind(":first_name", "Robert");
        bind(":score", 77.5);
        ubyte[] photo = ...
        bind(":photo", photo);
        execute;

        reset; // need to reset the query after execution
        bind(":last_name", "Doe");
        bind(":first_name", "John");
        bind(":score", null);
        bind(":photo", null);
        execute;
    }
}
catch (SqliteException e) {
    writefln("Error: %s.", e.msg);
}
writefln("--> %d persons inserted.", db.totalChanges);

writeln("Reading the table...");
try {
    // Count the persons in the table
    auto query = Query(db, "SELECT COUNT(*) FROM person");
    writefln("--> Number of persons: %d", query.rows.front[0].to!int);

    // Fetch the data from the table
    query = Query(db, "SELECT * FROM person");
    foreach (row; query.rows) {
        auto id = row["id"].as!int;
        auto name = format("%s, %s", row["last_name"].as!string,
                                     row["first_name"].as!string);
        auto score = row["score"].as!(real, 0.0); // score can be NULL,
        //           so provide 0.0 as a default value to replace NULLs
        auto photo = row["photo"].as!(void[]);
        writefln("--> [%d] %s, score = %.1f", id, name, score);
    }
}
catch (SqliteException e) {
    writefln("Error reading the database: %s.", e.msg);
}
---

Copyright: Copyright Nicolas Sicard, 2011.

License: $(LINK2 http://boost.org/LICENSE_1_0.txt, Boost License 1.0).

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

debug=SQLITE;
debug(SQLITE) import std.stdio;
version(unittest) { import std.stdio; }

/++
Exception thrown then SQLite functions return error codes.
+/
class SqliteException : Exception {
    this(string msg) {
        super(msg);
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

Once a Database object is created, the database is open and can be used
directly. The database is automatically closed when the last reference to the
object goes out of scope. If database error occur while the database is beeing
closed in the destructor, a SqliteException is thrown.

The Database object is not thread-safe, while the SQLite database engine
itself can be.
+/
struct Database {
    private struct _core {
        string path;
        sqlite3* handle;
        int refcount;
        bool inTransaction;
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
        core.path = path;
        auto result = sqlite3_open(cast(char*) core.path.toStringz, &core.handle);
        enforceEx!SqliteException(result == SQLITE_OK, errorMsg);
        core.refcount = 1;
        core.inTransaction = false;
    }

    this(this) {
        core.refcount++;
    }

    ~this() {
        core.refcount--;
        if (core.refcount == 0) {
            if (core.inTransaction)
                commit;
            auto result = sqlite3_close(core.handle);
            enforceEx!SqliteException(result == SQLITE_OK, errorMsg);
        }
    }

    void opAssign(Database rhs) {
        swap(core, rhs.core);
    }

    /++
    Begins a transaction.
    Throws:
        SqliteException when a transaction has already been starter (simple
        transactions do not nest in SQLite).
    +/
    void transaction() {
        enforceEx!SqliteException(!core.inTransaction, "cannot begin transaction: already in transaction");
        auto q = Query(this, "BEGIN TRANSACTION");
        q.execute;
        core.inTransaction = true;
    }

    /++
    Commits the current transaction.
    Throws:
        SqliteException when no transaction is started.
    +/
    void commit() {
        enforceEx!SqliteException(core.inTransaction, "no transaction to commit");
        auto q = Query(this, "COMMIT TRANSACTION");
        q.execute;
        core.inTransaction = false;
    }

    /++
    Rolls back the current transaction.
    Throws:
        SqliteException when no transaction is started.
    +/
    void rollback() {
        enforceEx!SqliteException(core.inTransaction, "no transaction to rollback");
        auto q = Query(this, "ROLLBACK TRANSACTION");
        q.execute;
        core.inTransaction = false;
    }

    /++
    Gets the database file _path.
    +/
    @property string path() {
        return core.path;
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
        return format("error %d '%s'", errorCode, to!string(sqlite3_errmsg(core.handle)));
    }

    /++
    Gets the SQLite internal _handle of the database connection.
    +/
    @property sqlite3* handle() {
        assert(core.handle);
        return core.handle;
    }

    private void retain() {
        core.refcount++;
    }

    private void release() {
        core.refcount--;
    }
}

/++
An interface to SQLite query execution.

Use execute to execute queries that do not expect rows as their result (CREATE
TABLE, INSERT, UPDATE...). Use rows without a prior call to execute for
queries that expect rows as their result (SELECT).

Once a Query object is created, the query can be used directly. The
query is automatically closed when the last reference to the object goes out
of scope. If database error occur while the query is beeing
closed in the destructor, a SqliteException is thrown.

Query is not thread-safe.
+/
struct Query {
    private struct _core {
        Database* db;
        string sql;
        sqlite3_stmt* statement;
        int refcount;
        bool isClean = true;
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
        db.retain;
        core.db = &db;
        core.sql = sql;
        char* unused;
        auto result = sqlite3_prepare_v2(
            core.db.handle,
            cast(char*) core.sql.toStringz,
            core.sql.length,
            &core.statement,
            &unused
        );
        enforceEx!SqliteException(result == SQLITE_OK, core.db.errorMsg);
        core.refcount = 1;
        core.isClean = true;
        core.rows = RowSet(&this);
    }

    this(this) {
        core.refcount++;
    }

    ~this() {
        core.refcount--;
        if (core.refcount == 0) {
            if (core.statement) {
                auto result = sqlite3_finalize(core.statement);
                enforceEx!SqliteException(result == SQLITE_OK, core.db.errorMsg);
            }
            core.db.release;
        }
    }

    void opAssign(Query rhs) {
        swap(core, rhs.core);
    }

    /++
    Binds a value to a named parameter in the query.
    Params:
        parameter = the name of the parameter to bind to in the SQL prepared
        statement, including the symbol preceeding the actual name, e.g.
        ":id".
        value = the bound value.
    Throws:
        SqliteException when parameter refers to an invalid binding or when
        the value cannot be bound.
    +/
    void bind(T)(string parameter, T value) {
        assert(core.statement);
        int index = 0;
        index = sqlite3_bind_parameter_index(core.statement, cast(char*) parameter.toStringz);
        enforceEx!SqliteException(index, format("parameter named '%s' cannot be bound", parameter));
        bind(index, value);
    }

    /++
    Binds a value to an indexed parameter in the query.
        index = the index of the parameter to bind to in the SQL prepared
        statement.
        value = the bound value.
    Throws:
        SqliteException when index is invalid or when the value cannot be
        bound.
    +/
    void bind(T)(int index, T value) {
        assert(core.statement);

        int result;
        static if (isImplicitlyConvertible!(Unqual!T, long))
            result = sqlite3_bind_int64(core.statement, index, cast(long) value);
        else static if (isImplicitlyConvertible!(Unqual!T, real))
            result = sqlite3_bind_double(core.statement, index, value);
        else static if (isSomeString!T) {
            if (value is null)
                result = sqlite3_bind_null(core.statement, index);
            else {
                string utf8 = value.toUTF8;
                result = sqlite3_bind_text(core.statement, index, cast(char*) utf8.toStringz, utf8.length, null);
            }
        }
        else static if (isPointer!T && !is(T == void*)) {
            if (value is null)
                result = sqlite3_bind_null(core.statement, index);
            else {
                bind(index, *value);
                return;
            }
        }
        else static if (is(T == void*))
            result = sqlite3_bind_null(core.statement, index);
        else static if (isArray!T) {
            void[] buffer = cast(void[]) value;
            result = sqlite3_bind_blob(core.statement, index, cast(void*) buffer.ptr, buffer.length, null);
        }
        else static if (!is(T == void)) {
            void[] buffer;
            buffer.length = T.sizeof;
            memcpy(buffer.ptr, &value, buffer.length);
            result = sqlite3_bind_blob( core.statement, index, cast(void*) buffer.ptr, buffer.length, null);
        }
        else
            static assert(isValidSqliteType!T, "cannot bind a void value");

        enforceEx!SqliteException(result == SQLITE_OK, core.db.errorMsg);
    }

    /++
    Gets the results of a query that returns _rows.
    Throws:
        SqliteException when rows() is called twice whitout a prior reset of
        the query.
    +/
    @property ref RowSet rows() {
        assert(core.statement);
        enforceEx!SqliteException(core.isClean, "rows() called but the query needs to be reset");
        if (!core.rows.isInitialized)
            core.rows.initialize;
        return core.rows;
    }

    /++
    Execute a query that does not expect rows as its result.
    Throws:
        SqliteException when the query cannot be executed.
    +/
    void execute() {
        assert(core.statement);
        enforceEx!SqliteException(core.isClean, "execute() called but the query needs to be reset");
        auto result = sqlite3_step(core.statement);
        assert(result != SQLITE_ROW,
            "call to Query.execute() on a query that return rows, "
            "use Query.rows instead"
        );
        enforceEx!SqliteException(result == SQLITE_DONE, to!string(result)/+core.db.errorMsg+/);
        core.isClean = false;
    }

    /++
    Resets a query and clears all bindings.
    Throws:
        SqliteException when the querey could not be reset.
    +/
    void reset() {
        assert(core.statement);
        auto result = sqlite3_reset(core.statement);
        enforceEx!SqliteException(result == SQLITE_OK, core.db.errorMsg);
        sqlite3_clear_bindings(core.statement);
        core.isClean = true;
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
        isInitialized = true;
    }

    /++
    Tests whether no more rows are available.
    +/
    @property bool empty() {
        return sqliteResult == SQLITE_DONE;
    }

    /++
    Gets the current row.
    +/
    @property Row front() {
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
unittest {
    string text = "TEXT";
    auto col = Column(0, "", Variant(text));
    assert(col.as!string == "TEXT");
}

//-----------------------------------------------------------------------------
// TESTS
//-----------------------------------------------------------------------------
unittest {
    assert(Sqlite.versionNumber > 3003011);
}

unittest {
    auto db = Database(":memory:");
    db.transaction;
    db.commit;
    assert(db.changes == 0);
    assert(db.totalChanges == 0);
}

unittest {
    // Tests copy-construction
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
    // Tests Query.rows()
    static assert(isInputRange!RowSet);
    auto db = Database(":memory:");
    auto query = Query(db, "CREATE TABLE test (val INTEGER)");
    query.execute;
    query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", 1024);
    query.execute;
    query = Query(db, "SELECT * FROM test");
    assert(!query.rows.empty);
    assert(query.rows.front["val"].as!int == 1024);
    query.rows.popFront();
    assert(query.rows.empty);
}

unittest {
    // Tests Database.changes() and Database.totalChanges()
    auto db = Database(":memory:");
    auto query = Query(db, "CREATE TABLE test (val INTEGER)");
    query.execute;
    assert(db.changes == 0);
    assert(db.totalChanges == 0);

    query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", 1024);
    query.execute;
    assert(db.changes == 1);
    assert(db.totalChanges == 1);
}

unittest {
    // Tests NULL values
    auto db = Database(":memory:");
    auto query = Query(db, "CREATE TABLE test (val INTEGER)");
    query.execute;

    query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", null);
    query.execute;

    query = Query(db, "SELECT * FROM test");
    assert(query.rows.front["val"].as!(int, -1024) == -1024);
}

unittest {
    // Tests INTEGER values
    auto db = Database(":memory:");
    auto query = Query(db, "CREATE TABLE test (val INTEGER)");
    query.execute;

    query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    int i = 1;
    query.bind(":val", &i);
    query.execute;
    query.reset;
    query.bind(":val", 1L);
    query.execute;
    assert(db.changes == 1);
    assert(db.totalChanges == 2);
    query.reset;
    query.bind(":val", 1U);
    query.execute;
    query.reset;
    query.bind(":val", 1UL);
    query.execute;
    query.reset;
    query.bind(":val", true);
    query.execute;
    query.reset;
    query.bind(":val", '\&copy;');
    query.execute;
    query.reset;
    query.bind(":val", '\x72');
    query.execute;
    query.reset;
    query.bind(":val", '\u1032');
    query.execute;
    query.reset;
    query.bind(":val", '\U0000FF32');
    query.execute;

    query = Query(db, "SELECT * FROM test");
    auto rows = query.rows;
    foreach (row; rows)
        assert(row["val"].as!long > 0);
}

unittest {
    // Tests FLOAT values
    auto db = Database(":memory:");
    auto query = Query(db, "CREATE TABLE test (val FLOAT)");
    query.execute;

    query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", 1.0F);
    query.execute;
    query.reset;
    query.bind(":val", 1.0);
    query.execute;
    query.reset;
    query.bind(":val", 1.0L);
    query.execute;

    query = Query(db, "SELECT * FROM test");
    auto rows = query.rows;
    foreach (row; rows)
        assert(row["val"].as!real > 0);
}

unittest {
    // Tests TEXT values
    auto db = Database(":memory:");
    auto query = Query(db, "CREATE TABLE test (val TEXT)");
    query.execute;

    query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B"c);
    query.execute;
    query.reset;
    query.bind(":val", "\uC720\uB2C8\uCF5B"w);
    query.execute;
    query.reset;
    query.bind(":val", "\uC720\uB2C8\uCF5B"d);
    query.execute;

    query = Query(db, "SELECT * FROM test");
    auto rows = query.rows;
    foreach (row; rows)
        assert(row["val"].as!string ==  "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B"c);
}

unittest {
    // Tests BLOB values with arrays
    auto db = Database(":memory:");
    auto query = Query(db, "CREATE TABLE test (val BLOB)");
    query.execute;

    query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    int[] array = [1, 2, 3, 4];
    query.bind(":val", array);
    query.execute;

    query = Query(db, "SELECT * FROM test");
    assert(query.rows.front["val"].as!(int[]) == [1, 2, 3, 4]);
}

unittest {
    // Tests BLOB values with structs
    auto db = Database(":memory:");
    auto query = Query(db, "CREATE TABLE test (val BLOB)");
    query.execute;

    struct Data {
        int integer;
        char character;
        real number;
        string text;
    }

    query = Query(db, "INSERT INTO test (val) VALUES (:val)");
    auto original = Data(1024, 'z', 3.14159e12, "foo");
    query.bind(":val", original);
    query.execute;

    query = Query(db, "SELECT * FROM test");
    auto copy = query.rows.front["val"].as!Data;
    assert(original == copy);
}

//-----------------------------------------------------------------------------
// SQLite C API
//-----------------------------------------------------------------------------
private:

enum {
	SQLITE_OK = 0,
	SQLITE_ROW = 100,
	SQLITE_DONE = 101
}

enum {
    SQLITE_INTEGER = 1,
    SQLITE_FLOAT = 2,
    SQLITE_TEXT = 3,
    SQLITE_BLOB = 4,
    SQLITE_NULL = 5,
}

struct sqlite3;
struct sqlite3_stmt;
struct sqlite3_context;
struct sqlite3_value;
struct sqlite3_blob;
struct sqlite3_module;
struct sqlite3_callback;
struct sqlite3_mutex;
struct sqlite3_backup;
struct sqlite3_vfs;

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
