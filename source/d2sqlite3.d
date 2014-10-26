// Written in the D programming language
/++
Simple SQLite interface.

This module provides a simple "object-oriented" interface to the SQLite
database engine.

Objects in this interface (Database and Query) automatically create the SQLite
objects they need. They are reference-counted, so that when their last
reference goes out of scope, the underlying SQLite objects are automatically
closed and finalized. They are not thread-safe.

See example in the documentation for the Database struct below.

The C API is available through $(D etc.c.sqlite3).

Copyright:
    Copyright Nicolas Sicard, 2011-2014.

License:
    $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

Authors:
    Nicolas Sicard (dransic@gmail.com).

Macros:
    D = <tt>$0</tt>
    DK = <strong><tt>$0</tt></strong>
+/
module d2sqlite3;

import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.traits;
import std.typecons;
import std.variant;
public import etc.c.sqlite3;


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
    static @property int versionNumber()
    {
        return sqlite3_libversion_number();
    }
}


deprecated enum SharedCache : bool
{
    enabled = true, /// Shared cache is _enabled.
    disabled = false /// Shared cache is _disabled (the default in SQLite).
}


/++
An interface to a SQLite database connection.
+/
struct Database
{
private:
    struct _Core
    {
        sqlite3* handle;
        
        this(sqlite3* handle)
        {
            this.handle = handle;
        }
        
        ~this()
        {
            if (handle)
            {
                auto result = sqlite3_close(handle);
                enforce(result == SQLITE_OK, new SqliteException(result));
            }
            handle = null;
        }

        @disable this(this);
        void opAssign(_Core) { assert(false); }
    }
    
    alias RefCounted!_Core Core;
    Core core;

public:
    /++
    Opens a database connection.

