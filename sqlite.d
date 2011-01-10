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
        auto id = row["id"].to!int;
        auto name = format("%s, %s", row["last_name"].to!string, 
                                     row["first_name"].to!string);
        auto score = row["score"].to!(real, 0.0); // score can be NULL,
        //           so provide 0.0 as a default value to replace NULLs
        auto photo = row["photo"].to!(void[]);
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

//debug=SQLITE;
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
enum ThreadMode {
    SINGLETHREAD = 1, /// SQLite is unsafe to use in more than
                      /// a single thread at once.
    MULTITHREAD = 2,  /// SQLite can be safely used by multiple threads
                      /// provided that no single database connection
                      /// is used simultaneously in two or more threads. 
    SERIALIZED = 3    /// SQLite can be safely used by multiple threads
                      /// with no restriction.
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
    static ThreadMode threadMode() {
        return cast(ThreadMode) sqlite3_threadsafe();
    }
}
unittest {
    assert(Sqlite.versionNumber > 3003011);
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
        auto result = sqlite3_open(
                        cast(char*) core.path.toStringz,
                        &core.handle);
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
        enforceEx!SqliteException(!core.inTransaction,
            "cannot begin transaction: already in transaction");
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
        enforceEx!SqliteException(core.inTransaction,
            "no transaction to commit");
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
        enforceEx!SqliteException(core.inTransaction,
            "no transaction to rollback");
        auto q = Query(this, "ROLLBACK TRANSACTION");
        q.execute;
        core.inTransaction = false;
    }
    
    /++
    Gets the database file name.
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
    
    unittest {
        auto db = Database(":memory:");
        db.transaction;
        db.commit;
        assert(db.changes == 0);
        assert(db.totalChanges == 0);
    }
}

