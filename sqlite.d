// Written in the D programming language
/++
Simple and easy SQLite interface.

Executable must be linked to the SQLite library version 3.3.11 or later.

Objects in this interface (SqliteDatabase and SqliteQuery) are reference-counted. When the last reference goes out of scope, the objects are automatically closed and finalized. The user does not have to explicitly open or close them.

Example:
---
// Open an SQLite database (here in memory)
auto db = SqliteDatabase("");

// Create a table
auto query = SqliteQuery(db,
    "CREATE TABLE person (
        id INTEGER PRIMARY KEY,
        last_name TEXT NOT NULL,
        first_name TEXT,
        score REAL,
        photo BLOB
    )");
query.execute;

// Populate the table, using bindings
with (SqliteQuery(db, "INSERT INTO person (last_name, first_name, score, photo)
                       VALUES (:last_name, :first_name, :score, :photo)"))
{
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

// Count the persons in the table
query = SqliteQuery(db, "SELECT COUNT(*) FROM person");
writefln("Number of persons: %d", query.rows.front[0].as!int);

// Fetch the data from the table
query = SqliteQuery(db, "SELECT * FROM person");
foreach (row; query.rows)
{
    auto id = row["id"].as!int;
    auto name = row["first_name"].as!string ~ row["last_name"].as!string;
    auto score = row["score"].as!(real, 0.0); // score can be NULL, so provide 0.0 as
                                              // a default value to replace NULLs
    auto photo = row["photo"].as!(ubyte[]);
    writefln("[%d] %s scores %.1f", id, name, score);
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
SQLite thread mode (set at compile-time).
+/
enum SqliteThreadMode {
    SINGLETHREAD = 1, /// SQLite is unsafe to use in more than a single thread at once.
    MULTITHREAD = 2, /// SQLite can be safely used by multiple threads provided that no single database connection is used simultaneously in two or more threads. 
    SERIALIZED = 3 /// SQLite can be safely used by multiple threads with no restriction.
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
        return  sqlite3_libversion_number();
    }
    
    ///Gets the library's thread mode.
    static SqliteThreadMode threadMode() {
        return cast(SqliteThreadMode) sqlite3_threadsafe();
    }
}
unittest {
    assert(Sqlite.versionNumber > 3003011);
}

/++
An interface to a SQLite database connection.

Once a SqliteDatabase object is created, the database is open and can be used directly. The database is automatically closed when the last reference to the object goes out of scope. SqliteDatabase is not thread-safe.
+/
struct SqliteDatabase {
    private struct payload {
        string filename;
        sqlite3* handle;
        int refcount;
        bool inTransaction;
    }
    private payload* pl;

    /++
    Opens a database with the name passed in the parameter. The file name can be empty or set to ":memory:" according to the SQLite specification.
    +/
    this(string filename) {
        //debug(SQLITE) writefln("Opening database '%s'", filename);
        assert(filename);
        pl = new payload;
        pl.filename = filename;
        auto result = sqlite3_open(cast(char*) pl.filename.toStringz, &pl.handle);
        enforceEx!SqliteException(result == SQLITE_OK, errorMsg);
        pl.refcount = 1;
        pl.inTransaction = false;
    }

    this(this) {
        assert(pl);
        pl.refcount++;
    }
    
    ~this() {
        assert(pl);
        pl.refcount--;
        if (pl.refcount == 0) {
            //debug(SQLITE) writefln("Closing database '%s'", _filename);
            if (pl.inTransaction) {
                commit;
                enforceEx!SqliteException(errorCode == SQLITE_OK, errorMsg);                
            }
            auto result = sqlite3_close(pl.handle);
            enforceEx!SqliteException(result == SQLITE_OK, errorMsg);
            pl = null;
        }
    }
    
    void opAssign(SqliteDatabase rhs) {
        assert(pl);
        assert(rhs.pl);
        swap(pl, rhs.pl);
    }
    
    /++
    Begins a transaction. No-op if already in _transaction.
    +/
    void transaction() {
        //debug(SQLITE) writeln("Beginning a transaction");
        if (!pl.inTransaction) {
            auto q = SqliteQuery(this, "BEGIN TRANSACTION");
            q.execute;
            pl.inTransaction = true;
        }
    }

    /++
    Commits the current transaction. No-op if no transaction was started.
    +/
    void commit() {
        //debug(SQLITE) writeln("Committing transaction");
        if (pl.inTransaction) {
            auto q = SqliteQuery(this, "COMMIT TRANSACTION");
            q.execute;
            pl.inTransaction = false;
        }
    }

    /++
    Rolls back the current transaction. No-op if no transaction was started.
    +/
    void rollback() {
        //debug(SQLITE) writeln("Rolling back transaction");
        if (pl.inTransaction) {
            auto q = SqliteQuery(this, "ROLLBACK TRANSACTION");
            q.execute;
            pl.inTransaction = false;
        }
    }
    
    /++
    Gets the database file name.
    +/
    @property string filename() {
        assert(pl);
        return pl.filename;
    }
    
    /++
    Gets the number of database rows that were changed, inserted or deleted by the most recently completed query.
    +/
    @property int changes() {
        return sqlite3_changes(pl.handle);
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted since the database was opened.
    +/
    @property int totalChanges() {
        return sqlite3_total_changes(pl.handle);
    }
    
    /++
    Gets the SQLite error code of the last operation.
    +/
    @property int errorCode() {
        return sqlite3_errcode(pl.handle);
    }
    
    /++
    Gets the SQLite error message of the last operation.
    +/
    @property string errorMsg() {
        return to!string(sqlite3_errmsg(pl.handle));
    }
    
    /++
    Gets the SQLite internal _handle of the database connection.
    +/
    @property sqlite3* handle() {
        assert(pl);
        return pl.handle;
    }
    
    private void retain() {
        assert(pl);
        pl.refcount++;
    }
    
    private void release() {
        assert(pl);
        pl.refcount--;
    }
    
    unittest {
        auto db = SqliteDatabase(":memory:");
        db.transaction;
        db.commit;
        assert(db.changes == 0);
        assert(db.totalChanges == 0);
    }
}

/++
Detect whether type T is accepted as the type of a SQLite value. Accepted types are:
$(UL
    $(LI for INTEGER values: integral types, including bool)
    $(LI for NUMERIC or REAL values: floating point types)
    $(LI for TEXT values: string types and character types)
    $(LI for BLOB values: ubyte[])
    $(LI for NULL values: void*)
)
+/
template isValidSqliteType(T) {
    enum bool isValidSqliteType =
           isImplicitlyConvertible!(Unqual!T, long)
        || isImplicitlyConvertible!(Unqual!T, real)
        || isSomeChar!T
        || isSomeString!T
        || isArray!T
        || isPointer!T
        || is(T == struct)
        ;
}
unittest {
    assert(isValidSqliteType!bool);
    assert(isValidSqliteType!byte);
    assert(isValidSqliteType!ubyte);
    assert(isValidSqliteType!short);
    assert(isValidSqliteType!ushort);
    assert(isValidSqliteType!int);
    assert(isValidSqliteType!uint);
    assert(isValidSqliteType!long);
    assert(isValidSqliteType!ulong);
    assert(isValidSqliteType!float);
    assert(isValidSqliteType!double);
    assert(isValidSqliteType!real);
    assert(isValidSqliteType!char);
    assert(isValidSqliteType!wchar);
    assert(isValidSqliteType!dchar);
    assert(isValidSqliteType!string);
    assert(isValidSqliteType!wstring);
    assert(isValidSqliteType!dstring);
    assert(isValidSqliteType!(ubyte[]));
    assert(isValidSqliteType!(void[]));
    assert(isValidSqliteType!(int*));
    assert(isValidSqliteType!(typeof(null)));

    struct s {}
    assert(isValidSqliteType!s);
    
    enum e1 : int { dummy = 0 }
    enum e2 : real { dummy = 0.0 }
    enum e3 : string { dummy = "0" }
    assert(isValidSqliteType!(typeof(e1.dummy)));
    assert(isValidSqliteType!(typeof(e2.dummy)));
    assert(isValidSqliteType!(typeof(e3.dummy)));
    
    union u {}
    class c {}
    interface i {}
    enum e5 : s { dummy = s() }
    void f() {}
    
    assert(!isValidSqliteType!u);
    assert(!isValidSqliteType!c);
    assert(!isValidSqliteType!i);
    assert(!isValidSqliteType!(typeof(e5.dummy)));
    assert(!isValidSqliteType!(typeof(f)));
    assert(!isValidSqliteType!void);
}

/++
An interface to SQLite query execution.

Use execute to execute queries that do not expect rows as their result (CREATE TABLE, INSERT, UPDATE...). Use rows without a prior call to execute for queries that expect rows as their result (SELECT).

Once a SqliteQuery object is created, the query can be used directly. The query is automatically closed when the last reference to the object goes out of scope.  SqliteDatabase is not thread-safe.
+/
struct SqliteQuery {
    private struct payload {
        SqliteDatabase* db;
        string sql;
        sqlite3_stmt* statement;
        int refcount;
        bool isdirty;        
    }
    private payload* pl;
    
    this(ref SqliteDatabase db, string sql) {
        //debug(SQLITE) writeln("Creating query");
        pl = new payload;
        pl.db = &db;
        pl.db.retain;
        pl.sql = sql;
        char* unused;
        auto result = sqlite3_prepare_v2(pl.db.handle, cast(char*) pl.sql.toStringz, pl.sql.length, &pl.statement, &unused);
        enforceEx!SqliteException(result == SQLITE_OK, pl.db.errorMsg);
        pl.refcount = 1;
        pl.isdirty = false;
    }
    
    this(this) {
        assert(pl);
        pl.refcount++;
    }

    ~this() {
        assert(pl);
        pl.refcount--;
        if (pl.refcount == 0) {
            //debug(SQLITE) writeln("Deleting query");
            sqlite3_finalize(pl.statement);
            pl.db.release;
            pl = null;
        }
    }
    
    void opAssign(SqliteQuery rhs) {
        assert(pl);
        assert(rhs.pl);
        swap(pl, rhs.pl);
    }
    
    /++
    Binds a value to a named parameter in the query.
    +/
    void bind(T)(string parameter, T value) {
        assert(pl);
        assert(pl.statement);
        int index = 0;
        index = sqlite3_bind_parameter_index(pl.statement, cast(char*) parameter.toStringz);
        enforceEx!SqliteException(index, format("parameter named '%s' cannot be bound", parameter));
        bind(index, value);
    }
    
    /++
    Binds a value to an indexed parameter in the query.
    +/
    void bind(T)(int index, T value) {
        static assert(isValidSqliteType!T, "cannot convert a column value to type " ~ T.stringof);

        assert(pl);
        assert(pl.statement);
        int result;

        static if (isImplicitlyConvertible!(Unqual!T, long)) {
            //debug(SQLITE) writefln("binding %d (%s) at index %d", value, typeof(value).stringof, index);
            result = sqlite3_bind_int64(pl.statement, index, cast(long) value);
        }
        else static if (isImplicitlyConvertible!(Unqual!T, real)) {
            //debug(SQLITE) writefln("binding %f (%s) at index %d", value, typeof(value).stringof, index);
            result = sqlite3_bind_double(pl.statement, index, value);
        }
        else static if (isSomeString!T) {
            //debug(SQLITE) writefln("binding '%s' (%s) at index %d ", value, typeof(value).stringof, index);
            if (value is null)
                result = sqlite3_bind_null(pl.statement, index);
            else {
                string utf8 = value.toUTF8;
                result = sqlite3_bind_text(pl.statement, index, cast(char*) utf8.toStringz, utf8.length, null);
            }
        }
        else static if (isPointer!T && !is(T == void*)) {
            if (value is null) {
                //debug(SQLITE) writefln("binding a NULL at index %d", index);
                result = sqlite3_bind_null(pl.statement, index);
            }
            else {
                bind(index, *value);
                return;
            }
        }
        else static if (is(T == void*)) {
            //debug(SQLITE) writefln("binding a NULL at index %d", index);
            result = sqlite3_bind_null(pl.statement, index);
        }
        else static if (isArray!T) {
            //debug(SQLITE) writefln("binding a %s as a BLOB at index %d", typeof(value).stringof, index);
            void[] buffer = cast(void[]) value;
            result = sqlite3_bind_blob(pl.statement, index, cast(void*) buffer.ptr, buffer.length, null);
        }
        else static if (!is(T == void)) {
            //debug(SQLITE) writefln("binding a %s as a BLOB at index %d", typeof(value).stringof, index);
            void[] buffer;
            buffer.length = T.sizeof;
            memcpy(buffer.ptr, &value, buffer.length);
            result = sqlite3_bind_blob(pl.statement, index, cast(void*) buffer.ptr, buffer.length, null);
        }
        else
            static assert(isValidSqliteType!T, "cannot bind a void value");

        enforceEx!SqliteException(result == SQLITE_OK, pl.db.errorMsg);
    }
    
    /++
    Execute a query that does not expect rows as its result.
    +/
    void execute() {
        assert(pl);
        assert(pl.statement);
        auto result = sqlite3_step(pl.statement);
        assert(result != SQLITE_ROW, "call to SqliteQuery.execute() on a query that return rows, use SqliteQuery.rows instead");
        enforceEx!SqliteException(result == SQLITE_DONE, pl.db.errorMsg);
    }
    
    /++
    Gets the results of a query that returns _rows.
    +/
    @property SqliteRowSet rows() {
        assert(pl);
        enforceEx!SqliteException(!pl.isdirty, "SqliteQuery.rows called twice without resetting");
        pl.isdirty = true;
        return SqliteRowSet(&this);
    }
    
    /++
    Resets a query and clears all bindings.
    +/
    void reset() {
        assert(pl);
        assert(pl.statement);
        auto result = sqlite3_reset(pl.statement);
        enforceEx!SqliteException(result == SQLITE_OK, pl.db.errorMsg);
        sqlite3_clear_bindings(pl.statement);
        pl.isdirty = false;
    }
    
    private void retain() {
        assert(pl);
        pl.refcount++;
    }
    
    private void release() {
        assert(pl);
        pl.refcount--;
    }

    unittest {
        auto db = SqliteDatabase(":memory:");
        auto query = SqliteQuery(db, "CREATE TABLE test (val INTEGER)");
        query.execute;
        assert(db.changes == 0);
        assert(db.totalChanges == 0);
        
        int i = 1;
        query = SqliteQuery(db, "INSERT INTO test (val) VALUES (:val)");
        query.bind(":val", &i);
        query.execute;
        assert(db.changes == 1);
        assert(db.totalChanges == 1);
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
        
        query = SqliteQuery(db, "SELECT * FROM test");
        auto rows = query.rows;
        foreach (row; rows) {
            assert(row["val"].as!long > 0);
        }
    }
    
    unittest {
        auto db = SqliteDatabase(":memory:");
        auto query = SqliteQuery(db, "CREATE TABLE test (val FLOAT)");
        query.execute;
        
        query = SqliteQuery(db, "INSERT INTO test (val) VALUES (:val)");
        query.bind(":val", 1.0F);
        query.execute;
        query.reset;
        query.bind(":val", 1.0);
        query.execute;
        query.reset;
        query.bind(":val", 1.0L);
        query.execute;
        
        query = SqliteQuery(db, "SELECT * FROM test");
        auto rows = query.rows;
        foreach (row; rows) {
            assert(row["val"].as!real > 0);
        }
    }
    
    unittest {
        auto db = SqliteDatabase(":memory:");
        auto query = SqliteQuery(db, "CREATE TABLE test (val TEXT)");
        query.execute;
        
        query = SqliteQuery(db, "INSERT INTO test (val) VALUES (:val)");
        query.bind(":val", "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B"c);
        query.execute;
        query.reset;
        query.bind(":val", "\uC720\uB2C8\uCF5B"w);
        query.execute;
        query.reset;
        query.bind(":val", "\uC720\uB2C8\uCF5B"d);
        query.execute;
        
        query = SqliteQuery(db, "SELECT * FROM test");
        auto rows = query.rows;
        foreach (row; rows) {
            assert(row["val"].as!string == "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B"c);
        }
    }
    
    unittest {
        auto db = SqliteDatabase(":memory:");
        auto query = SqliteQuery(db, "CREATE TABLE test (val BLOB)");
        query.execute;
        
        struct Data {
            int i = 2048;
            char c = '\xFF';
        }
        auto data = [2048, 0xFF];
        
        query = SqliteQuery(db, "INSERT INTO test (val) VALUES (:val)");
        query.bind(":val", Data());
        query.execute;
        query.reset;
        query.bind(":val", data);
        query.execute;
        
        query = SqliteQuery(db, "SELECT * FROM test");
        auto rows = query.rows;
        foreach (row; rows) {
            assert(row["val"].as!(immutable(ubyte)[]) == [0, 8, 0, 0, 255, 0, 0, 0]);
        }
    }
}

/++
The results of a query that returns rows, with an InputRange interface.
+/
struct SqliteRowSet {
    private SqliteQuery* query;
    private int sqliteResult;
    
    /++
    A single row.
    +/
    struct SqliteRow {
        private SqliteColumn[] columns;
        
        /++
        A single column
        +/
        struct SqliteColumn {
            int index;
            string name;
            Variant data;
            
            /++
            Gets the value of the column converted to type T.
            
            If the value is NULL, it is replaced by value.
            +/
            @property T as(T, T value)() {
                static assert(isValidSqliteType!T, "cannot convert a column value to type " ~ T.stringof);
                
                if (data.hasValue) {
                    static if (is(T == bool)) {
                        return data.get!long != 0;
                    }
                    else static if (isIntegral!T) {
                        return to!T(data.get!long);
                    }
                    else static if (isSomeChar!T) {
                        return to!T(data.get!string[0]);
                    }
                    else static if (isFloatingPoint!T) {
                        return to!T(data.get!double);
                    }
                    else static if (isSomeString!T) {
                        static if (is(Unqual!T == string))
                            return data.get!string;
                        else static if (is(Unqual!T == wstring))
                            return data.get!string.toUTF16;
                        else
                            return data.get!string.toUTF32;
                    }
                    else static if (isArray!T) {
                        return cast(T) data.get!(ubyte[]);
                    }
                }
                else
                    return value;
            }
            
            /++
            Gets the value of the column converted to type T.
            
            Same _as above but throws an exception when a NULL value is converted into a type that cannot be null.
            +/
            @property T as(T)() {
                static if (isPointer!T || isDynamicArray!T) {
                    if (data.hasValue)
                        return as!(T, T.init)();
                    else
                        return null;
                }
                else {
                    if (data.hasValue)
                        return as!(T, T.init)();
                    else
                        throw new SqliteException("cannot set a value of type " ~ T.stringof ~ " to null");                
                }
            }
        }
        
        /++
        Gets the number of columns in this row.
        +/
        @property int columnCount() {
            return columns.length;
        }
        
        /++
        Gets the column at the given index.
        +/
        SqliteColumn opIndex(int index) {
            auto f = filter!((SqliteColumn c) { return c.index == index; })(columns);
            if (!f.empty)
                return f.front;
            else
                throw new SqliteException(format("invalid column index: %d", index));
        }
        
        /++
        Gets the column from its name.
        +/
        SqliteColumn opIndex(string name) {
            auto f = filter!((SqliteColumn c) { return c.name == name; })(columns);
            if (!f.empty)
                return f.front;
            else
                throw new SqliteException("invalid column name: " ~ name);
        }
    }
    
    private this(SqliteQuery* query) {
        this.query = query;
        query.retain;
        sqliteResult = sqlite3_step(query.pl.statement);
    }
    
    ~this() {
        query.release;
        query = null;
    }
    
    /++
    Tests whether no more rows are available.
    +/
    @property bool empty() {
        return sqliteResult != SQLITE_ROW;
    }
    
    /++
    Gets the current row.
    +/
    @property SqliteRow front() {
        SqliteRow row;
        auto colcount = sqlite3_column_count(query.pl.statement);
        row.columns.reserve(colcount);
        for (int i = 0; i < colcount; i++) {
            auto name = to!string(sqlite3_column_name(query.pl.statement, i));
            auto type = sqlite3_column_type(query.pl.statement, i);
            final switch(type) {
            case SQLITE_INTEGER:
                row.columns ~= SqliteRow.SqliteColumn(i, name, Variant(sqlite3_column_int64(query.pl.statement, i)));
                break;
                
            case SQLITE_FLOAT:
                row.columns ~= SqliteRow.SqliteColumn(i, name, Variant(sqlite3_column_double(query.pl.statement, i)));
                break;

            case SQLITE_TEXT:
                auto str = to!string(sqlite3_column_text(query.pl.statement, i));
                str.validate;
                row.columns ~= SqliteRow.SqliteColumn(i, name, Variant(str));
                break;
                
            case SQLITE_BLOB:
                auto ptr = sqlite3_column_blob(query.pl.statement, i);
                auto length = sqlite3_column_bytes(query.pl.statement, i);
                ubyte[] blob;
                blob.length = length;
                memcpy(blob.ptr, ptr, length);
                row.columns ~= SqliteRow.SqliteColumn(i, name, Variant(blob));
                break;
            
            case SQLITE_NULL:
                row.columns ~= SqliteRow.SqliteColumn(i, name, Variant());
                break;
            }
        }
        return row;
    }
    
    /++
    Jumps to the next row.
    +/
    void popFront() {
        sqliteResult = sqlite3_step(query.pl.statement);
    }
    
    unittest {
        assert(isInputRange!SqliteRowSet);
    }
}

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

struct sqlite3 { /* Opaque structure */ }
struct sqlite3_stmt { /* Opaque structure */ }
struct sqlite3_value { /* Opaque structure */ }

alias long sqlite3_int64;
alias ulong sqlite3_uint64;

extern(C):

char* sqlite3_libversion();
int sqlite3_libversion_number();
int sqlite3_threadsafe();
int sqlite3_errcode(sqlite3*);
char* sqlite3_errmsg(sqlite3*);
int sqlite3_open(char*, sqlite3**);
int sqlite3_close(sqlite3*);
int sqlite3_prepare_v2(sqlite3*, char*, int, sqlite3_stmt**, char**);
int sqlite3_step(sqlite3_stmt*);
int sqlite3_changes(sqlite3*);
int sqlite3_total_changes(sqlite3*);
int sqlite3_finalize(sqlite3_stmt*);
int sqlite3_reset(sqlite3_stmt*);
int sqlite3_bind_blob(sqlite3_stmt*, int, void*, int n, void function(void*));
int sqlite3_bind_double(sqlite3_stmt*, int, double);
int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64);
int sqlite3_bind_null(sqlite3_stmt*, int);
int sqlite3_bind_text(sqlite3_stmt*, int, char*, int n, void function(void*));
//int sqlite3_bind_text16(sqlite3_stmt*, int, void*, int n, void function(void*));
int sqlite3_bind_parameter_index(sqlite3_stmt*, char*);
int sqlite3_clear_bindings(sqlite3_stmt*);
void* sqlite3_column_blob(sqlite3_stmt*, int);
int sqlite3_column_bytes(sqlite3_stmt*, int);
double sqlite3_column_double(sqlite3_stmt*, int);
sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int);
char* sqlite3_column_text(sqlite3_stmt*, int);
//void* sqlite3_column_text16(sqlite3_stmt*, int);
int sqlite3_column_type(sqlite3_stmt*, int);
char* sqlite3_column_name(sqlite3_stmt*, int);
int sqlite3_column_count(sqlite3_stmt*);