    The database is open using the sqlite3_open_v2 function.
    See $(LINK http://www.sqlite.org/c3ref/open.html) to know how to use the flags
    parameter or to use path as a file URI if the current configuration allows it.
    +/
    this(string path, int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
    {
        sqlite3* hdl;
        auto result = sqlite3_open_v2(cast(char*) path.toStringz, &hdl, flags, null);
        core = Core(hdl);
        enforce(result == SQLITE_OK && core.handle, new SqliteException(errorMsg, result));
    }

    deprecated("Use the other constructor and set the flags to use shared cache")
    this(string path, SharedCache sharedCache)
    {
        if (sharedCache)
        {
            auto result = sqlite3_enable_shared_cache(1);
            enforce(result == SQLITE_OK, new SqliteException(errorMsg, result));
        }
        sqlite3* hdl;
        auto result = sqlite3_open(cast(char*) path.toStringz(), &hdl);
        core = Core(hdl);
        enforce(result == SQLITE_OK && core.handle, new SqliteException(errorMsg, result));
    }

    /++
    Gets the SQLite internal _handle of the database connection.
    +/
    @property sqlite3* handle()
    {
        return core.handle;
    }
    
    /++
    Explicitly closes the database.

    Throws an SqliteException if the database cannot be closed.

    After this function has been called successfully, using this databse object
    or a query depending on it is a programming error.
    +/
    void close()
    {
        auto result = sqlite3_close(handle);
        enforce(result == SQLITE_OK, new SqliteException(result));
        core.handle = null;
    }

    /++
    Execute the given SQL code.

    Rows returned by any statements are ignored.
    +/
    void execute(string sql)
    {
        char* errmsg;
        assert(core.handle);
        sqlite3_exec(core.handle, cast(char*) sql.toStringz(), null, null, &errmsg);
        if (errmsg !is null)
        {
            auto msg = to!string(errmsg);
            sqlite3_free(errmsg);
            throw new SqliteException(msg, sql);
        }
    }
    
    /++
    Creates a _query on the database and returns it.
    +/
    Query query(string sql)
    {
        return Query(this, sql);
    }
    
    /++
    Gets the number of database rows that were changed, inserted or deleted by
    the most recently completed query.
    +/
    @property int changes()
    {
        assert(core.handle);
        return sqlite3_changes(core.handle);
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted
    since the database was opened.
    +/
    @property int totalChanges()
    {
        assert(core.handle);
        return sqlite3_total_changes(core.handle);
    }

    /++
    Gets the SQLite error code of the last operation.
    +/
    @property int errorCode()
    {
        return core.handle ? sqlite3_errcode(core.handle) : 0;
    }
    
    /++
    Gets the SQLite error message of the last operation.
    +/
    @property string errorMsg()
    {
        return core.handle ? sqlite3_errmsg(core.handle).to!string : "Database is not open";
    }

    /+
    Helper function to translate the arguments values of a D function
    into Sqlite values.
    +/
    private static @property string block_read_values(size_t n, string name, PT...)()
    {
        static if (n == 0)
            return null;
        else
        {
            enum index = n - 1;
            alias Unqual!(PT[index]) UT;
            static if (isBoolean!UT)
                enum templ = q{
                    @{previous_block}
                    type = sqlite3_value_numeric_type(argv[@{index}]);
                    enforce(type == SQLITE_INTEGER, new SqliteException(
                        "argument @{n} of function @{name}() should be a boolean"));
                    args[@{index}] = sqlite3_value_int64(argv[@{index}]) != 0;
                };
            else static if (isIntegral!UT)
                enum templ = q{
                    @{previous_block}
                    type = sqlite3_value_numeric_type(argv[@{index}]);
                    enforce(type == SQLITE_INTEGER, new SqliteException(
                        "argument @{n} of function @{name}() should be of an integral type"));
                    args[@{index}] = to!(PT[@{index}])(sqlite3_value_int64(argv[@{index}]));
                };
            else static if (isFloatingPoint!UT)
                enum templ = q{
                    @{previous_block}
                    type = sqlite3_value_numeric_type(argv[@{index}]);
                    enforce(type == SQLITE_FLOAT, new SqliteException(
                        "argument @{n} of function @{name}() should be a floating point"));
                    args[@{index}] = to!(PT[@{index}])(sqlite3_value_double(argv[@{index}]));
                };
            else static if (isSomeString!UT)
                enum templ = q{
                    @{previous_block}
                    type = sqlite3_value_type(argv[@{index}]);
                    enforce(type == SQLITE3_TEXT, new SqliteException(
                        "argument @{n} of function @{name}() should be a string"));
                    args[@{index}] = to!(PT[@{index}])(sqlite3_value_text(argv[@{index}]));
                };
            else static if (isArray!UT && is(Unqual!(ElementType!UT) : ubyte))
                enum templ = q{
                    @{previous_block}
                    type = sqlite3_value_type(argv[@{index}]);
                    enforce(type == SQLITE_BLOB, new SqliteException(
                        "argument @{n} of function @{name}() should be of an array of bytes (BLOB)"));
                    n = sqlite3_value_bytes(argv[@{index}]);
                    blob.length = n;
                    import std.c.string : memcpy;
                    memcpy(blob.ptr, sqlite3_value_blob(argv[@{index}]), n);
                    args[@{index}] = to!(PT[@{index}])(blob.dup);
                };
            else
                static assert(false, PT[index].stringof ~ " is not a compatible argument type");

            return render(templ, [
                "previous_block": block_read_values!(n - 1, name, PT),
                "index":  to!string(index),
                "n": to!string(n),
                "name": name
            ]);
        }
    }

    /+
    Helper function to translate the return of a function into a Sqlite value.
    +/
    private static @property string block_return_result(RT...)()
    {
        static if (isIntegral!RT || isBoolean!RT)
            return q{
                auto result = to!long(tmp);
                sqlite3_result_int64(context, result);
            };
        else static if (isFloatingPoint!RT)
            return q{
                auto result = to!double(tmp);
                sqlite3_result_double(context, result);
            };
        else static if (isSomeString!RT)
            return q{
                auto result = to!string(tmp);
                if (result)
                    sqlite3_result_text(context, cast(char*) result.toStringz(), -1, null);
                else
                    sqlite3_result_null(context);
            };
        else static if (isArray!RT && is(Unqual!(ElementType!RT) == ubyte))
            return q{
                auto result = to!(ubyte[])(tmp);
                if (result)
                    sqlite3_result_blob(context, cast(void*) result.ptr, cast(int) result.length, null);
                else
                    sqlite3_result_null(context);
            };
        else
            static assert(false, RT.stringof ~ " is not a compatible return type");
    }

    /++
    Creates and registers a new aggregate function in the database.

    The type Aggregate must be a $(DK struct) that implements at least these
    two methods: $(D accumulate) and $(D result), and that must be default-constructible.

    See also: $(LINK http://www.sqlite.org/lang_aggfunc.html)
    +/
    void createAggregate(Aggregate, string name = Aggregate.stringof)()
    {
        import std.typetuple;

        static assert(is(Aggregate == struct), name ~ " shoud be a struct");
        static assert(is(typeof(Aggregate.accumulate) == function), name ~ " shoud define accumulate()");
        static assert(is(typeof(Aggregate.result) == function), name ~ " shoud define result()");

        alias staticMap!(Unqual, ParameterTypeTuple!(Aggregate.accumulate)) PT;
        alias ReturnType!(Aggregate.result) RT;

        enum x_step = q{
            extern(C) static void @{name}_step(sqlite3_context* context, int argc, sqlite3_value** argv)
            {
                Aggregate* agg = cast(Aggregate*) sqlite3_aggregate_context(context, Aggregate.sizeof);
                if (!agg)
                {
                    sqlite3_result_error_nomem(context);
                    return;
                }

                PT args;
                int type;
                @{blob}

                @{block_read_values}

                try
                {
                    agg.accumulate(args);
                }
                catch (Exception e)
                {
                    auto txt = "error in aggregate function @{name}(): " ~ e.msg;
                    sqlite3_result_error(context, cast(char*) txt.toStringz(), -1);
                }
            }
        };
        enum x_step_mix = render(x_step, [
            "name": name,
            "blob": staticIndexOf!(ubyte[], PT) >= 0 ? q{ubyte[] blob;} : "",
            "block_read_values": block_read_values!(PT.length, name, PT)
        ]);

        mixin(x_step_mix);

        enum x_final = q{
            extern(C) static void @{name}_final(sqlite3_context* context)
            {
                Aggregate* agg = cast(Aggregate*) sqlite3_aggregate_context(context, Aggregate.sizeof);
                if (!agg)
                {
                    sqlite3_result_error_nomem(context);
                    return;
                }

                try
                {
                    auto tmp = agg.result();
                    mixin(block_return_result!RT);
                }
                catch (Exception e)
                {
                    auto txt = "error in aggregate function @{name}(): " ~ e.msg;
                    sqlite3_result_error(context, cast(char*) txt.toStringz(), -1);
                }
            }
        };
        enum x_final_mix = render(x_final, [
            "name": name
        ]);

        mixin(x_final_mix);

        assert(core.handle);
        auto result = sqlite3_create_function(
            core.handle,
            name.toStringz(),
            PT.length,
            SQLITE_UTF8,
            null,
            null,
            mixin(format("&%s_step", name)),
            mixin(format("&%s_final", name))
        );
        enforce(result == SQLITE_OK, new SqliteException(errorMsg, result));
    }
    ///
    unittest // Aggregate creation
    {
        struct weighted_average
        {
            double total_value = 0.0;
            double total_weight = 0.0;

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

        auto db = Database(":memory:");
        db.execute("CREATE TABLE test (value FLOAT, weight FLOAT)");
        db.createAggregate!(weighted_average, "w_avg")();

        auto query = db.query("INSERT INTO test (value, weight) VALUES (:v, :w)");
        double[double] list = [11.5: 3, 14.8: 1.6, 19: 2.4];
        foreach (value, weight; list) {
            query.bind(":v", value);
            query.bind(":w", weight);
            query.execute();
            query.reset();
        }

        query = db.query("SELECT w_avg(value, weight) FROM test");
        import std.math: approxEqual;        
        assert(approxEqual(query.oneValue!double, (11.5*3 + 14.8*1.6 + 19*2.4)/(3 + 1.6 + 2.4)));
    }

    /++
    Creates and registers a collation function in the database.

    The function $(D_PARAM fun) must satisfy these criteria:
    $(UL
        $(LI It must take two string arguments, e.g. s1 and s2.)
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
    +/
    void createCollation(alias fun, string name = __traits(identifier, fun))()
    {
        static assert(__traits(isStaticFunction, fun), "symbol " ~ __traits(identifier, fun)
                      ~ " of type " ~ typeof(fun).stringof ~ " is not a static function");

        alias ParameterTypeTuple!fun PT;
        static assert(isSomeString!(PT[0]), "the first argument of function " ~ name ~ " should be a string");
        static assert(isSomeString!(PT[1]), "the second argument of function " ~ name ~ " should be a string");
        static assert(isImplicitlyConvertible!(ReturnType!fun, int), "function " ~ name ~ " should return a value convertible to an int");

        enum x_compare = q{
            extern (C) static int @{name}(void*, int n1, const(void*) str1, int n2, const(void* )str2)
            {
                char[] s1, s2;
                s1.length = n1;
                s2.length = n2;
                import std.c.string : memcpy;
                memcpy(s1.ptr, str1, n1);
                memcpy(s2.ptr, str2, n2);
                return fun(cast(immutable) s1, cast(immutable) s2);
            }
        };
        mixin(render(x_compare, ["name": name]));

        assert(core.handle);
        auto result = sqlite3_create_collation(
            core.handle,
            name.toStringz(),
            SQLITE_UTF8,
            null,
            mixin("&" ~ name)
        );
        enforce(result == SQLITE_OK, new SqliteException(errorMsg, result));
    }
    ///
    unittest // Collation creation
    {
        static int my_collation(string s1, string s2)
        {
            import std.uni;
            return icmp(s1, s2);
        }

        auto db = Database(":memory:");
        db.createCollation!my_collation();
        db.execute("CREATE TABLE test (word TEXT)");

        auto query = db.query("INSERT INTO test (word) VALUES (:wd)");
        foreach (word; ["straße", "strasses"])
        {
            query.bind(":wd", word);
            query.execute();
            query.reset();
        }

        query = db.query("SELECT word FROM test ORDER BY word COLLATE my_collation");
        assert(query.oneValue!string == "straße");
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
    +/
    void createFunction(alias fun, string name = __traits(identifier, fun))()
    {
        import std.typetuple;

        static if (__traits(isStaticFunction, fun))
            enum funpointer = &fun;
        else
            static assert(false, "symbol " ~ __traits(identifier, fun) ~ " of type "
                          ~ typeof(fun).stringof ~ " is not a static function");

        static assert(variadicFunctionStyle!(fun) == Variadic.no);

        alias staticMap!(Unqual, ParameterTypeTuple!fun) PT;
        alias ReturnType!fun RT;

        enum x_func = q{
            extern(C) static void @{name}(sqlite3_context* context, int argc, sqlite3_value** argv)
            {
                PT args;
                int type, n;
                @{blob}

                @{block_read_values}

                try
                {
                    auto tmp = funpointer(args);
                    mixin(block_return_result!RT);
                }
                catch (Exception e)
                {
                    auto txt = "error in function @{name}(): " ~ e.msg;
                    sqlite3_result_error(context, cast(char*) txt.toStringz(), -1);
                }
            }
        };
        enum x_func_mix = render(x_func, [
            "name": name,
            "blob": staticIndexOf!(ubyte[], PT) >= 0 ? q{ubyte[] blob;} : "",
            "block_read_values": block_read_values!(PT.length, name, PT)
        ]);

        mixin(x_func_mix);

        assert(core.handle);
        auto result = sqlite3_create_function(
            core.handle,
            name.toStringz(),
            PT.length,
            SQLITE_UTF8,
            null,
            mixin(format("&%s", name)),
            null,
            null
        );
        enforce(result == SQLITE_OK, new SqliteException(errorMsg, result));
    }
    ///
    unittest // Function creation
    {
        static string my_msg(string name)
        {
            return "Hello, %s!".format(name);
        }
       
        auto db = Database(":memory:");
        db.createFunction!my_msg();

        auto query = db.query("SELECT my_msg('John')");
        assert(query.oneValue!string() == "Hello, John!");
    }
}

///
unittest // Documentation example
{
    // Note: exception handling is left aside for clarity.

    // Open a database in memory.
    auto db = Database(":memory:");

    // Create a table
    db.execute(
        "CREATE TABLE person (
            id INTEGER PRIMARY KEY,
            last_name TEXT NOT NULL,
            first_name TEXT,
            score FLOAT,
            photo BLOB
         )"
    );

    // Populate the table.
    auto query = db.query(
        "INSERT INTO person (last_name, first_name, score, photo)
         VALUES (:last_name, :first_name, :score, :photo)"
    );
    
    // Bind values.
    query.bind(":last_name", "Smith");
    query.bind(":first_name", "John");
    query.bind(":score", 77.5);
    query.bind(":photo", [0xDE, 0xEA, 0xBE, 0xEF]);
    query.execute();
    
    query.reset(); // Need to reset the query after execution.
    query.bind(":last_name", "Doe");
    query.bind(":first_name", "John");
    query.bind(3, 46.8); // Use of index instead of name.
    query.bind(":photo", null);
    query.execute();

    // Count the changes
    assert(db.totalChanges == 2);

    // Count the Johns in the table.
    query = db.query("SELECT count(*) FROM person WHERE first_name == 'John'");
    assert(query.oneValue!long == 2);

    // Read the data from the table lazily
    query = db.query("SELECT * FROM person");
    foreach (row; query)
    {
        // Retrieve "id", which is the column at index 0, and contains an int,
        // e.g. using the peek function (best performance).
        auto id = row.peek!long(0);

        // Retrieve "last_name" and "first_name", e.g. using opIndex(string),
        // which returns a ColumnData.
        auto name = format("%s, %s", row["last_name"].as!string, row["first_name"].as!string);

        // Retrieve "score", which is at index 3, e.g. using the peek function.
        auto score = row.peek!double("score");
        
        // Retrieve "photo", e.g. using opIndex(index),
        // which returns a ColumnData.
        auto photo = row[4].as!(ubyte[]);
        
        // ... and use all these data!
    }

    // Read all the table in memory at once
    auto data = QueryCache(db.query("SELECT * FROM person"));
    foreach (row; data)
    {
        auto id = row[0].as!long;
        auto name = format("%s, %s", row["last_name"], row["first_name"]);
        auto score = row["score"].as!double;
        auto photo = row[4].as!(ubyte[]);
        // etc.
    }
}

unittest // Database construction
{
    Database db1;
    auto db2 = db1;
    db1 = Database(":memory:");
    db2 = Database("");
    auto db3 = Database(null);
    db1 = db2;
    assert(db2.core.refCountedStore.refCount == 2);
    assert(db1.core.refCountedStore.refCount == 2);
}

unittest // Execute an SQL statement
{
    auto db = Database(":memory:");
    db.execute(";");
    db.execute("ANALYZE");
}


/++
An interface to SQLite query execution.
+/
struct Query
{
private:
    struct _Core
    {
        Database db;
        string sql;
        sqlite3_stmt* statement; // null if error or empty statement
        int state;
        
        this(Database db, string sql, sqlite3_stmt* statement)
        {
            this.db = db;
            this.sql = sql;
            this.statement = statement;
        }
        
        ~this()
        {
            auto result = sqlite3_finalize(statement);
            enforce(result == SQLITE_OK, new SqliteException(result));
            statement = null;
        }

        @disable this(this);
        void opAssign(_Core) { assert(false); }
    }
    alias RefCounted!_Core Core;
    Core core;
    
    @disable this();
    
    this(Database db, string sql)
    {
        sqlite3_stmt* statement;
        auto result = sqlite3_prepare_v2(
            db.core.handle,
            cast(char*) sql.toStringz(),
            cast(int) sql.length,
            &statement,
            null
        );
        enforce(result == SQLITE_OK, new SqliteException(db.errorMsg, result, sql));
        core = Core(db, sql, statement);
        if (statement is null)
            core.state = SQLITE_DONE;
    }

    int parameterCount()
    {
        if (core.statement)
            return sqlite3_bind_parameter_count(core.statement);
        else
            return 0;
    }

public:
    /++
    Gets the SQLite internal handle of the query _statement.
    +/
    @property sqlite3_stmt* statement()
    {
        return core.statement;
    }
    
    /++
    Binds values to parameters in the query.

    The index is the position of the parameter in the SQL query (starting from 0).
    The name must include the ':', '@' or '$' that introduces it in the query.
    +/
    void bind(T)(int index, T value)
    {
        enforce(parameterCount > 0, new SqliteException("no parameter to bind to"));
        
        alias Unqual!T U;
        int result;
        
        static if (is(U == typeof(null)) || is(U == void*))
        {
            result = sqlite3_bind_null(core.statement, index);
        }
        else static if (isIntegral!U && U.sizeof <= int.sizeof || isSomeChar!U)
        {
            result = sqlite3_bind_int(core.statement, index, value);
        }
        else static if (isIntegral!U && U.sizeof <= long.sizeof)
        {
            result = sqlite3_bind_int64(core.statement, index, value);
        }
        else static if (isFloatingPoint!U)
        {
            result = sqlite3_bind_double(core.statement, index, value);
        }
        else static if (isSomeString!U)
        {
            string utf8 = value.to!string;
            enforce(utf8.length <= int.max, new SqliteException("string too long"));
            result = sqlite3_bind_text(core.statement,
                                       index,
                                       cast(char*) utf8.toStringz(),
                                       cast(int) utf8.length,
                                       null);
        }
        else static if (isArray!U)
        {
            if (!value.length)
                result = sqlite3_bind_null(core.statement, index);
            else
            {
                auto bytes = cast(ubyte[]) value;
                enforce(bytes.length <= int.max, new SqliteException("array too long"));
                result = sqlite3_bind_blob(core.statement,
                                           index,
                                           cast(void*) bytes.ptr,
                                           cast(int) bytes.length,
                                           null);
            }
        }
        else
            static assert(false, "cannot bind a value of type " ~ U.stringof);
        
        enforce(result == SQLITE_OK, new SqliteException(result));
    }

    /// Ditto
    void bind(T)(string name, T value)
    {
        enforce(parameterCount > 0, new SqliteException("no parameter to bind to"));
        auto index = sqlite3_bind_parameter_index(core.statement, cast(char*) name.toStringz());
        enforce(index > 0, new SqliteException(format("no parameter named '%s'", name)));
        bind(index, value);
    }

    /++
    Clears the bindings.

    This does not reset the prepared statement. Use Query.reset() for this.
    +/
    void clearBindings()
    {
        if (core.statement)
        {
            auto result = sqlite3_clear_bindings(core.statement);
            enforce(result == SQLITE_OK, new SqliteException(result));
        }
    }

    /++
    Resets a query's prepared statement before a new execution.

    This does not clear the bindings. Use Query.clear() for this.
    +/
    void reset()
    {
        if (core.statement)
        {
            auto result = sqlite3_reset(core.statement);
            enforce(result == SQLITE_OK, new SqliteException(core.db.errorMsg, result));
            core.state = 0;
        }
    }
    
    /++
    Executes the query.

    If the query is expected to return rows, use the query's input range interface
    to iterate over them.
    +/
    void execute()
    {
        core.state = sqlite3_step(core.statement);
        if (core.state != SQLITE_ROW && core.state != SQLITE_DONE)
        {
            reset(); // necessary to retrieve the error message.
            throw new SqliteException(core.db.errorMsg, core.state);
        }
    }
    
    /++
    Input range interface.

    A $(D Query) is an input range of $(D Row)s. A Row becomes invalid
    as soon as $(D Query.popFront) is called (it contains undefined data afterwards).
    +/
    @property bool empty()
    {
        if (!core.state) execute();
        assert(core.state);
        return core.state == SQLITE_DONE;
    }
    
    /// ditto
    @property Row front()
    {
        if (!core.state) execute();
        assert(core.state);
        enforce(!empty, new SqliteException("No rows available"));
        return Row(core.statement);
    }
    
    /// ditto
    void popFront()
    {
        if (!core.state) execute();
        assert(core.state);
        enforce(!empty, new SqliteException("No rows available"));
        core.state = sqlite3_step(core.statement);
        enforce(core.state == SQLITE_DONE || core.state == SQLITE_ROW,
                new SqliteException(core.db.errorMsg, core.state));
    }

    /++
    Gets only the first value of the first row returned by a query.
    +/
    auto oneValue(T)()
    {
        return front.peek!T(0);
    }
    ///
    unittest // One value
    {
        auto db = Database(":memory:");
        db.execute("CREATE TABLE test (val INTEGER)");
        auto query = db.query("SELECT count(*) FROM test");
        assert(query.oneValue!long == 0);
    }
}

unittest // Empty query
{
    auto db = Database(":memory:");
    db.execute(";");
    auto query = db.query("-- This is a comment !");
    assert(query.empty);
    assert(query.parameterCount == 0);
    query.clearBindings();
    query.reset();
}

unittest // Simple parameters binding
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");
    
    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", 42);
    query.execute();
    query.reset();
    query.bind(1, 42);
    query.execute();
    
    query = db.query("SELECT * FROM test");
    foreach (row; query)
        assert(row.peek!int(0) == 42);
}

unittest // Multiple parameters binding
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto query = db.query("INSERT INTO test (i, f, t) VALUES (:i, @f, $t)");
    assert(query.parameterCount == 3);
    query.bind("$t", "TEXT");
    query.bind(":i", 42);
    query.bind("@f", 3.14);
    query.execute();
    query.reset();
    query.bind(3, "TEXT");
    query.bind(1, 42);
    query.bind(2, 3.14);
    query.execute();
    
    query = db.query("SELECT * FROM test");
    foreach (row; query)
    {
        assert(row.length == 3);
        assert(row.peek!int("i") == 42);
        assert(row.peek!double("f") == 3.14);
        assert(row.peek!string("t") == "TEXT");
    }
}

unittest // Other Query tests
{
    auto db = Database(":memory:");
    {
        db.execute("CREATE TABLE test (val INTEGER)");
        auto tmp = db.query("INSERT INTO test (val) VALUES (:val)");
        tmp.bind(":val", 42);
        tmp.execute();
    }
    
    auto query = { return db.query("SELECT * FROM test"); }();
    assert(!query.empty);
    assert(query.front.peek!int(0) == 42);
    query.popFront();
    assert(query.empty);

    query = db.query("SELECT * FROM test WHERE val=%s".format(43.literal));
    assert(query.empty);
}


/++
A SQLite row, implemented as a random-access range of ColumnData.

Warning:
    A Row is just a view of the current row when iterating the results of a $(D Query). 
    It becomes invalid as soon as $(D Query.popFront) is called. Row contains
    undefined data afterwards.
+/
struct Row
{
    private
    {
        sqlite3_stmt* statement;
        int frontIndex;
        int backIndex;
    }

    this(sqlite3_stmt* statement)
    {
        assert(statement);
        this.statement = statement;
        backIndex = sqlite3_column_count(statement) - 1;
    }

    /// Input range primitives.
    @property bool empty()
    {
        return length == 0;
    }

    /// ditto
    @property ColumnData front()
    {
        return ColumnData(peek!Variant(0));
    }

    /// ditto
    void popFront()
    {
        frontIndex++;
    }
   
    /// Forward range primitive.
    @property Row save()
    {
        Row ret;
        ret.statement = statement;
        ret.frontIndex = frontIndex;
        ret.backIndex = backIndex;
        return ret;
    }
    
    /// Bidirectional range primitives.
    @property ColumnData back()
    {
        return ColumnData(peek!Variant(backIndex - frontIndex));
    }
    
    /// ditto
    void popBack()
    {
        backIndex--;
    }
    
    /// Random access range primitives.
    @property int length()
    {
        return backIndex - frontIndex + 1;
    }

    /++
    Return the content of a column, automatically cast to T.

    T must be a boolean, a built-in numeric type, a string, an array or a Variant.

    If the column data is NULL, T.init is returned.

    Warning:
        If the column is specified by its name, the names of all the columns are tested
        each time this function is called: use numeric indexing for better performance.
    +/
    auto peek(T)(int index)
    {
        int i =  cast(int) index + frontIndex;
        enforce(i >= 0 && i <= backIndex, new SqliteException(format("invalid column index: %d", i)));
        
        static if (isBoolean!T || isIntegral!T)
        {
            return cast(T) sqlite3_column_int64(statement, i);
        }
        else static if (isFloatingPoint!T)
        {
            if (sqlite3_column_type(statement, i) == SQLITE_NULL)
                return double.nan;
            return cast(T) sqlite3_column_double(statement, i);
        }
        else static if (isSomeString!T)
        {
            return sqlite3_column_text(statement, i).to!T;
        }
        else static if (isArray!T)
        {
            auto ptr = sqlite3_column_blob(statement, i);
            auto length = sqlite3_column_bytes(statement, i);
            ubyte[] blob;
            blob.length = length;
            import std.c.string : memcpy;
            memcpy(blob.ptr, ptr, length);
            return cast(T) blob;
        }
        else static if (is(T == Variant))
        {
            auto type = sqlite3_column_type(statement, i);
            final switch (type)
            {
                case SQLITE_INTEGER:
                    return Variant(peek!long(index));
                    
                case SQLITE_FLOAT:
                    return Variant(peek!double(index));
                    
                case SQLITE3_TEXT:
                    return Variant(peek!string(index));
                    
                case SQLITE_BLOB:
                    return Variant(peek!(ubyte[])(index));
                    
                case SQLITE_NULL:
                    return Variant();        
            }
        }
        else
            static assert(false, "value cannot be converted to type " ~ T.stringof);
    }

    /// ditto
    auto peek(T)(string name)
    {
        foreach (i; frontIndex .. backIndex + 1)
            if (sqlite3_column_name(statement, i).to!string == name)
                return peek!T(i);
        
        throw new SqliteException("invalid column name: '%s'".format(name));
    }

    /++
    Returns the data of a given column as a ColumnData.
    +/
    ColumnData opIndex(int index)
    {
        return ColumnData(peek!Variant(index));
    }
    
    /// ditto
    ColumnData opIndex(string name)
    {
        return ColumnData(peek!Variant(name));
    }
}

version (unittest)
{
    static assert(isRandomAccessRange!Row);
    static assert(is(ElementType!Row == ColumnData));
}

unittest // Row random-access range interface
{
    auto db = Database(":memory:");

    {
        db.execute("CREATE TABLE test (a INTEGER, b INTEGER, c INTEGER, d INTEGER)");
        auto query = db.query("INSERT INTO test (a, b, c, d) VALUES (:a, :b, :c, :d)");
        query.bind(":a", 1);
        query.bind(":b", 2);
        query.bind(":c", 3);
        query.bind(":d", 4);
        query.execute();
        query.reset();
        query.bind(":a", 5);
        query.bind(":b", 6);
        query.bind(":c", 7);
        query.bind(":d", 8);
        query.execute();
    }

    {
        auto query = db.query("SELECT * FROM test");
        auto values = [1, 2, 3, 4, 5, 6, 7, 8];
        foreach (row; query)
        {
            while (!row.empty)
            {
                assert(row.front.as!int == values.front);
                row.popFront();
                values.popFront();
            }
        }
    }

    {
        auto query = db.query("SELECT * FROM test");
        auto values = [4, 3, 2, 1, 8, 7, 6, 5];
        foreach (row; query)
        {
            while (!row.empty)
            {
                assert(row.back.as!int == values.front);
                row.popBack();
                values.popFront();
            }
        }
    }

    auto query = { return db.query("SELECT * FROM test"); }();
    auto values = [1, 2, 3, 4, 5, 6, 7, 8];
    foreach (row; query)
    {
        while (!row.empty)
        {
            assert(row.front.as!int == values.front);
            row.popFront();
            values.popFront();
        }
    }
}


/++
Some column's data.

The data is stored internally as a Variant, which is accessible through "$(D alias this)".
+/
struct ColumnData
{
    Variant variant;
    alias variant this;
    
    /++
    Returns the data converted to T.

    If the data is NULL, defaultValue is returned.
    +/
    auto as(T)(T defaultValue = T.init)
    {
        if (!variant.hasValue)
            return defaultValue;
        
        static if (isBoolean!T || isNumeric!T || isSomeChar!T || isSomeString!T)
        {
            return variant.coerce!T;
        }
        else static if (isArray!T)
        {
            auto a = variant.get!(ubyte[]);
            return cast(T) a;
        }
        else
            throw new SqliteException("Cannot convert value to type %s".format(T.stringof));
    }
}


unittest // Getting integral values
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", cast(byte) 42);
    query.execute();
    query.reset();
    query.bind(":val", 42U);
    query.execute();
    query.reset();
    query.bind(":val", 42UL);
    query.execute();
    query.reset();
    query.bind(":val", '\x2A');
    query.execute();

    query = db.query("SELECT * FROM test");
    foreach (row; query)
        assert(row.peek!long(0) == 42);
}

unittest // Getting floating point values
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val FLOAT)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", 42.0F);
    query.execute();
    query.reset();
    query.bind(":val", 42.0);
    query.execute();
    query.reset();
    query.bind(":val", 42.0L);
    query.execute();
    query.reset();
    query.bind(":val", "42");
    query.execute();

    query = db.query("SELECT * FROM test");
    foreach (row; query)
        assert(row.peek!double(0) == 42.0);
}

unittest // Getting text values
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val TEXT)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", "I am a text.");
    query.execute();

    query = db.query("SELECT * FROM test");
    assert(query.front.peek!string(0) == "I am a text.");
}