/+
Detect whether type T is accepted as the type of a SQLite value. Accepted
types are:
$(UL
    $(LI integral types, including bool)
    $(LI floating point types)
    $(LI string and character types)
    $(LI arrays, structs and unions)
    $(LI void*)
)
+/
private template isValidSqliteType(T) {
    enum bool isValidSqliteType =
           isImplicitlyConvertible!(Unqual!T, long)
        || isImplicitlyConvertible!(Unqual!T, real)
        || isSomeChar!T
        || isSomeString!T
        || isArray!T
        || isPointer!T
        || is(T == struct)
        || is(T == union);
}
version(unittest) {
    static assert(isValidSqliteType!bool);
    static assert(isValidSqliteType!byte);
    static assert(isValidSqliteType!ubyte);
    static assert(isValidSqliteType!short);
    static assert(isValidSqliteType!ushort);
    static assert(isValidSqliteType!int);
    static assert(isValidSqliteType!uint);
    static assert(isValidSqliteType!long);
    static assert(isValidSqliteType!ulong);
    static assert(isValidSqliteType!float);
    static assert(isValidSqliteType!double);
    static assert(isValidSqliteType!real);
    static assert(isValidSqliteType!char);
    static assert(isValidSqliteType!wchar);
    static assert(isValidSqliteType!dchar);
    static assert(isValidSqliteType!string);
    static assert(isValidSqliteType!wstring);
    static assert(isValidSqliteType!dstring);
    static assert(isValidSqliteType!(ubyte[]));
    static assert(isValidSqliteType!(void[]));
    static assert(isValidSqliteType!(int*));
    static assert(isValidSqliteType!(typeof(null)));
    struct s {}
    static assert(isValidSqliteType!s);
    union u {}
    static assert(isValidSqliteType!u);
    enum e1 : int { dummy = 0 }
    static assert(isValidSqliteType!(typeof(e1.dummy)));
    enum e2 : real { dummy = 0.0 }
    static assert(isValidSqliteType!(typeof(e2.dummy)));
    enum e3 : string { dummy = "0" }
    static assert(isValidSqliteType!(typeof(e3.dummy)));
    enum e4 : s { dummy = s() }
    static assert(!isValidSqliteType!(typeof(e4.dummy)));
    class c {}
    static assert(!isValidSqliteType!c);
    interface i {}
    static assert(!isValidSqliteType!i);
    void f() {}
    static assert(!isValidSqliteType!(typeof(f)));
    static assert(!isValidSqliteType!void);
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
        bool isClean;
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
        core.db = &db;
        core.db.retain;
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
        assert(core.statement);
        core.refcount--;
        if (core.refcount == 0) {
            auto result = sqlite3_finalize(core.statement);
            enforceEx!SqliteException(result == SQLITE_OK, core.db.errorMsg);
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
        index = sqlite3_bind_parameter_index(
                    core.statement,
                    cast(char*) parameter.toStringz);
        enforceEx!SqliteException(index, 
            format("parameter named '%s' cannot be bound", parameter));
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
        static assert(isValidSqliteType!T,
            "cannot convert a column value to type " ~ T.stringof);
        assert(core.statement);
        
        int result;
        static if (isImplicitlyConvertible!(Unqual!T, long)) {
            result = sqlite3_bind_int64(
                        core.statement,
                        index, cast(long) value
                    );
        }
        else static if (isImplicitlyConvertible!(Unqual!T, real)) {
            result = sqlite3_bind_double(core.statement, index, value);
        }
        else static if (isSomeString!T) {
            if (value is null)
                result = sqlite3_bind_null(core.statement, index);
            else {
                string utf8 = value.toUTF8;
                result = sqlite3_bind_text(
                            core.statement,
                            index,
                            cast(char*) utf8.toStringz,
                            utf8.length,
                            null
                        );
            }
        }
        else static if (isPointer!T && !is(T == void*)) {
            if (value is null) {
                result = sqlite3_bind_null(core.statement, index);
            }
            else {
                bind(index, *value);
                return;
            }
        }
        else static if (is(T == void*)) {
            result = sqlite3_bind_null(core.statement, index);
        }
        else static if (isArray!T) {
            void[] buffer = cast(void[]) value;
            result = sqlite3_bind_blob(
                        core.statement, index,
                        cast(void*) buffer.ptr,
                        buffer.length,
                        null
                    );
        }
        else static if (!is(T == void)) {
            void[] buffer;
            buffer.length = T.sizeof;
            memcpy(buffer.ptr, &value, buffer.length);
            result = sqlite3_bind_blob(
                        core.statement,
                        index,
                        cast(void*) buffer.ptr,
                        buffer.length,
                        null
                    );
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
    
    unittest {
        auto db = Database(":memory:");
        auto query = Query(db, "CREATE TABLE test (val INTEGER)");
        query.execute;
        query = Query(db, "INSERT INTO test (val) VALUES (:val)");
        query.bind(":val", 1024);
        query.execute;
        query = Query(db, "SELECT * FROM test");
        assert(!query.rows.empty);
        assert(query.rows.front["val"].to!int == 1024);
        query.rows.popFront();
        assert(query.rows.empty);
    }
    
    unittest {
        auto db = Database(":memory:");
        auto query = Query(db, "CREATE TABLE test (val INTEGER)");
        query.execute;
        assert(db.changes == 0);
        assert(db.totalChanges == 0);
        
        int i = 1;
        query = Query(db, "INSERT INTO test (val) VALUES (:val)");
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
        
        query = Query(db, "SELECT * FROM test");
        auto rows = query.rows;
        foreach (row; rows) {
            assert(row["val"].to!long > 0);
        }
    }
    
    unittest {
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
        foreach (row; rows) {
            assert(row["val"].to!real > 0);
        }
    }
    
    unittest {
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
        foreach (row; rows) {
            assert(row["val"].to!string == 
                "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B"c);
        }
    }
    
    unittest {
        auto db = Database(":memory:");
        auto query = Query(db, "CREATE TABLE test (val BLOB)");
        query.execute;
        
        struct Data {
            int i = 2048;
            char c = '\xFF';
        }
        auto data = [2048, 0xFF];
        
        query = Query(db, "INSERT INTO test (val) VALUES (:val)");
        query.bind(":val", Data());
        query.execute;
        query.reset;
        query.bind(":val", data);
        query.execute;
        
        query = Query(db, "SELECT * FROM test");
        auto rows = query.rows;
        foreach (row; rows) {
            assert(row["val"].to!(immutable(ubyte)[]) ==
                [0, 8, 0, 0, 255, 0, 0, 0]);
        }
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
            final switch(type) {
            case SQLITE_INTEGER:
                row.columns ~= Column(i, name,
                    Variant(sqlite3_column_int64(query.core.statement, i)));
                break;
                
            case SQLITE_FLOAT:
                row.columns ~= Column(i, name,
                    Variant(sqlite3_column_double(query.core.statement, i)));
                break;

            case SQLITE_TEXT:
                auto str = to!string(
                    sqlite3_column_text(query.core.statement, i));
                str.validate;
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
    
    version(unittest) {
        static assert(isInputRange!RowSet);
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
        auto f = filter!((Column c) {
            return c.index == index;
        })(columns);
        if (!f.empty)
            return f.front;
        else
            throw new SqliteException(format("invalid column index: %d",
                index));
    }
    
    /++
    Gets the column from its name.
    Params:
        name = the name of the column in the SELECT statement.
    Throws:
        SqliteException when the name is invalid.
    +/
    Column opIndex(string name) {
        auto f = filter!((Column c) {
            return c.name == name;
        })(columns);
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
    int index;
    string name;
    Variant data;
    
    /++
    Gets the value of the column converted _to type T.
    If the value is NULL, it is replaced by value.
    +/
    @property T to(T, T value)() {
        static assert(isValidSqliteType!T,
            "cannot convert a column value to type " ~ T.stringof);
        
        if (data.hasValue) {
            static if (is(T == bool)) {
                return data.get!long != 0;
            }
            else static if (isIntegral!T) {
                return std.conv.to!T(data.get!long);
            }
            else static if (isSomeChar!T) {
                return std.conv.to!T(data.get!string[0]);
            }
            else static if (isFloatingPoint!T) {
                return std.conv.to!T(data.get!double);
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
    Gets the value of the column converted _to type T.
    Throws:
        SqliteException when a NULL value is converted into a type that cannot
        be null.
    +/
    @property T to(T)() {
        static if (isPointer!T || isDynamicArray!T) {
            if (data.hasValue)
                return to!(T, T.init)();
            else
                return null;
        }
        else {
            if (data.hasValue)
                return to!(T, T.init)();
            else
                throw new SqliteException("cannot set a value of type "
                    ~ T.stringof ~ " to null");                
        }
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
