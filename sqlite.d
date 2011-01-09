// Written in the D programming language
/++
Simple and easy SQLite interface.

Objects in this interface (SqliteDatabase and SqliteQuery) are reference-counted. When the last reference goes out of scope, the objects are automatically closed and finalized. The user does not have to explicitly open or close them.

Example:
---
// Open an SQLite database (here in memory)
auto db = SqliteDatabase(":memory:");

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

Issues:$(UL
$(LI TEXT values must be UTF8-encoded.)
)

Todo:$(UL
$(LI implement backup API: $(LINK http://www.sqlite.org/backup.html).)
)

Author: Nicolas Sicard.
+/
module sqlite;

import std.algorithm;
import std.conv;
import std.exception;
import std.string;
import std.range;
import std.traits;
import std.variant;

pragma(lib, "sqlite3");

debug=SQLITE;
debug(SQLITE) import std.stdio;

/++
Exception thrown then SQLite functions return error codes.
+/
class SqliteException : Exception {
    this(string msg) {
        super(msg);
    }
}

/++
Once a SqliteDatabase object is created, the database is open and can be used directly. The database is automatically closed when the last reference to the object goes out of scope.
+/
struct SqliteDatabase {
    private struct payload {
        private string filename;
        private sqlite3* handle;
        private int refcount;
    }
    private payload* pl;

    /++
    Opens a database with the name passed in the parameter.
    
    If filename is empty, the database is open in a temporary file, and if filename is ":memory:", the database is open in memory (implied by SQLite).
    +/
    this(string filename) {
        //debug(SQLITE) writefln("Opening database '%s'", filename);
        assert(filename);
        pl = new payload;
        pl.filename = filename;
        auto result = sqlite3_open(cast(char*) pl.filename.toStringz, &pl.handle);
        enforceEx!SqliteException(result == SQLITE_OK, to!string(sqlite3_errmsg(pl.handle)));
        pl.refcount = 1;
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
            auto result = sqlite3_close(pl.handle);
            enforceEx!SqliteException(result == SQLITE_OK, to!string(sqlite3_errmsg(pl.handle)));
            pl = null;
        }
    }
    
    void opAssign(SqliteDatabase rhs) {
        assert(pl);
        assert(rhs.pl);
        swap(pl, rhs.pl);
    }
    
    version(none) {
        private bool _inTransaction = false;
        
        /++
        Begins a transaction.
        +/
        void transaction() {
            //debug(SQLITE) writeln("Beginning a transaction");
            auto q = query("BEGIN TRANSACTION");
            q.execute;
        }

        /++
        Commits the current transaction.
        +/
        void commit() {
            //debug(SQLITE) writeln("Committing transaction");
            auto q = query("COMMIT TRANSACTION");
            q.execute;
        }

        /++
        Rolls back the current transaction.
        +/
        void rollback() {
            //debug(SQLITE) writeln("Rolling back transaction");
            auto q = query("ROLLBACK TRANSACTION");
            q.execute;
        }
    }

    /++
    Returns the SQLite internal handle of the database connection.
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
}

/++
Detect whether type T is accepted as the type of a SQLite value.
+/
template isValidSqliteType(T) {
    enum bool isValidSqliteType =
           is(T == bool)
        || isIntegral!T
        || isFloatingPoint!T
        || isArray!T
        || isPointer!T;
}

/++
Once a SqliteQuery object is created, the query can be used directly. The query is automatically closed when the last reference to the object goes out of scope. Use execute to execute queries that do not expect rows as their result (CREATE TABLE, INSERT, UPDATE...). Use rows without a prior call to execute for queries that expect rows as their result (SELECT).
+/
struct SqliteQuery {
    private struct payload {
        private SqliteDatabase* db;
        private string sql;
        private sqlite3_stmt* statement;
        private int refcount;
        private bool isdirty;        
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
        enforceEx!SqliteException(result == SQLITE_OK, to!string(sqlite3_errmsg(pl.db.handle)));
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

        static if (isSomeString!T) {
            //debug(SQLITE) writefln("binding a string at index %d ", index);
            if (value is null)
                result = sqlite3_bind_null(pl.statement, index);
            else
                result = sqlite3_bind_text(pl.statement, index, cast(char*) value.toStringz, value.length, null);
        }
        else static if (isArray!T) {
            //debug(SQLITE) writefln("binding an array at index %d", index);
            if (value is null)
                result = sqlite3_bind_null(pl.statement, index);
            else
                result = sqlite3_bind_blob(pl.statement, index, (cast(ubyte[]) value).ptr, value.length, null);
        }
        else static if (is(T == void*)) {
            enforce(value is null, "cannot bind with non-null of type void*");
            //debug(SQLITE) writefln("binding a null value at index %d", index);
            result = sqlite3_bind_null(pl.statement, index);
        }
        else static if (isIntegral!T || is(T == bool)) {
            //debug(SQLITE) writefln("binding an integral or bool at index %d", index);
            result = sqlite3_bind_int64(pl.statement, index, cast(long) value);
        }
        else static if (isFloatingPoint!T) {
            //debug(SQLITE) writefln("binding a floating poing value at index %d", index);
            result = sqlite3_bind_double(pl.statement, index, value);
        }
        else {
            static assert(false, "cannot bind with object of type " ~ T.stringof);
        }

        enforceEx!SqliteException(result == SQLITE_OK, to!string(sqlite3_errmsg(pl.db.handle)));
    }
    
    /++
    Execute a query that does not expect rows as its result.
    +/
    void execute() {
        assert(pl);
        assert(pl.statement);
        auto result = sqlite3_step(pl.statement);
        assert(result != SQLITE_ROW, "call to SqliteQuery.execute() on a query that return rows, use SqliteQuery.rows instead");
        enforceEx!SqliteException(result == SQLITE_DONE, to!string(sqlite3_errmsg(pl.db.handle)));
    }
    
    /++
    Gets the results of a query that returns rows.
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
        enforceEx!SqliteException(result == SQLITE_OK, to!string(sqlite3_errmsg(pl.db.handle)));
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
}

/++
The results of a query that returns rows, with an InputRange interface.
+/
struct SqliteRowSet {
    private SqliteQuery* _query;
    private int sqliteResult;
    
    /++
    A single row.
    +/
    struct SqliteRow {
        private SqliteColumn[] _columns;
        
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
                    else static if (isFloatingPoint!T) {
                        return to!T(data.get!double);
                    }
                    else static if (isSomeString!T) {
                        return to!T(data.get!string);
                    }
                    else static if (isArray!T && !isSomeString!T) {
                        return cast(T) data.get!T;
                    }
                }
                else
                    return value;
            }
            
            /++
            Gets the value of the column converted to type T.
            
            Same as above but throws an exception when a NULL value is converted into a type that cannot be null.
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
            
            /+debug(SQLITE) {
                string toString() {
                    if (data.hasValue)
                        return to!string(data);
                    else
                        return "<null>";
                }
            }+/
        }
        
        /++
        Gets the number of columns in this row.
        +/
        @property int columnCount() {
            return _columns.length;
        }
        
        /++
        Gets the column at the given index.
        +/
        SqliteColumn opIndex(int index) {
            auto f = filter!((SqliteColumn c) { return c.index == index; })(_columns);
            if (!f.empty)
                return f.front;
            else
                throw new SqliteException(format("invalid column index: %d", index));
        }
        
        /++
        Gets the column from its name.
        +/
        SqliteColumn opIndex(string name) {
            auto f = filter!((SqliteColumn c) { return c.name == name; })(_columns);
            if (!f.empty)
                return f.front;
            else
                throw new SqliteException("invalid column name: " ~ name);
        }
        
        /+debug(SQLITE) {
            string toString() {
                return to!string(_columns);
            }
        }+/
    }
    
    private this(SqliteQuery* query) {
        _query = query;
        _query.retain;
        
        sqliteResult = sqlite3_step(_query.pl.statement);
    }
    
    ~this() {
        _query.release;
        _query = null;
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
        auto colcount = sqlite3_column_count(_query.pl.statement);
        row._columns.reserve(colcount);
        for (int i = 0; i < colcount; i++) {
            auto name = to!string(sqlite3_column_name(_query.pl.statement, i));
            auto type = sqlite3_column_type(_query.pl.statement, i);
            final switch(type) {
            case SQLITE_INTEGER:
                row._columns ~= SqliteRow.SqliteColumn(i, name, Variant(sqlite3_column_int64(_query.pl.statement, i)));
                break;
                
            case SQLITE_FLOAT:
                row._columns ~= SqliteRow.SqliteColumn(i, name, Variant(sqlite3_column_double(_query.pl.statement, i)));
                break;

            case SQLITE_TEXT:
                row._columns ~= SqliteRow.SqliteColumn(i, name, Variant(to!string(sqlite3_column_text(_query.pl.statement, i))));
                break;
                
            case SQLITE_BLOB:
                auto ptr = sqlite3_column_blob(_query.pl.statement, i);
                auto length = sqlite3_column_bytes(_query.pl.statement, i);
                ubyte[] blob;
                blob.length = length;
                memcpy(blob.ptr, ptr, length);
                row._columns ~= SqliteRow.SqliteColumn(i, name, Variant(blob));
                break;
            
            case SQLITE_NULL:
                row._columns ~= SqliteRow.SqliteColumn(i, name, Variant());
                break;
            }
        }
        return row;
    }
    
    /++
    Jumps to the next row.
    +/
    void popFront() {
        sqliteResult = sqlite3_step(_query.pl.statement);
    }
}
unittest {
    assert(isInputRange!SqliteRowSet);
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

int sqlite3_errcode(sqlite3*);
char* sqlite3_errmsg(sqlite3*);
int sqlite3_open(char*, sqlite3**);
int sqlite3_close(sqlite3*);
int sqlite3_prepare_v2(sqlite3*, char*, int, sqlite3_stmt**, char**);
int sqlite3_step(sqlite3_stmt*);
int sqlite3_finalize(sqlite3_stmt*);
int sqlite3_reset(sqlite3_stmt*);
int sqlite3_bind_blob(sqlite3_stmt*, int, void*, int n, void function(void*));
int sqlite3_bind_double(sqlite3_stmt*, int, double);
int sqlite3_bind_int64(sqlite3_stmt*, int, sqlite3_int64);
int sqlite3_bind_null(sqlite3_stmt*, int);
int sqlite3_bind_text(sqlite3_stmt*, int, char*, int n, void function(void*));
int sqlite3_bind_parameter_index(sqlite3_stmt*, char*);
int sqlite3_clear_bindings(sqlite3_stmt*);
void* sqlite3_column_blob(sqlite3_stmt*, int);
int sqlite3_column_bytes(sqlite3_stmt*, int);
double sqlite3_column_double(sqlite3_stmt*, int);
sqlite3_int64 sqlite3_column_int64(sqlite3_stmt*, int);
char* sqlite3_column_text(sqlite3_stmt*, int);
int sqlite3_column_type(sqlite3_stmt*, int);
char* sqlite3_column_name(sqlite3_stmt*, int);
int sqlite3_column_count(sqlite3_stmt*);