unittest // Getting blob values
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val BLOB)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    ubyte[] array = [1, 2, 3];
    query.bind(":val", array);
    query.execute();

    query = db.query("SELECT * FROM test");
    foreach (row; query)
        assert(row.peek!(ubyte[])(0) ==  [1, 2, 3]);
}

unittest // Getting null values
{
    import std.math;

    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val TEXT)");

    auto query = db.query("INSERT INTO test (val) VALUES (:val)");
    query.bind(":val", null);
    query.execute();

    query = db.query("SELECT * FROM test");
    assert(query.front.peek!bool(0) == false);
    assert(query.front.peek!long(0) == 0);
    assert(query.front.peek!double(0).isnan);
    assert(query.front.peek!string(0) is null);
    assert(query.front.peek!(ubyte[])(0) is null);
    assert(query.front[0].as!bool == false);
    assert(query.front[0].as!long == 0);
    assert(query.front[0].as!double.isnan);
    assert(query.front[0].as!string is null);
    assert(query.front[0].as!(ubyte[]) is null);
}


/++
Caches all the results of a Query in memory as ColumnData.

Allows to iterate on the rows and their columns with an array-like interface.
The rows can be viewed as an array of ColumnData or as an associative array of
ColumnData indexed by the column names.
+/
struct QueryCache
{
    struct CachedRow
    {
        ColumnData[] columns;
        alias columns this;

