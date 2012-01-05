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
        single SQL statement and either use Query.execute() if you don't expect
        the query to return rows, or use Query.rows() directly in the other
        case.)
        $(LI If you need parameter binding, create a Query object with a
        single SQL statement that includes binding names, and use Parameter methods
        as many times as necessary to bind all values. Then either use
        Query.execute() if you don't expect the query to return rows, or use
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
---

Copyright:
    Copyright Nicolas Sicard, 2011.

License:
    No license yet.

Author:
    Nicolas Sicard.
    
Macros:
    D = <tt>$0</tt>
    DK = <strong><tt>$0</tt></strong>
+/
module d2sqlite3;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.metastrings;
import std.string;
import std.range;
import std.traits;
import std.typetuple;
import std.utf;
import std.variant;

pragma(lib, "sqlite3");
version (SQLITE_ENABLE_ICU)
{
    pragma(lib, "icui18n");
    pragma(lib, "icuuc");        
}

//debug=SQLITE;
//debug(SQLITE) import std.stdio;
version(unittest)
{
    import std.file;
    import std.math;
    void main() {}
}

/++
Exception thrown when SQLite functions return an error.
+/
class SqliteException : Exception
{
    int code;

    this(int code)
    {
        this.code = code;
        super(format("error %d", code));
    }

    this(string msg, int code = -1)
    {
        this.code = code;
        super(msg);
    }
}


/++
Metadata from the SQLite library.
+/
struct Sqlite3
{
    /++
    Gets the library's version string (e.g. 3.6.12).
    +/
    static @property string versionString()
    {
        return to!string(sqlite3_libversion());
    }

    /++
    Gets the library's version number (e.g. 3006012).
    +/
    static nothrow @property int versionNumber()
    {
        return sqlite3_libversion_number();
    }
    
    unittest
    {
        assert(Sqlite3.versionString[0..2] == "3.");
        assert(Sqlite3.versionNumber > 3003011, "incompatible SQLite version");
    }
}

/++
Tests if T is a convertible to a SQLite type.
+/
template isValidSqlite3Type(T)
{
    enum isValidSqlite3Type =
               isIntegral!T
            || is(Unqual!T == bool)
            || isFloatingPoint!T
            || isSomeChar!T
            || isSomeString!T
            || (isArray!T && is(Unqual!(ElementType!T) == ubyte))
            || is(T == void*);
}
version (unittest)
{
    static assert(isValidSqlite3Type!int);
    static assert(isValidSqlite3Type!uint);
    static assert(isValidSqlite3Type!long);
    static assert(isValidSqlite3Type!ulong);
    static assert(isValidSqlite3Type!short);
    static assert(isValidSqlite3Type!ushort);
    static assert(isValidSqlite3Type!byte);
    static assert(isValidSqlite3Type!ubyte);
    static assert(isValidSqlite3Type!(immutable(int)));
    static assert(isValidSqlite3Type!bool);
    static assert(isValidSqlite3Type!float);
    static assert(isValidSqlite3Type!double);
    static assert(isValidSqlite3Type!real);
    static assert(isValidSqlite3Type!string);
    static assert(isValidSqlite3Type!wstring);
    static assert(isValidSqlite3Type!dstring);
    static assert(isValidSqlite3Type!(char[]));
    static assert(isValidSqlite3Type!(ubyte[]));
    static assert(isValidSqlite3Type!(immutable(ubyte)[]));
    static assert(isValidSqlite3Type!(immutable(ubyte)[4]));
    static assert(isValidSqlite3Type!(typeof(null)));
}

/++
Transaction types.

See $(LINK http://www.sqlite.org/lang_transaction.html)
+/
enum Transaction : string
{
    deferred = "DEFERRED", /// Deferred transaction (the default in SQLite).
    immediate = "IMMEDIATE", /// Transaction with write lock.
    exclusive = "EXCLUSIVE" /// Transaction with read and write lock.
}

/++
Use of a shared cache.

See $(LINK http://www.sqlite.org/sharedcache.html)
+/
enum SharedCache : bool
{
    enabled = true, /// Shared cache is _enabled.
    disabled = false /// Shared cache is _disabled (the default in SQLite).
}

/++
An interface to a SQLite database connection.
+/
struct Database
{
    private struct _core
    {
        sqlite3* handle;
        size_t refcount = 1;
    }
    private _core* core; // shared between copies of this Database object.

    private nothrow void _retain()
    in
    {
        assert(core);
    }
    body
    {
        core.refcount++;
    }

    private void _release()
    in
    {
        assert(core);
    }
    body
    {
        core.refcount--;
        if (core.refcount == 0)
        {
            auto result = sqlite3_close(core.handle);
            enforce(result == SQLITE_OK, new SqliteException(result));
            core = null;        
        }
    }

    /++
    Opens a database connection.
    Params:
        path = the path of the database file. Can be empty or set to
        ":memory:" according to the SQLite specification.
        sharedCache = whether this database connection will use a shared cache.
    Throws:
        SqliteException when the database cannot be opened.
    +/
    this(string path, SharedCache sharedCache = SharedCache.disabled)
    out
    {
        assert(core);
        assert(core.handle);
        assert(core.refcount == 1);
    }
    body
    {
        core = new _core;
        if (sharedCache)
        {
            auto result = sqlite3_enable_shared_cache(1);
            enforce(result == SQLITE_OK, new SqliteException(errorMsg, result));
        }
        auto result = sqlite3_open(cast(char*) path.toStringz, &core.handle);
        enforce(result == SQLITE_OK && core.handle, new SqliteException(errorMsg, result));
    }
    unittest
    {
        auto db = Database(":memory:");
    }
    
    @disable this();

    nothrow this(this)
    {
        _retain();
    }

    ~this()
    {
        _release();
    }

    nothrow void opAssign(Database rhs)
    {
        swap(core, rhs.core);
    }
    
    unittest
    {
        // Tests copy-construction and reference counting.
        Database db1 = Database(":memory:");
        assert(db1.core.refcount == 1);
        {   // new scope
            auto db2 = db1;
            assert(db1.core.refcount == 2);
            assert(db2.core.refcount == 2);            
        }
        assert(db1.core.refcount == 1);
    }

    /++
    Compiles internal statistics to optimize indexing.

    See $(LINK http://www.sqlite.org/lang_analyze.html)
    +/
    void analyze()
    {
        execute("ANALYZE");
    }

    /++
    Attaches a database.

    See $(LINK http://www.sqlite.org/lang_attach.html)

    Params:
        fileName = the file name of the database.
        databaseName = the name with which the database will be referred to.
    +/
    void attach(string fileName, string databaseName)
    {
        enforce(!databaseName.empty, new SqliteException("database name cannot be empty"));
        execute(format(`ATTACH "%s" AS %s`, fileName, databaseName));
    }

    /++
    Begins a transaction.

    See $(LINK http://www.sqlite.org/lang_transaction.html)

    Params:
        type = the _type of the transaction.
    +/
    void begin(Transaction type = Transaction.deferred)
    {
        execute("BEGIN " ~ type);
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted by
    the most recently completed query.
    +/
    nothrow @property int changes()
    in
    {
        assert(core && core.handle);
    }
    body
    {
        return sqlite3_changes(core.handle);
    }

    /++
    Commits all transactions.

    See $(LINK http://www.sqlite.org/lang_transaction.html)
    )
    +/
    void commit()
    {
        execute("COMMIT");
    }
    
    /++
    Creates and registers a new aggregate function in the database.
    
    The type Aggregate must be a $(DK struct) that implements at least these
    two methods: $(D accumulate) and $(D result), and that must be default-constructible.
    
    See also: $(LINK http://www.sqlite.org/lang_aggfunc.html)
    
    Example:
    ---
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
    +/
    void createAggregate(Aggregate, string name = Aggregate.stringof)()
    {
        alias staticMap!(Unqual, ParameterTypeTuple!(Aggregate.accumulate)) PT;
        enum paramcount = PT.length;
        alias ReturnType!(Aggregate.result) RT;
        
        static assert(is(Aggregate == struct), name ~ " shoud be a struct");
        static assert(is(typeof(Aggregate.accumulate) == function), name ~ " shoud define accumulate()");
        static assert(is(typeof(Aggregate.result) == function), name ~ " shoud define result()");

        /+
        Arguments of the functions.
        +/
        static @property string block_read_values(size_t n)()
        {
            static if (n == 0)
                return null;
            else
            {
                enum index = n - 1;
                alias Unqual!(PT[index]) UT;
                static if (is(UT == bool))
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_numeric_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_INTEGER, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be a boolean"));
                        args[` ~ to!string(index) ~ `] = sqlite3_value_int64(argv[` ~ to!string(index) ~ `]) != 0;`;
                else static if (isIntegral!UT)
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_numeric_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_INTEGER, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be of an integral type"));
                        args[` ~ to!string(index) ~ `] = to!(PT[` ~ to!string(index) 
                            ~ `])(sqlite3_value_int64(argv[` ~ to!string(index) ~ `]));`;
                else static if (isFloatingPoint!UT)
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_numeric_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_FLOAT, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be a floating point"));
                        args[` ~ to!string(index) ~ `] = to!(PT[` ~ to!string(index) 
                            ~ `])(sqlite3_value_double(argv[` ~ to!string(index) ~ `]));`;
                else static if (isSomeString!UT)
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_TEXT, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be a string"));
                        args[` ~ to!string(index) ~ `] = to!(PT[` ~ to!string(index) 
                            ~ `])(sqlite3_value_text(argv[` ~ to!string(index) ~ `]));`;
                else static if (isArray!UT && is(Unqual!(ElementType!UT) == ubyte))
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_BLOB, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be of an array of bytes (BLOB)"));
                        n = sqlite3_value_bytes(argv[` ~ to!string(index) ~ `]);
                        blob.length = n;
                        memcpy(blob.ptr, sqlite3_value_blob(argv[` ~ to!string(index) ~ `]), n);
                        args[` ~ to!string(index) ~ `] = to!(PT[` ~ to!string(index) ~ `])(blob.dup);`;
                else
                    static assert(false, PTA[index].stringof ~ " is not a compatible argument type");
            }
        }
        
        static if (staticIndexOf!(ubyte[], PT) >= 0)
            enum blob = "ubyte[] blob;\n";
        else
            enum blob = "";
            
        enum x_step = `
            extern(C) static void ` ~ name ~ `_step(sqlite3_context* context, int argc, sqlite3_value** argv)
            { 
                Aggregate* agg = cast(Aggregate*) sqlite3_aggregate_context(context, Aggregate.sizeof);
                if (!agg)
                {
                    sqlite3_result_error_nomem(context);
                    return;
                }
                
                PT args;
                int type;
                `
                ~ blob
                ~ block_read_values!(paramcount)
                ~ `
                
                try
                {
                    agg.accumulate(args);
                }
                catch (Exception e)
                {
                    auto txt = "error in aggregate function ` ~ name ~ `(): " ~ e.msg;
                    sqlite3_result_error(context, cast(char*) txt.toStringz, -1);
                }
            }`;
        //pragma(msg, x_step);
        mixin(x_step);
        
        /+
        Return type and value of the final function.
        +/
        static if (isIntegral!RT || is(Unqual!RT == bool))
            enum string block_return_result = `
                auto result = to!long(tmp);
                sqlite3_result_int64(context, result);`;
        else static if (isFloatingPoint!RT)
            enum string block_return_result = `
                auto result = to!double(tmp);
                sqlite3_result_double(context, result);`;
        else static if (isSomeString!RT)
            enum string block_return_result = `
                auto result = to!string(tmp);
                if (result)
                    sqlite3_result_text(context, cast(char*) result.toStringz, -1, null);
                else
                    sqlite3_result_null(context);`;
        else static if (isArray!RT && is(Unqual!(ElementType!RT) == ubyte))
            enum string block_return_result = `
                auto result = to!(ubyte[])(tmp);
                if (result)
                    sqlite3_result_blob(context, cast(void*) result.ptr, result.length, null);
                else
                    sqlite3_result_null(context);`;
        else
            static assert(false, RT.stringof ~ " is not a compatible return type");
        
        enum x_final = `
            extern(C) static void ` ~ name ~ `_final(sqlite3_context* context)
            { 
                Aggregate* agg = cast(Aggregate*) sqlite3_aggregate_context(context, Aggregate.sizeof);
                if (!agg)
                {
                    sqlite3_result_error_nomem(context);
                    return;
                }
                
                try
                {
                    auto tmp = agg.result();`
                    ~ block_return_result
                    ~ `
                }
                catch (Exception e)
                {
                    auto txt = "error in aggregate function ` ~ name ~ `(): " ~ e.msg;
                    sqlite3_result_error(context, cast(char*) txt.toStringz, -1);
                }
            }`;
        //pragma(msg, x_final);
        mixin(x_final);
        
        auto result = sqlite3_create_function(core.handle, cast(char*) name.toStringz, paramcount,
            SQLITE_UTF8, null, null, mixin(Format!("&%s_step", name)), mixin(Format!("&%s_final", name)));
        enforce(result == SQLITE_OK, new SqliteException(errorMsg, result));
    }
    unittest
    {
        // Tests aggregate creation.
        struct weighted_average {
            double total_value = 0.0;
            double total_weight = 0.0;

            void accumulate(double value, double weight) {
                total_value += value * weight;
                total_weight += weight;
            }

            double result() {
                return total_value / total_weight;
            }
        }

        auto db = Database(":memory:");
        db.createAggregate!(weighted_average, "w_avg")();

        db.execute("CREATE TABLE test (value FLOAT, weight FLOAT)");

        auto query = db.query("INSERT INTO test (value, weight) VALUES (:v, :w)");
        query.params.bind(":v", 11.5, ":w", 3);
        query.execute();
        query.reset();
        query.params.bind(":v", 14.8, ":w", 1.6);
        query.execute();
        query.reset();
        query.params.bind(":v", 19, ":w", 2.4);
        query.execute();
        query.reset();

        query = db.query("SELECT w_avg(value, weight) FROM test");
        assert(approxEqual(query.rows.front[0].as!double, (11.5*3 + 14.8*1.6 + 19*2.4)/(3 + 1.6 + 2.4)));
    }
    
    /++
    Creates and registers a collation function in the database.
    
    The function $(D_PARAM fun) must satisfy these criteria:
    $(UL
        $(LI It must two string arguments, e.g. s1 and s2.)
        $(LI Its return value $(D ret) must satisfy these criteria (when s3 is any other string):
            $(UL
                $(LI If s1 is less than s2, $(D ret < 0).)
                $(LI If s1 is equal to s2, $(D ret == 0).)
                $(LI If s1 is greater than s2, $(D ret > 0).)
                $(LI If s1 is equal to s2, then s2 is equal to s1.)
                $(LI If s1 is equal to s2 and s2 is equal to s3, then s1 is equal to s3.)
                $(LI If s1 is less than s2, then s2 is greater than s1.)
                $(LI If s1 is less than s2 and s2 is less than s3, then s1 is less than s3.)
            )
        )
    )
    
    The function will have the name $(D_PARAM name) in the database; this name defaults to
    the identifier of the function fun.
    
    See also: $(LINK http://www.sqlite.org/lang_aggfunc.html)

    Example:
    ---
    static int icmp(string s1, string s2)
    {
        return std.string.icmp(s1, s2);
    }

    auto db = Database("my_db.db");
    db.createCollation!icmp();
    db.execute("CREATE TABLE test (val TEXT)");
    ... // Populate the table.
    auto query = db.query("SELECT val FROM test ORDER BY val COLLATE icmp");
    ---
    +/
    void createCollation(alias fun, string name = __traits(identifier, fun))()
    {
        static assert(__traits(isStaticFunction, fun), "symbol " ~ __traits(identifier, fun) ~ " of type " ~ typeof(fun).stringof ~ " is not a static function");
        
        alias ParameterTypeTuple!fun PT;
        static assert(isSomeString!(PT[0]), "the first argument of function " ~ name ~ " should be a string");
        static assert(isSomeString!(PT[1]), "the second argument of function " ~ name ~ " should be a string");
        static assert(isImplicitlyConvertible!(ReturnType!fun, int), "function " ~ name ~ " should return a value convertible to an integer");
        
        enum funpointer = &fun;
        enum x_compare = `extern (C) static int ` ~ name ~ `(void*, int n1, void* str1, int n2, void* str2)
        {
            char[] s1, s2;
            s1.length = n1;
            s2.length = n2;
            memcpy(s1.ptr, str1, n1);
            memcpy(s2.ptr, str2, n2);
            return funpointer(cast(immutable) s1, cast(immutable) s2);
        }`;
        //pragma(msg, x_compare);
        mixin(x_compare);
        
        auto result = sqlite3_create_collation(core.handle, cast(char*) name.toStringz, SQLITE_UTF8, null, mixin(Format!("&%s", name)));
        enforce(result == SQLITE_OK, new SqliteException(errorMsg, result));
    }
    unittest
    {
        static int my_collation(string s1, string s2)
        {
            return std.string.icmp(s1, s2);
        }
        
        auto db = Database(":memory:");
        db.createCollation!my_collation();
        db.execute("CREATE TABLE test (val TEXT)");

        auto query = db.query("INSERT INTO test (val) VALUES (:val)");
        query.params.bind(":val", "A");
        query.execute();
        query.reset();
        query.params.bind(":val", "B");
        query.execute();
        query.reset();
        query.params.bind(":val", "a");
        query.execute();

        query = db.query("SELECT val FROM test ORDER BY val COLLATE my_collation");
        assert(query.rows.front[0].as!string == "A");
        query.rows.popFront();
        assert(query.rows.front[0].as!string == "a");
        query.rows.popFront();
        assert(query.rows.front[0].as!string == "B");
    }
    
    /++
    Creates and registers a simple function in the database.
    
    The function $(D_PARAM fun) must satisfy these criteria:
    $(UL
        $(LI It must not be a variadic.)
        $(LI Its arguments must all have a type that is compatible with SQLite types:
             boolean, integral, floating point, string, or array of bytes (BLOB types).)
        $(LI Its return value must also be of a compatible type.)
    )
    
    The function will have the name $(D_PARAM name) in the database; this name defaults to
    the identifier of the function fun.
    
    See also: $(LINK http://www.sqlite.org/lang_corefunc.html)
    
    Example:
    ---
    import std.string;
    
    static string my_repeat(string s, int i)
    {
        return std.string.repeat(s, i);
    }
    
    auto db = Database("");
    db.createFunction!my_repeat();
    
    auto query = db.query("SELECT my_repeat('*', 8)");
    assert(query.rows.front[0].as!string = "********");
    ---
        +/
    void createFunction(alias fun, string name = __traits(identifier, fun))()
    {
        static if (__traits(isStaticFunction, fun))
            enum funpointer = &fun;
        else
            static assert(false, "symbol " ~ __traits(identifier, fun) ~ " of type " 
                          ~ typeof(fun).stringof ~ " is not a static function");
                          
        static assert(variadicFunctionStyle!(fun) == Variadic.no);

        alias staticMap!(Unqual, ParameterTypeTuple!fun) PT;
        enum paramcount = PT.length;
        alias ReturnType!fun RT;

        /+
        Arguments.
        +/
        static @property string block_read_values(size_t n)()
        {
            static if (n == 0)
                return null;
            else
            {
                enum index = n - 1;
                alias Unqual!(PT[index]) UT;
                static if (is(UT == bool))
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_numeric_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_INTEGER, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be a boolean"));
                        args[` ~ to!string(index) ~ `] = sqlite3_value_int64(argv[` ~ to!string(index) ~ `]) != 0;`;
                else static if (isIntegral!UT)
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_numeric_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_INTEGER, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be of an integral type"));
                        args[` ~ to!string(index) ~ `] = to!(PT[` ~ to!string(index) 
                            ~ `])(sqlite3_value_int64(argv[` ~ to!string(index) ~ `]));`;
                else static if (isFloatingPoint!UT)
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_numeric_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_FLOAT, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be a floating point"));
                        args[` ~ to!string(index) ~ `] = to!(PT[` ~ to!string(index) 
                            ~ `])(sqlite3_value_double(argv[` ~ to!string(index) ~ `]));`;
                else static if (isSomeString!UT)
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_TEXT, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be a string"));
                        args[` ~ to!string(index) ~ `] = to!(PT[` ~ to!string(index) 
                            ~ `])(sqlite3_value_text(argv[` ~ to!string(index) ~ `]));`;
                else static if (isArray!UT && is(Unqual!(ElementType!UT) == ubyte))
                    return block_read_values!(n - 1) ~ `
                        type = sqlite3_value_type(argv[` ~ to!string(index) ~ `]);
                        enforce(type == SQLITE_BLOB, new SqliteException(
                            "argument ` ~ to!string(n) ~ ` of function ` ~ name ~ `() should be of an array of bytes (BLOB)"));
                        n = sqlite3_value_bytes(argv[` ~ to!string(index) ~ `]);
                        blob.length = n;
                        memcpy(blob.ptr, sqlite3_value_blob(argv[` ~ to!string(index) ~ `]), n);
                        args[` ~ to!string(index) ~ `] = to!(PT[` ~ to!string(index) ~ `])(blob.dup);`;
                else
                    static assert(false, PT[index].stringof ~ " is not a compatible argument type");
            }
        }

        /+
        Return type and value.
        +/
        static if (isIntegral!RT || is(Unqual!RT == bool))
            enum string block_return_result = `
                auto result = to!long(tmp);
                sqlite3_result_int64(context, result);`;
        else static if (isFloatingPoint!RT)
            enum string block_return_result = `
                auto result = to!double(tmp);
                sqlite3_result_double(context, result);`;
        else static if (isSomeString!RT)
            enum string block_return_result = `
                auto result = to!string(tmp);
                if (result)
                    sqlite3_result_text(context, cast(char*) result.toStringz, -1, null);
                else
                    sqlite3_result_null(context);`;
        else static if (isArray!RT && is(Unqual!(ElementType!RT) == ubyte))
            enum string block_return_result = `
                auto result = to!(ubyte[])(tmp);
                if (result)
                {
                    enforce(result.length <= int.max, new SqliteException("array too long"));
                    sqlite3_result_blob(context, cast(void*) result.ptr, cast(int) result.length, null);
                }
                else
                    sqlite3_result_null(context);`;
        else
            static assert(false, RT.stringof ~ " is not a compatible return type");

        /+
        The generated function.
        +/
        
        // Detect the need of a blob variable
        static if (staticIndexOf!(ubyte[], PT) >= 0)
            enum blob = "ubyte[] blob;\n";
        else
            enum blob = "";

        enum x_func = `
            extern(C) static void ` ~ name ~ `(sqlite3_context* context, int argc, sqlite3_value** argv)
            { 
                PT args;
                int type, n;
                `
                ~ blob
                ~ block_read_values!(paramcount)
                ~ `
                try
                {
                    auto tmp = funpointer(args);
                `
                ~ block_return_result
                ~ `
                }
                catch (Exception e)
                {
                    auto txt = "error in function ` ~ name ~ `(): " ~ e.msg;
                    sqlite3_result_error(context, cast(char*) txt.toStringz, -1);
                }
            }
        `;
        //pragma(msg, x_func);
        mixin(x_func);

        auto result = sqlite3_create_function(core.handle, cast(char*) name.toStringz, paramcount,
            SQLITE_UTF8, null, mixin(Format!("&%s", name)), null, null);
        enforce(result == SQLITE_OK, new SqliteException(errorMsg, result));
    }
    unittest
    {
        // Tests function creation.
        static string test_args(bool b, int i, double d, string s, ubyte[] a)
        {
            if (b && i == 42 && d == 4.2 && s == "42" && a == [0x04, 0x02])
                return "OK";
            else
                return "NOT OK";
        }
        static bool test_bool()
        {
            return true;
        }
        static int test_int()
        {
            return 42;
        }
        static double test_double()
        {
            return 4.2;
        }
        static string test_string()
        {
            return "42";
        }
        static immutable(ubyte)[] test_ubyte()
        {
            return [0x04, 0x02];
        }

        auto db = Database(":memory:");
        db.createFunction!test_args();
        db.createFunction!test_bool();
        db.createFunction!test_int();
        db.createFunction!test_double();
        db.createFunction!test_string();
        db.createFunction!test_ubyte();
        auto query = db.query("SELECT test_args(test_bool(), test_int(), test_double(), test_string(), test_ubyte())");
        assert(query.rows.front[0].as!string == "OK");
    }

    /++
    Detaches a database.

    See $(LINK http://www.sqlite.org/lang_detach.html)

    Params:
        databaseName = the name of the database to detach.
    +/
    void detach(string databaseName)
    {
        execute("DETACH " ~ databaseName);
    }

    /++
    Gets the SQLite error code of the last operation.
    +/
    nothrow @property int errorCode()
    in
    {
        assert(core && core.handle);
    }
    body
    {
        return sqlite3_errcode(core.handle);
    }
    unittest
    {
        auto db = Database(":memory:");
        assert(db.errorCode == SQLITE_OK);
    }

    /++
    Gets the SQLite error message of the last operation.
    +/
    @property string errorMsg()
    in
    {
        assert(core && core.handle);
    }
    body
    {
        return to!string(sqlite3_errmsg(core.handle));
    }
    unittest
    {
        auto db = Database(":memory:");
        assert(db.errorMsg == "not an error");
    }

    /++
    Execute one or many SQL statements. Rows returned by any of these statements
    are ignored.
    Throws:
        SqliteException in one of the SQL statements cannot be executed.
    +/
    void execute(string sql)
    in
    {
        assert(core && core.handle);
    }
    body
    {
        char* errmsg;
        sqlite3_exec(core.handle, cast(char*) sql.toStringz, null, null, &errmsg);
        if (errmsg !is null)
        {
            auto msg = to!string(errmsg);
            sqlite3_free(errmsg);
            throw new SqliteException(msg);
        }
    }
    unittest
    {
        // Tests empty statements
        auto db = Database(":memory:");
        db.execute(";");
    }
    unittest
    {
        // Tests multiple statements in query string
        auto db = Database(":memory:");
        try
            db.execute("CREATE TABLE test (val INTEGER);CREATE TABLE test (val INTEGER)");
        catch (SqliteException e)
            assert(e.msg.canFind("test"));
    }
    
    /++
    Gets the SQLite internal _handle of the database connection.
    +/
    nothrow @property sqlite3* handle()
    in
    {
        assert(core && core.handle);
    }
    body
    {
        return core.handle;
    }

    /++
    Creates a _query on the database and returns it.
    Params:
        sql = the SQL code of the _query.
    +/
    Query query(string sql)
    {
        return Query(&this, sql);
    }

    /++
    Releases a transaction save point.

    See $(LINK http://www.sqlite.org/lang_savepoint.html)
    +/
    void release(string savepoint)
    {
        execute("RELEASE " ~ savepoint);
    }

    /++
    Rolls back to the given save point or rolls back all transaction if
    savepoint is null.

    See $(LINK http://www.sqlite.org/lang_savepoint.html)

    Params:
        savepoint = the name of the save point.
    +/
    void rollback(string savepoint = null)
    {
        if (savepoint)
            execute("ROLLBACK TO " ~ savepoint);
        else
            execute("ROLLBACK");
    }

    /++
    Creates a transaction save point.

    See $(LINK http://www.sqlite.org/lang_savepoint.html)
    +/
    void savepoint(string name)
    {
        execute("SAVEPOINT " ~ name);
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted
    since the database was opened.
    +/
    nothrow @property int totalChanges()
    in
    {
        assert(core && core.handle);
    }
    body
    {
        return sqlite3_total_changes(core.handle);
    }

    /++
    Optimizes the size of the database file.

    See $(LINK http://www.sqlite.org/lang_vacuum.html)
    +/
    void vacuum()
    {
        execute("VACUUM");
    }
    
    unittest
    {
        // Tests miscellaneous functionalities.
        auto db = Database(":memory:");
        db.attach("test.db", "other_db");
        db.detach("other_db");
        assert(std.file.exists("test.db"));
        std.file.remove("test.db");

        db.begin();
            db.execute("CREATE TABLE test (dummy BLOB)");
            assert(db.changes == 0);
            assert(db.totalChanges == 0);
        db.rollback();

        db.begin();
            db.execute("CREATE TABLE test (val INTEGER)");
            assert(db.changes == 0);
            assert(db.totalChanges == 0);
        db.savepoint("aftercreation");
            db.execute("INSERT INTO test (val) VALUES (42)");
            assert(db.changes == 1);
            assert(db.totalChanges == 1);
        db.rollback("aftercreation");
        db.release("aftercreation");
            db.execute("INSERT INTO test (val) VALUES (84)");
            assert(db.changes == 1);
            //assert(db.totalChanges == 1); // == 2 !!
        db.commit();

        db.vacuum();
        db.analyze();

        auto query = db.query("SELECT COUNT(*) FROM test");
        assert(query.rows.front[0].as!int == 1);
    }
}

/++
An interface to SQLite query execution.
+/
static struct Query
{
    private struct _core
    {
        Database* db;
        string sql;
        sqlite3_stmt* statement;
        uint refcount;
        Parameters params = void;
        RowSet rows = void;
        
        this(Database* db, string sql, sqlite3_stmt* statement, Parameters params, RowSet rows)
        {
            this.db = db;
            this.sql = sql;
            this.statement = statement;
            this.refcount = 1;
            this.params = params;
            this.rows = rows;
        }
    }
    private _core* core;

    @disable this();

    private this(Database* db, string sql)
    in
    {
        assert(db);
        assert(db.core);
        assert(db.core.handle);
    }
    out
    {
        assert(core);
        // core.statement can be null is sql contains an empty statement
        assert(core.refcount == 1);
    }
    body
    {
        enforce(sql.length <= int.max, new SqliteException("string too long"));
        db._retain();
        sqlite3_stmt* statement;       
        auto result = sqlite3_prepare_v2(
            db.core.handle,
            cast(char*) sql.toStringz,
            cast(int) sql.length,
            &statement,
            null
        );
        enforce(result == SQLITE_OK, new SqliteException(db.errorMsg, result));
        core = new _core(db, sql, statement, Parameters(statement), RowSet(&this));
    }

    nothrow this(this)
    {
        _retain();
    }

    ~this()
    {
        _release();
    }

    private nothrow void _retain()
    {
        core.refcount++;
    }

    private void _release()
    {
        core.refcount--;
        assert(core.refcount >= 0);
        if (core.refcount == 0)
        {
            if (core.statement)
            {
                auto result = sqlite3_finalize(core.statement);
                enforce(result == SQLITE_OK, new SqliteException(result));
            }
            if (core.db)
                core.db._release();
            core = null;
        }
    }
    
    nothrow void opAssign(Query rhs)
    {
        swap(core, rhs.core);
    }
    
    unittest
    {
        // Test copy-construction and reference counting.
        Database db = Database(":memory:");
        auto q1 = db.query("SELECT 42");
        assert(q1.statement);
        {
            assert(q1.core.refcount == 1);
            auto q2 = q1;
            assert(q1.core.refcount == 2);
            assert(q2.core.refcount == 2);
        }
        assert(q1.core.refcount == 1);
    }

    /++
    Gets the bindable parameters of the query.
    Returns:
        A Parameters object. Becomes invalid when the Query goes out of scope.
    +/
    nothrow @property ref Parameters params()
    in
    {
        assert(core);        
    }
    body
    {
        return core.params;
    }

    /++
    Resets a query.
    Throws:
        SqliteException when the query could not be reset.
    +/
    void reset()
    in
    {
        assert(core);        
    }
    body
    {
        if (core.statement)
        {
            auto result = sqlite3_reset(core.statement);
            enforce(result == SQLITE_OK, new SqliteException(core.db.errorMsg, result));
            core.rows = RowSet(&this);
        }
    }

    /++
    Gets the results of a query that returns _rows.
    Returns:
        A RowSet object that can be used as an InputRange. Becomes invalid
        when the Query goes out of scope.
    +/
    @property ref RowSet rows()
    in
    {
        assert(core);        
    }
    body
    {
        if (!core.rows.isInitialized)
        {
            core.rows = RowSet(&this);
            core.rows.initialize();
        }
        return core.rows;
    }
    unittest
    {
        // Tests empty statements
        auto db = Database(":memory:");
        db.execute(";");
        auto query = db.query("-- This is a comment !");
        assert(query.rows.empty);
        
        // TODO: Move these next to their definition:
        assert(query.params.length == 0);
        query.params.clear();
        query.reset();
    }
    unittest
    {
        // Tests Query.rows()
        static assert(isInputRange!RowSet);
        auto db = Database(":memory:");
        db.execute("CREATE TABLE test (val INTEGER)");

        auto query = db.query("INSERT INTO test (val) VALUES (:val)");
        query.params.bind(":val", 42);
        query.execute();
        assert(query.rows.empty);
        query = db.query("SELECT * FROM test");
        assert(!query.rows.empty);
        assert(query.rows.front[0].as!int == 42);
        query.rows.popFront();
        assert(query.rows.empty);
    }

    /++
    Executes the query.
    Use rows() directly if the query is expected to return rows.
    +/
    void execute()
    {
        rows();
    }

    /++
    Gets the SQLite internal handle of the query statement.
    +/
    nothrow @property sqlite3_stmt* statement()
    in
    {
        assert(core);        
    }
    body
    {
        return core.statement;
    }
}

/++
The bound parameters of a query.
+/
struct Parameters
{
    private sqlite3_stmt* statement;
    
    private nothrow this(sqlite3_stmt* statement)
    {
        this.statement = statement;
    }
    
    @disable this();

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
    void bind(T...)(T args)
    {
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
    unittest
    {
        // Tests simple bindings
        auto db = Database(":memory:");
        db.execute("CREATE TABLE test (val INTEGER)");

        auto query = db.query("INSERT INTO test (val) VALUES (:val)");
        query.params.bind(":val", 42);
        query.execute();
        query.reset();
        query.params.bind(1, 42);
        query.execute();
        query.reset();
        query.params.bind(1, 42);
        query.execute();
        query.reset();
        query.params.bind(":val", 42);
        query.execute();

        query = db.query("SELECT * FROM test");
        foreach (row; query.rows)
            assert(row[0].as!int == 42);
    }
    unittest
    {
        // Tests multiple bindings
        auto db = Database(":memory:");
        db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
        auto query = db.query("INSERT INTO test (i, f, t) VALUES (:i, :f, :t)");
        assert(query.params.length == 3);
        query.params.bind(":t", "TEXT", ":i", 42, ":f", 3.14);
        query.execute();
        query.reset();
        query.params.bind(3, "TEXT", 1, 42, 2, 3.14);
        query.execute();

        query = db.query("SELECT * FROM test");
        foreach (row; query.rows)
        {
            assert(row.columnCount == 3);
            assert(row["i"].as!int == 42);
            assert(row["f"].as!double == 3.14);
            assert(row["t"].as!string == "TEXT");
        }
    }

    /++
    Binds $(D_PARAM value) at the given $(D_PARAM index) or to the parameter
    named $(D_PARAM name).
    Throws:
        SqliteException when parameter refers to an invalid binding or when
        the value cannot be bound.
    Bugs:
        Does not work with Query.params due to DMD issue #5202
    +/
    void opIndexAssign(T)(T value, size_t i)
    {
        static assert(isValidSqlite3Type!T, T.stringof ~ " is not a valid value type");
        
        enforce(i <= int.max, new SqliteException("index too long"));
        enforce(length > 0, new SqliteException("no parameter in prepared statement"));
        
        alias Unqual!T U;
        auto index = cast(int) i;
        int result;

        static if (is(U == typeof(null)))
            result = sqlite3_bind_null(statement, index);
        else static if (isImplicitlyConvertible!(U, long))
            result = sqlite3_bind_int64(statement, index, cast(long) value);
        else static if (isImplicitlyConvertible!(U, double))
            result = sqlite3_bind_double(statement, index, value);
        else static if (isSomeString!U)
        {
            string utf8 = value.toUTF8;
            enforce(utf8.length <= int.max, new SqliteException("string too long"));
            result = sqlite3_bind_text(statement, index, cast(char*) utf8.toStringz, cast(int) utf8.length, null);
        }
        else static if (is(U == void*))
            result = sqlite3_bind_null(statement, index);
        else static if (isArray!U && is(Unqual!(ElementType!U) == ubyte))
        {
            ubyte[] buffer = cast(ubyte[]) value;
            enforce(buffer.length <= int.max, new SqliteException("array too long"));
            result = sqlite3_bind_blob(statement, index, cast(void*) buffer.ptr, cast(int) buffer.length, null);
        }
        else
            static assert(false, "cannot bind a value of type " ~ U.stringof);

        enforce(result == SQLITE_OK, new SqliteException(result));
    }

    /// ditto
    void opIndexAssign(T)(T value, string name)
    {
        enforce(length > 0, new SqliteException("no parameter in prepared statement"));
        auto index = sqlite3_bind_parameter_index(statement, cast(char*) name.toStringz);
        enforce(index > 0, new SqliteException(format("parameter named '%s' cannot be bound", name)));
        opIndexAssign(value, index);
    }
    unittest
    {
        // Tests simple bindings with associative array syntax
        auto db = Database(":memory:");
        db.execute("CREATE TABLE test (val INTEGER)");

        auto query = db.query("INSERT INTO test (val) VALUES (:val)");
        version (none) // @@@ BUG5202 @@@: doesn't compile.
        {
            query.params[":val"] == 42;
        }
        query.params.opIndexAssign(42, ":val"); // this works !
        query.execute();

        query = db.query("SELECT * FROM test");
        foreach (row; query.rows) {
            assert(row[0].as!int == 42);
        }
    }

    /++
    Gets the number of parameters.
    +/
    nothrow @property int length()
    {
        if (statement)
            return sqlite3_bind_parameter_count(statement);
        else 
            return 0;
    }

    /++
    Clears the bindings.
    +/
    void clear()
    {
        if (statement)
        {
            auto result = sqlite3_clear_bindings(statement);
            enforce(result == SQLITE_OK, new SqliteException(result));
        }
    }
}

/++
The results of a query that returns rows, with an InputRange interface.
+/
struct RowSet
{
    private Query* query;
    private int sqliteResult = SQLITE_DONE;
    private bool isInitialized = false;

    private this(Query* query)
    in
    {
        assert(query);
    }
    body
    {
        this.query = query;
    }
    
    @disable this();

    private void initialize()
    in
    {
        assert(query);
    }
    body
    {
        if (query.statement)
        {
            // Try to fetch first row
            sqliteResult = sqlite3_step(query.statement);
            if (sqliteResult != SQLITE_ROW && sqliteResult != SQLITE_DONE)
            {
                query.reset(); // necessary to retrieve the error message.
                throw new SqliteException(query.core.db.errorMsg, sqliteResult);
            }
        }
        else
            sqliteResult = SQLITE_DONE; // No statement, so RowSet is empty;
        isInitialized = true;
    }

    /++
    Tests whether no more rows are available.
    +/
    nothrow @property bool empty()
    in
    {
        assert(query);
        assert(isInitialized);
    }
    body
    {
        return sqliteResult == SQLITE_DONE;
    }

    /++
    Gets the current row.
    +/
    @property Row front()
    {
        if (!empty)
        {
            Row row;
            auto colcount = sqlite3_column_count(query.statement);
            row.columns.reserve(colcount);
            foreach (i; 0 .. colcount)
            {
                /*
                    TODO The name obtained from sqlite3_column_name is that of
                    the query text. We should test first for the real name with
                    sqlite3_column_database_name or sqlite3_column_table_name.
                */
                auto name = to!string(sqlite3_column_name(query.statement, i));
                auto type = sqlite3_column_type(query.statement, i);
                final switch (type) {
                case SQLITE_INTEGER:
                    row.columns ~= Column(i, name, Variant(sqlite3_column_int64(query.statement, i)));
                    break;

                case SQLITE_FLOAT:
                    row.columns ~= Column(i, name, Variant(sqlite3_column_double(query.statement, i)));
                    break;

                case SQLITE_TEXT:
                    auto str = to!string(sqlite3_column_text(query.statement, i));
                    row.columns ~= Column(i, name, Variant(str));
                    break;

                case SQLITE_BLOB:
                    auto ptr = sqlite3_column_blob(query.statement, i);
                    auto length = sqlite3_column_bytes(query.statement, i);
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
        else
            throw new SqliteException("no row available");
    }

    /++
    Jumps to the next row.
    +/
    void popFront()
    {
        if (!empty)
            sqliteResult = sqlite3_step(query.statement);
        else
            throw new SqliteException("no row available");
    }
}

/++
A SQLite row.
+/
struct Row
{
    private Column[] columns;

    /++
    Gets the number of columns in this row.
    +/
    nothrow @property size_t columnCount()
    {
        return columns.length;
    }

    /++
    Gets the column at the given index.
    Params:
        index = the index of the column in the SELECT statement.
    Throws:
        SqliteException when the index is invalid.
    +/
    Column opIndex(size_t index)
    {
        enforce(index >= 0 && index < columns.length,
                new SqliteException(format("invalid column index: %d", index)));
        return columns[index];
    }

    /++
    Gets the column from its name.
    Params:
        name = the name of the column in the SELECT statement.
    Throws:
        SqliteException when the name is invalid.
    +/
    Column opIndex(string name)
    {
        auto f = filter!((Column c) { return c.name == name; })(columns);
        if (!f.empty)
            return f.front;
        else
            throw new SqliteException("invalid column name: " ~ name);
    }

    /++
    Gets the column from its name.    
    +/
    @property Column opDispatch(string name)()
    {
        return opIndex(name);
    }
}

/++
A SQLite column.
+/
struct Column
{
    size_t index;
    string name;
    private Variant data;

    /++
    Gets the value of the column converted _to type T.
    If the value is NULL, it is replaced by value.
    +/
    @property T as(T, T value = T.init)()
    {
        alias Unqual!T U;
        if (data.hasValue)
        {
            static if (is(U == bool))
                return cast(T) data.coerce!long() != 0;
            else static if (isIntegral!U)
                return cast(T) std.conv.to!U(data.coerce!long());
            else static if (isFloatingPoint!U)
                return cast(T) std.conv.to!U(data.coerce!double());
            else static if (isSomeString!U)
                return cast(T) std.conv.to!U(data.coerce!string());
            else static if (isArray!U && is(Unqual!(ElementType!U) == ubyte))
                return cast(T) data.get!(ubyte[]);
            else
                static assert(false, "value cannot be converted to type " ~ T.stringof);
        }
        else
            return value;
    }

    alias as!string toString;
}

unittest
{
    // Tests Column
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", 42);
    query.execute();

    query = db.query("SELECT val FROM test");
    with (query.rows)
    {
        assert(front[0].as!int == 42);
        assert(front["val"].as!int == 42);
        assert(front.val.as!int == 42);
    }
}

/++
Unit tests.
+/
unittest
{
    // Tests NULL values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", null);
    query.execute();

    query = db.query("SELECT * FROM test");
    assert(query.rows.front["val"].as!(int, -42) == -42);
}

unittest
{
    // Tests INTEGER values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", 2);
    query.params.clear(); // Resets binding to NULL.
    query.execute();
    query.reset();
    query.params.bind(":val", 42L);
    query.execute();
    query.reset();
    query.params.bind(":val", 42U);
    query.execute();
    query.reset();
    query.params.bind(":val", 42UL);
    query.execute();
    query.reset();
    query.params.bind(":val", true);
    query.execute();
    query.reset();
    query.params.bind(":val", '\x2A');
    query.execute();
    query.reset();
    query.params.bind(":val", null);
    query.execute();

    query = db.query("SELECT * FROM test");
    foreach (row; query.rows)
        assert(row["val"].as!(long, 42) == 42 || row["val"].as!long == 1);
}

unittest
{
    // Tests FLOAT values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val FLOAT)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", 42.0F);
    query.execute();
    query.reset();
    query.params.bind(":val", 42.0);
    query.execute();
    query.reset();
    query.params.bind(":val", 42.0L);
    query.execute();
    query.reset();
    query.params.bind(":val", null);
    query.execute();

    query = db.query("SELECT * FROM test");
    foreach (row; query.rows)
        assert(row["val"].as!(real, 42.0) == 42.0);
}

unittest
{
    // Tetsts plain TEXT values
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val TEXT)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", "I am a text.");
    query.execute(); 
    
    query = db.query("SELECT * FROM test");
    assert(query.rows.front["val"].as!string == "I am a text.");
}

version(SQLITE_ENABLE_ICU) unittest
{
    // Tests TEXT values with ICU
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val TEXT)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.params.bind(":val", "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B");
    query.execute();
    query.reset();
    query.params.bind(":val", "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B");
    query.execute();
    query.reset();
    query.params.bind(":val", "\uC720\uB2C8\uCF5B"w);
    query.execute();
    query.reset();
    query.params.bind(":val", "\uC720\uB2C8\uCF5B"d);
    query.execute();
    query.reset();
    query.params.bind(":val", null);
    query.execute();
    string ns;
    query.reset();
    query.params.bind(":val", ns);
    query.execute();

    query = db.query("SELECT * FROM test");
    foreach (row; query.rows)
        assert(row["val"].as!(string, "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B") ==  "\xEC\x9C\xA0\xEB\x8B\x88\xEC\xBD\x9B");
}

unittest
{
    // Tests BLOB values with arrays
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val BLOB)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    ubyte[] array = [1, 2, 3, 4];
    query.params.bind(":val", array);
    query.execute();

    query = db.query("SELECT * FROM test");
    assert(query.rows.front["val"].as!(ubyte[]) == [1, 2, 3, 4]);
}


/+
SQLite C API
+/
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

extern(C) nothrow
{
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
}