        int[string] columnIndexes;

        private this(Row row, int[string] columnIndexes)
        {
            this.columnIndexes = columnIndexes;

            auto colapp = appender!(ColumnData[]);
            foreach (i; 0 .. row.length)
                colapp.put(ColumnData(row.peek!Variant(i)));
            columns = colapp.data;
        }

        ColumnData opIndex(int index)
        {
            return columns[index];
        }

        ColumnData opIndex(string name)
        {
            auto index = name in columnIndexes;
            enforce(index, new SqliteException("Unknown column name: %s".format(name)));
            return columns[*index];
        }
    }

    CachedRow[] rows;
    alias rows this;

    private int[string] columnIndexes;

    /++
    Creates and populates the cache from the results of the query.

    Warning:
        The query will be reset once this constructor have populated the cache.
        Don't call this constructor while using query's range interface.
    +/
    this(Query query)
    {
        if (!query.empty)
        {
            auto first = query.front;
            foreach (i; 0 .. first.length)
            {
                auto name = sqlite3_column_name(first.statement, i).to!string;
                columnIndexes[name] = i;
            }
        }

        auto rowapp = appender!(CachedRow[]);        
        foreach (row; query)
            rowapp.put(CachedRow(row, columnIndexes));
        rows = rowapp.data;
        query.reset();
    }
}
///
unittest
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (msg TEXT, num FLOAT)");
    
    auto query = db.query("INSERT INTO test (msg, num) VALUES (:msg, :num)");
    query.bind(":msg", "ABC");
    query.bind(":num", 123);
    query.execute();
    query.reset();
    query.bind(":msg", "DEF");
    query.bind(":num", 456);
    query.execute();
    
    query = db.query("SELECT * FROM test");
    auto data = QueryCache(query);
    assert(data.length == 2);
    assert(data[0].front.as!string == "ABC");
    assert(data[0][1].as!int == 123);
    assert(data[1]["msg"].as!string == "DEF");
    assert(data[1]["num"].as!int == 456);
}

unittest // QueryCache copies
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (msg TEXT)");
    auto query = db.query("INSERT INTO test (msg) VALUES (:msg)");
    query.bind(":msg", "ABC");
    query.execute();

    static getdata(Database db)
    {
        auto query = db.query("SELECT * FROM test");
        return QueryCache(query);
    }

    auto data = getdata(db);
    assert(data.length == 1);
    assert(data[0][0].as!string == "ABC");
}


/++
Turns a value into a literal that can be used in an SQLite expression.
+/
string literal(T)(T value)
{
    static if (is(T == typeof(null)))
        return "NULL";
    else static if (isBoolean!T)
        return value ? "1" : "0";
    else static if (isNumeric!T)
        return value.to!string();
    else static if (isSomeString!T)
        return format("'%s'", value.replace("'", "''"));
    else static if (isArray!T)
        return "'X%(%X%)'".format(cast(ubyte[]) value);
    else
        static assert(false, "cannot make a literal of a value of type " ~ T.stringof);
}
///
unittest
{
    assert(null.literal == "NULL");
    assert(false.literal == "0");
    assert(true.literal == "1");
    assert(4.literal == "4");
    assert(4.1.literal == "4.1");
    assert("foo".literal == "'foo'");
    assert("a'b'".literal == "'a''b'''");
    auto a = cast(ubyte[]) x"DEADBEEF";
    assert(a.literal == "'XDEADBEEF'");
}

/++
Exception thrown when SQLite functions return an error.
+/
class SqliteException : Exception
{
    int code;
    string sql;

    private this(string msg, string sql, int code,
                 string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        this.sql = sql;
        this.code = code;
        super(msg, file, line, next);
    }

    this(int code, string sql = null,
         string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        this("error %d".format(code), sql, code, file, line, next);
    }

    this(string msg, int code, string sql = null,
         string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        this("error %d : %s".format(code, msg), sql, code, file, line, next);
    }

    this(string msg, string sql = null,
         string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        this(msg, sql, code, file, line, next);
    }
}

// Compile-time rendering of code templates.
private string render(string templ, string[string] args)
{
    string markupStart = "@{";
    string markupEnd = "}";

    string result;
    auto str = templ;
    while (true)
    {
        auto p_start = std.string.indexOf(str, markupStart);
        if (p_start < 0)
        {
            result ~= str;
            break;
        }
        else
        {
            result ~= str[0 .. p_start];
            str = str[p_start + markupStart.length .. $];

            auto p_end = std.string.indexOf(str, markupEnd);
            if (p_end < 0)
                assert(false, "Tag misses ending }");
            auto key = strip(str[0 .. p_end]);

            auto value = key in args;
            if (!value)
                assert(false, "Key '" ~ key ~ "' has no associated value");
            result ~= *value;

            str = str[p_end + markupEnd.length .. $];
        }
    }

    return result;
}

unittest // Code templates
{
    enum tpl = q{
        string @{function_name}() {
            return "Hello world!";
        }
    };
    mixin(render(tpl, ["function_name": "hello_world"]));
    static assert(hello_world() == "Hello world!");
}
