// Written in the D programming language
/++
This module provides a thin and convenient wrapper around the SQLite C API.

Features:
$(UL
    $(LI Use reference-counted structs (Database, Statement, ResultRange) instead of SQLite objects
    pointers.)
    $(LI Run multistatement SQL code with `Database.run()`.)
    $(LI Use built-in integral types, floating point types, `string`s, `ubyte[]` and
    `Nullable` types directly: conversions to and from SQLite types is automatic and GC-safe.)
    $(LI Bind multiple values to a prepare statement with `Statement.bindAll()` or
    `Statement.inject()`. It's also possible to bind the fields of a struct automatically with
    `Statement.inject()`.)
    $(LI Handle the results of a query as a range of `Row`s, and the columns of a row
    as a range of `ColumnData` (equivalent of a `Variant` fit for SQLite types).)
    $(LI Access the data in a result row directly, by index or by name,
    with the `Row.peek!T()` methods.)
    $(LI Make a struct out of the data of a row with `Row.as!T()`.)
    $(LI Register D functions as SQLite callbacks, with `Database.setUpdateHook()` $(I et al).)
    $(LI Create new SQLite functions, aggregates or collations out of D functions or delegate,
    with automatic type converions, with `Database.createFunction()` $(I et al).)
    $(LI Store all the rows and columns resulting from a query at once with `QueryCache` (sometimes
    useful even if not memory-friendly...).)
)

Authors:
    Nicolas Sicard (biozic) and other contributors at $(LINK https://github.com/biozic/d2sqlite3)

Copyright:
    Copyright 2011-15 Nicolas Sicard.

License:
    $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).

+/
module d2sqlite3;

import std.algorithm;
import std.array;
import std.conv;
import std.exception;
import std.range;
import std.string;
import std.traits;
import std.typecons;
import std.typetuple;
import core.memory : GC;
import core.stdc.string : memcpy;
import core.stdc.stdlib : malloc, free;

public import sqlite3;

///
unittest // Documentation example
{
    // Note: exception handling is left aside for clarity.
    import d2sqlite3;
    import std.typecons : Nullable;

    // Open a database in memory.
    auto db = Database(":memory:");

    // Create a table
    db.run("CREATE TABLE person (
              id    INTEGER PRIMARY KEY,
              name  TEXT NOT NULL,
              score FLOAT
            )");

    // Populate the table

    // Prepare an INSERT statement
    Statement statement = db.prepare(
        "INSERT INTO person (name, score)
         VALUES (:name, :score)"
    );

    // Bind values one by one (by parameter name or index)
    statement.bind(":name", "John");
    statement.bind(2, 77.5);
    statement.execute();
    statement.reset(); // Need to reset the statement after execution.

    // Bind muliple values at the same time
    statement.bindAll("John", null);
    statement.execute();
    statement.reset();

    // Bind, execute and reset in one call
    statement.inject("Clara", 88.1);


    // Count the changes
    assert(db.totalChanges == 3);


    // Count the Johns in the table.
    auto count = db.execute("SELECT count(*) FROM person WHERE name == 'John'")
                   .oneValue!long;
    assert(count == 2);


    // Read the data from the table lazily
    ResultRange results = db.execute("SELECT * FROM person");
    foreach (Row row; results)
    {
        // Retrieve "id", which is the column at index 0, and contains an int,
        // e.g. using the peek function (best performance).
        auto id = row.peek!long(0);

        // Retrieve "name", e.g. using opIndex(string), which returns a ColumnData.
        auto name = row["name"].as!string;

        // Retrieve "score", which is at index 2, e.g. using the peek function,
        // using a Nullable type
        auto score = row.peek!(Nullable!double)(2);
        if (!score.isNull)
        {
            // ...
        }
    }
}


/// SQLite type codes
enum SqliteType
{
    INTEGER = SQLITE_INTEGER, ///
    FLOAT = SQLITE_FLOAT, ///
    TEXT = SQLITE3_TEXT, ///
    BLOB = SQLITE_BLOB, ///
    NULL = SQLITE_NULL ///
}

/++
Gets the library's version string (e.g. "3.8.7").
+/
string versionString()
{
    return to!string(sqlite3_libversion());
}

/++
Gets the library's version number (e.g. 3008007).
+/
int versionNumber() nothrow
{
    return sqlite3_libversion_number();
}

unittest
{
    import std.string : startsWith;
    assert(versionString.startsWith("3."));
    assert(versionNumber >= 3008007);
}

/++
Tells whether SQLite was compiled with the thread-safe options.

See_also: ($LINK http://www.sqlite.org/c3ref/threadsafe.html).
+/
bool threadSafe() nothrow
{
    return cast(bool) sqlite3_threadsafe();
}
unittest
{
    auto ts = threadSafe;
}

/++
Manually initializes (or shuts down) SQLite.

SQLite initializes itself automatically on the first request execution, so this
usually wouldn't be called. Use for instance before a call to config().
+/
void initialize()
{
    auto result = sqlite3_initialize();
    enforce(result == SQLITE_OK, new SqliteException("Initialization: error %s".format(result)));
}
/// Ditto
void shutdown()
{
    auto result = sqlite3_shutdown();
    enforce(result == SQLITE_OK, new SqliteException("Shutdown: error %s".format(result)));
}

/++
Sets a configuration option.

Use before initialization, e.g. before the first
call to initialize and before execution of the first statement.

See_Also: $(LINK http://www.sqlite.org/c3ref/config.html).
+/
void config(Args...)(int code, Args args)
{
    auto result = sqlite3_config(code, args);
    enforce(result == SQLITE_OK, new SqliteException("Configuration: error %s".format(result)));
}
unittest
{
    shutdown();
    config(SQLITE_CONFIG_MULTITHREAD);
    config(SQLITE_CONFIG_LOG, function(void* p, int code, const(char)* msg) {}, null);
    initialize();
}


/++
A caracteristic of user-defined functions or aggregates.
+/
enum Deterministic
{
    /++
    The returned value is the same if the function is called with the same parameters.
    +/
    yes = 0x800,

    /++
    The returned value can vary even if the function is called with the same parameters.
    +/
    no = 0
}


/++
An SQLite database connection.

This struct is a reference-counted wrapper around a `sqlite3*` pointer.
+/
struct Database
{
private:
    struct _Payload
    {
        sqlite3* handle;
        void* updateHook;
        void* commitHook;
        void* rollbackHook;
        void* progressHandler;
        void* traceCallback;
        void* profileCallback;

        this(sqlite3* handle) nothrow
        {
            this.handle = handle;
        }

        ~this()
        {
            if (handle)
            {
                sqlite3_progress_handler(handle, 0, null, null);
                auto result = sqlite3_close(handle);
                enforce(result == SQLITE_OK, new SqliteException(errmsg(handle), result));
            }
            handle = null;
            ptrFree(updateHook);
            ptrFree(commitHook);
            ptrFree(rollbackHook);
            ptrFree(progressHandler);
            ptrFree(traceCallback);
            ptrFree(profileCallback);
        }

        @disable this(this);
        @disable void opAssign(_Payload);
    }

    alias Payload = RefCounted!(_Payload, RefCountedAutoInitialize.no);
    Payload p;

    void check(int result) {
        enforce(result == SQLITE_OK, new SqliteException(errmsg(p.handle), result));
    }

public:
    /++
    Opens a database connection.

    Params:
        path = The path to the database file. In recent versions of SQLite, the path can be
        an URI with options.

        flags = Options flags.

    See_Also: $(LINK http://www.sqlite.org/c3ref/open.html) to know how to use the flags
    parameter or to use path as a file URI if the current configuration allows it.
    +/
    this(string path, int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
    {
        sqlite3* hdl;
        auto result = sqlite3_open_v2(path.toStringz, &hdl, flags, null);
        enforce(result == SQLITE_OK, new SqliteException(p.handle ? errmsg(p.handle) : "Error opening the database", result));
        p = Payload(hdl);
    }

    /++
    Gets the SQLite internal _handle of the database connection.
    +/
    sqlite3* handle() @property nothrow
    {
        return p.handle;
    }

    /++
    Gets the path associated with an attached database.

    Params:
        database = The name of an attached database.

    Returns: The absolute path of the attached database.
        If there is no attached database, or if database is a temporary or
        in-memory database, then null is returned.
    +/
    string attachedFilePath(string database = "main")
    {
        return sqlite3_db_filename(p.handle, database.toStringz).to!string;
    }

    /++
    Gets the read-only status of an attached database.

    Params:
        database = The name of an attached database.
    +/
    bool isReadOnly(string database = "main")
    {
        int ret = sqlite3_db_readonly(p.handle, database.toStringz);
        enforce(ret >= 0, new SqliteException("Database not found: %s".format(database)));
        return ret == 1;
    }

    /++
    Gets metadata for a specific table column of an attached database.

    Params:
        table = The name of the table.

        column = The name of the column.

        database = The name of a database attached. If null, then all attached databases
        are searched for the table using the same algorithm used by the database engine
        to resolve unqualified table references.
    +/
    ColumnMetadata tableColumnMetadata(string table, string column, string database = "main")
    {
        ColumnMetadata data;
        char* pzDataType, pzCollSeq;
        int notNull, primaryKey, autoIncrement;
        check(sqlite3_table_column_metadata(p.handle, database.toStringz, table.toStringz,
            column.toStringz, &pzDataType, &pzCollSeq, &notNull, &primaryKey, &autoIncrement));
        data.declaredTypeName = pzDataType.to!string;
        data.collationSequenceName = pzCollSeq.to!string;
        data.isNotNull = cast(bool) notNull;
        data.isPrimaryKey = cast(bool) primaryKey;
        data.isAutoIncrement = cast(bool) autoIncrement;
        return data;
    }
    unittest
    {
        auto db = Database(":memory:");
        db.run("CREATE TABLE test (id INTEGER PRIMARY KEY AUTOINCREMENT,
                val FLOAT NOT NULL)");
        assert(db.tableColumnMetadata("test", "id") ==
               ColumnMetadata("INTEGER", "BINARY", false, true, true));
        assert(db.tableColumnMetadata("test", "val") ==
               ColumnMetadata("FLOAT", "BINARY", true, false, false));
    }

    /++
    Explicitly closes the database connection.

    After a call to `close()`, using the database connection or one of its prepared statement
    is an error. The `Database` object is destroyed and cannot be used any more.
    +/
    void close()
    {
        destroy(p);
    }

    /++
    Executes a single SQL statement and returns the results directly.
    
    It's the equivalent of `prepare(sql).execute()`.

    The results become undefined when the Database goes out of scope and is destroyed.
    +/
    ResultRange execute(string sql)
    {
        return prepare(sql).execute();
    }
    ///
    unittest
    {
        auto db = Database(":memory:");
        db.execute("VACUUM");
    }

    /++
    Runs an SQL script that can contain multiple statements.

    Params:
        sql = The code of the script.

        dg = A delegate to call for each statement to handle the results. The passed
        ResultRange will be empty if a statement doesn't return rows. If the delegate
        return false, the execution is aborted.
    +/
    void run(string sql, bool delegate(ResultRange) dg = null)
    {
        foreach (statement; sql.byStatement)
        {
            auto stmt = prepare(statement);
            auto results = stmt.execute();
            if (dg && !dg(results))
                return;
        }
    }
    ///
    unittest
    {
        auto db = Database(":memory:");
        db.run(`CREATE TABLE test1 (val INTEGER);
                CREATE TABLE test2 (val FLOAT);
                DROP TABLE test1;
                DROP TABLE test2;`);
    }
    unittest
    {
        auto db = Database(":memory:");
        int i;
        db.run(`SELECT 1; SELECT 2;`, (ResultRange r) { i = r.oneValue!int; return false; });
        assert(i == 1);
    }

    /++
    Prepares (compiles) a single SQL statement and returngs it, so that it can be bound to
    values before execution.

    The statement becomes invalid if the Database goes out of scope and is destroyed.
    +/
    Statement prepare(string sql)
    {
        return Statement(this, sql);
    }

    /// Convenience functions equivalent to an SQL statement.
    void begin() { execute("BEGIN"); }
    /// Ditto
    void commit() { execute("COMMIT"); }
    /// Ditto
    void rollback() { execute("ROLLBACK"); }

    /++
    Returns the rowid of the last INSERT statement.
    +/
    long lastInsertRowid()
    {
        return sqlite3_last_insert_rowid(p.handle);
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted by the most
    recently executed SQL statement.
    +/
    int changes() @property nothrow
    {
        assert(p.handle);
        return sqlite3_changes(p.handle);
    }

    /++
    Gets the number of database rows that were changed, inserted or deleted since the
    database was opened.
    +/
    int totalChanges() @property nothrow
    {
        assert(p.handle);
        return sqlite3_total_changes(p.handle);
    }

    /++
    Gets the SQLite error code of the last operation.
    +/
    int errorCode() @property nothrow
    {
        return p.handle ? sqlite3_errcode(p.handle) : 0;
    }
    unittest
    {
        auto db = Database(":memory:");
        db.run(`SELECT 1;`);
        assert(db.errorCode == SQLITE_OK);
        try
            db.run(`DROP TABLE non_existent`);
        catch (SqliteException e)
            assert(db.errorCode == SQLITE_ERROR);
    }

    version (SQLITE_OMIT_LOAD_EXTENSION) {}
    else
    {
        /++
        Enables or disables loading extensions.
        +/
        void enableLoadExtensions(bool enable = true)
        {
            enforce(sqlite3_enable_load_extension(p.handle, enable) == SQLITE_OK,
                new SqliteException("Could not enable loading extensions."));
        }
        
        /++
        Loads an extension.

        Params:
            path = The path of the extension file.

            entryPoint = The name of the entry point function. If null is passed, SQLite
            uses the name of the extension file as the entry point.
        +/
        void loadExtension(string path, string entryPoint = null)
        {
            auto ret = sqlite3_load_extension(p.handle, path.toStringz, entryPoint.toStringz, null);
            enforce(ret == SQLITE_OK, new SqliteException(
                    "Could not load extension: %s:%s".format(entryPoint, path)));
        }
    }

    /++
    Creates and registers a new function in the database.

    If a function with the same name and the same arguments already exists, it is replaced
    by the new one.

    The memory associated with the function will be released when the database connection
    is closed.

    Params:
        name = The name that the function will have in the database.

        fun = a delegate or function that implements the function. $(D_PARAM fun)
        must satisfy the following criteria:
            $(UL
                $(LI It must not be variadic.)
                $(LI Its arguments must all have a type that is compatible with SQLite types:
                it must be a boolean or numeric type, a string, an array, `null`,
                or a `Nullable!T` where T is any of the previous types.)
                $(LI Its return value must also be of a compatible type.)
            )
            or
            $(UL
                $(LI It must be a normal or type-safe variadic function where the arguments
                are of type `ColumnData`. In other terms, the signature of the function must be:
                `function(ColumnData[] args)` or `function(ColumnData[] args...)`)
                $(LI Its return value must be a boolean or numeric type, a string, an array, `null`,
                or a `Nullable!T` where T is any of the previous types.)
            )
        Pass a `null` function pointer to delete the function from the database connection.

        det = Tells SQLite whether the result of the function is deterministic, i.e. if the
        result is the same when called with the same parameters. Recent versions of SQLite
        perform optimizations based on this. Set to `Deterministic.no` otherwise.

    See_Also: $(LINK http://www.sqlite.org/c3ref/create_function.html).
    +/
    void createFunction(T)(string name, T fun, Deterministic det = Deterministic.yes)
        if (isFunctionPointer!T || isDelegate!T)
    {
        static assert(variadicFunctionStyle!(fun) == Variadic.no
            || is(ParameterTypeTuple!fun == TypeTuple!(ColumnData[])),
            "only type-safe variadic functions with ColumnData arguments are supported");

        if (!fun)
            createFunction(name, null);

        static if (is(ParameterTypeTuple!fun == TypeTuple!(ColumnData[])))
        {
            extern(C) static
            void x_func(sqlite3_context* context, int argc, sqlite3_value** argv)
            {
                string name;
                try
                {
                    auto args = appender!(ColumnData[]);
                
                    for (int i = 0; i < argc; ++i)
                    {
                        auto value = argv[i];
                        auto type = sqlite3_value_type(value);
                        
                        final switch (type)
                        {
                            case SqliteType.INTEGER:
                                args.put(ColumnData(getValue!long(value)));
                                break;
                                
                            case SqliteType.FLOAT:
                                args.put(ColumnData(getValue!double(value)));
                                break;
                                
                            case SqliteType.TEXT:
                                args.put(ColumnData(getValue!string(value)));
                                break;
                                
                            case SqliteType.BLOB:
                                args.put(ColumnData(getValue!(ubyte[])(value)));
                                break;
                                
                            case SqliteType.NULL:
                                args.put(ColumnData(null));
                                break;
                        }
                    }
                    
                    auto ptr = sqlite3_user_data(context);

                    auto wrappedDelegate = delegateUnwrap!T(ptr);
                    auto dlg = wrappedDelegate.dlg;
                    name = wrappedDelegate.name;
                    setResult(context, dlg(args.data));
                }
                catch (Exception e)
                {
                    auto txt = "error in function %s(): %s".format(name, e.msg);
                    sqlite3_result_error(context, txt.toStringz, -1);
                }
            }
        }
        else
        {
            static assert(!is(ReturnType!fun == void), "function must not return void");

            alias PT = staticMap!(Unqual, ParameterTypeTuple!fun);
            alias PD = ParameterDefaultValueTuple!fun;

            extern (C) static void x_func(sqlite3_context* context, int argc, sqlite3_value** argv)
            {
                string name;
                try
                {
                    // Get the deledate and its name
                    auto ptr = sqlite3_user_data(context);
                    auto wrappedDelegate = delegateUnwrap!T(ptr);
                    auto dlg = wrappedDelegate.dlg;
                    name = wrappedDelegate.name;

                    enum maxArgc = PT.length;
                    enum minArgc = PT.length - EraseAll!(void, PD).length;

                    if (argc > maxArgc)
                    {
                        auto txt = "too many arguments in function %s(), expecting at most %s"
                            .format(name, maxArgc);
                        sqlite3_result_error(context, txt.toStringz, -1);
                    }
                    else if (argc < minArgc)
                    {
                        auto txt = "too few arguments in function %s(), expecting at least %s"
                            .format(name, minArgc);
                        sqlite3_result_error(context, txt.toStringz, -1);
                    }
                    else
                    {
                        PT args;
                        foreach (i, type; PT)
                        {
                            if (i < argc)
                                args[i] = getValue!type(argv[i]);
                            else
                                static if (is(typeof(PD[i])))
                                    args[i] = PD[i];
                        }
                        setResult(context, dlg(args));
                    }
                }
                catch (Exception e)
                {
                    auto txt = "error in function %s(): %s".format(name, e.msg);
                    sqlite3_result_error(context, txt.toStringz, -1);
                }
            }
        }

        assert(p.handle);
        check(sqlite3_create_function_v2(p.handle, name.toStringz, -1,
                SQLITE_UTF8 | det, delegateWrap(fun, name), &x_func, null, null, &ptrFree));
    }
    ///
    unittest
    {
        string star(int count, string starSymbol = "*")
        {
            import std.range : repeat;
            import std.array : join;
            
            return starSymbol.repeat(count).join;
        }

        auto db = Database(":memory:");
        db.createFunction("star", &star);
        assert(db.execute("SELECT star(5)").oneValue!string == "*****");
        assert(db.execute("SELECT star(3, '♥')").oneValue!string == "♥♥♥");
    }
    ///
    unittest
    {
        // The implementation of the new function
        string myList(ColumnData[] args)
        {
            Appender!(string[]) app;
            foreach (arg; args)
            {
                if (arg._type == SqliteType.TEXT)
                    app.put(`"%s"`.format(arg));
                else
                    app.put("%s".format(arg));
            }
            return app.data.join(", ");
        }

        auto db = Database(":memory:");
        db.createFunction("my_list", &myList);
        auto list = db.execute("SELECT my_list(42, 3.14, 'text', NULL)").oneValue!string;
        assert(list == `42, 3.14, "text", null`);
    }
    unittest
    {
        string myList(ColumnData[] args...)
        {
            Appender!(string[]) app;
            foreach (arg; args)
            {
                if (arg._type == SqliteType.TEXT)
                    app.put(`"%s"`.format(arg));
                else
                    app.put("%s".format(arg));
            }
            return app.data.join(", ");
        }
        auto db = Database(":memory:");
        db.createFunction("my_list", &myList);
        auto list = db.execute("SELECT my_list(42, 3.14, 'text', x'00FF', NULL)").oneValue!string;
        assert(list == `42, 3.14, "text", [0, 255], null`, list);
    }

    /// Ditto
    void createFunction(T)(string name, T fun)
        if (is(T == typeof(null)))
    {
        assert(p.handle);
        check(sqlite3_create_function_v2(p.handle, name.toStringz, -1, SQLITE_UTF8,
                null, null, null, null, null));
    }

    unittest
    {
        int myFun(int a, int b = 1)
        {
            return a * b;
        }
        
        auto db = Database(":memory:");
        db.createFunction("myFun", &myFun);
        assertThrown!SqliteException(db.execute("SELECT myFun()"));
        assertThrown!SqliteException(db.execute("SELECT myFun(1, 2, 3)"));
        assert(db.execute("SELECT myFun(5)").oneValue!int == 5);
        assert(db.execute("SELECT myFun(5, 2)").oneValue!int == 10);

        db.createFunction("myFun", null);
        assertThrown!SqliteException(db.execute("SELECT myFun(5)"));
        assertThrown!SqliteException(db.execute("SELECT myFun(5, 2)"));
    }
    
    deprecated("Kept for compatibility. Use of the new createFunction method is recommended.")
    void createFunction(string name, T)(T fun, Deterministic det = Deterministic.yes)
        if (isFunctionPointer!T || isDelegate!T)
    {
        createFunction(name, fun, det);
    }

    /++
    Creates and registers a new aggregate function in the database.

    Params:
        name = The name that the aggregate function will have in the database.

        agg = The struct of type T implementing the aggregate. T must implement
        at least these two methods: `accumulate()` and `result()`.
        Each parameter and the returned type of `accumulate()` and `result()` must be
        a boolean or numeric type, a string, an array, `null`, or a `Nullable!T`
        where T is any of the previous types. These methods cannot be variadic.

        det = Tells SQLite whether the result of the function is deterministic, i.e. if the
        result is the same when called with the same parameters. Recent versions of SQLite
        perform optimizations based on this. Set to `Deterministic.no` otherwise.

    See_Also: $(LINK http://www.sqlite.org/c3ref/create_function.html).
    +/
    void createAggregate(T)(string name, T agg, Deterministic det = Deterministic.yes)
    {
        static assert(isAggregateType!T,
            T.stringof ~ " should be an aggregate type");
        static assert(is(typeof(T.accumulate) == function),
            T.stringof ~ " should have a method named accumulate");
        static assert(is(typeof(T.result) == function),
            T.stringof ~ " should have a method named result");
        static assert(is(typeof({
                alias RT = ReturnType!(T.result);
                setResult!RT(null, RT.init);
            })),
            T.stringof ~ ".result should return an SQLite-compatible type");
        static assert(variadicFunctionStyle!(T.accumulate) == Variadic.no,
            "variadic functions are not supported");
        static assert(variadicFunctionStyle!(T.result) == Variadic.no,
            "variadic functions are not supported");

        alias staticMap!(Unqual, ParameterTypeTuple!(T.accumulate)) PT;
        alias ReturnType!(T.result) RT;

        static struct Context
        {
            T aggregate;
            string functionName;
        }

        extern(C) static
        void x_step(sqlite3_context* context, int argc, sqlite3_value** argv)
        {
            auto ctx = cast(Context*) sqlite3_user_data(context);
            if (!ctx)
            {
                sqlite3_result_error_nomem(context);
                return;
            }

            PT args;
            try
            {
                foreach (i, type; PT)
                    args[i] = getValue!type(argv[i]);
                
                ctx.aggregate.accumulate(args);
            }
            catch (Exception e)
            {
                auto txt = "error in aggregate function %s(): %s".format(ctx.functionName, e.msg);
                sqlite3_result_error(context, txt.toStringz, -1);
            }
        }

        extern(C) static
        void x_final(sqlite3_context* context)
        {
            auto ctx = cast(Context*) sqlite3_user_data(context);
            if (!ctx)
            {
                sqlite3_result_error_nomem(context);
                return;
            }

            try
                setResult(context, ctx.aggregate.result());
            catch (Exception e)
            {
                auto txt = "error in aggregate function %s(): %s".format(ctx.functionName, e.msg);
                sqlite3_result_error(context, txt.toStringz, -1);
            }
        }

        static if (is(T == class) || is(T == Interface))
            enforce(agg, "Attempt to create an aggregate function from a null reference");

        auto ctx = cast(Context*) malloc(Context.sizeof);
        ctx.aggregate = agg;
        ctx.functionName = name;

        assert(p.handle);
        check(sqlite3_create_function_v2(p.handle, name.toStringz, PT.length, SQLITE_UTF8 | det,
            cast(void*) ctx, null, &x_step, &x_final, &ptrFree));
    }
    ///
    unittest // Aggregate creation
    {
        import std.array : appender, join;

        // The implementation of the aggregate function
        struct Joiner
        {
            private
            {
                Appender!(string[]) stringList;
                string separator;
            }

            this(string separator)
            {
                this.separator = separator;
            }

            void accumulate(string word)
            {
                stringList.put(word);
            }

            string result()
            {
                return stringList.data.join(separator);
            }
        }

        auto db = Database(":memory:");
        db.run("CREATE TABLE test (word TEXT);
                INSERT INTO test VALUES ('My');
                INSERT INTO test VALUES ('cat');
                INSERT INTO test VALUES ('is');
                INSERT INTO test VALUES ('black');");

        db.createAggregate("dash_join", Joiner("-"));
        auto text = db.execute("SELECT dash_join(word) FROM test").oneValue!string;
        assert(text == "My-cat-is-black");
    }

    deprecated("Kept for compatibility. Use of the new createAggregate method is recommended.")
    {
        alias createAggregate(T, string name) = createAggregate!(name, T);
        void createAggregate(string name, T)(Deterministic det = Deterministic.yes)
        {
            createAggregate(name, new T, det);
        }
    }

    /++
    Creates and registers a collation function in the database.

    Params:
        name = The name that the function will have in the database.

        fun = a delegate or function that implements the collation. The function $(D_PARAM fun)
        must satisfy these criteria:
            $(UL
                $(LI Takes two string arguments (s1 and s2). )
                $(LI Returns an integer (ret). )
                $(LI If s1 is less than s2, ret < 0.)
                $(LI If s1 is equal to s2, ret == 0.)
                $(LI If s1 is greater than s2, ret > 0.)
                $(LI If s1 is equal to s2, then s2 is equal to s1.)
                $(LI If s1 is equal to s2 and s2 is equal to s3, then s1 is equal to s3.)
                $(LI If s1 is less than s2, then s2 is greater than s1.)
                $(LI If s1 is less than s2 and s2 is less than s3, then s1 is less than s3.)
            )

    See_Also: $(LINK http://www.sqlite.org/lang_aggfunc.html)
    +/
    void createCollation(T)(string name, T fun)
        if (isFunctionPointer!T || isDelegate!T)
    {
        static assert(isImplicitlyConvertible!(typeof(fun("a", "b")), int),
            "the collation function has a wrong signature");

        alias ParameterTypeTuple!fun PT;
        static assert(isSomeString!(PT[0]),
            "the first argument of function " ~ name ~ " should be a string");
        static assert(isSomeString!(PT[1]),
            "the second argument of function " ~ name ~ " should be a string");
        static assert(isImplicitlyConvertible!(ReturnType!fun, int),
            "function " ~ name ~ " should return a value convertible to an int");

        extern (C) static
        int x_compare(void* ptr, int n1, const(void)* str1, int n2, const(void)* str2)
        {
            auto dg = delegateUnwrap!T(ptr).dlg;
            char[] s1, s2;
            s1.length = n1;
            s2.length = n2;
            memcpy(s1.ptr, str1, n1);
            memcpy(s2.ptr, str2, n2);
            return dg(cast(immutable) s1, cast(immutable) s2);
        }

        assert(p.handle);
        check(sqlite3_create_collation_v2(p.handle, name.toStringz, SQLITE_UTF8,
            delegateWrap(fun, name), &x_compare, &ptrFree));
    }
    ///
    unittest // Collation creation
    {
        // The implementation of the collation
        int my_collation(string s1, string s2)
        {
            import std.uni;
            return icmp(s1, s2);
        }

        auto db = Database(":memory:");
        db.createCollation("my_coll", &my_collation);
        db.run("CREATE TABLE test (word TEXT);
                INSERT INTO test (word) VALUES ('straße');
                INSERT INTO test (word) VALUES ('strasses');");

        auto word = db.execute("SELECT word FROM test ORDER BY word COLLATE my_coll")
                      .oneValue!string;
        assert(word == "straße");
    }

    /++
    Registers a delegate as the database's update hook.
    
    Any previously set hook is released.
    Pass `null` to disable the callback.

    See_Also: $(LINK http://www.sqlite.org/c3ref/commit_hook.html).
    +/
    void setUpdateHook(void delegate(int type, string dbName, string tableName, long rowid) updateHook)
    {
        extern(C) static
        void callback(void* ptr, int type, char* dbName, char* tableName, long rowid)
        {
            auto dlg = delegateUnwrap!(void delegate(int, string, string, long))(ptr).dlg;
            return dlg(type, dbName.to!string, tableName.to!string, rowid);
        }

        ptrFree(p.updateHook);
        p.updateHook = delegateWrap(updateHook);
        sqlite3_update_hook(p.handle, &callback, p.updateHook);
    }

    unittest
    {
        int i;
        auto db = Database(":memory:");
        db.setUpdateHook((int type, string dbName, string tableName, long rowid) {
            assert(type == SQLITE_INSERT);
            assert(dbName == "main");
            assert(tableName == "test");
            assert(rowid == 1);
            i = 42;
        });
        db.run("CREATE TABLE test (val INTEGER);
                INSERT INTO test VALUES (100)");
        assert(i == 42);
        db.setUpdateHook(null);
    }

    /++
    Registers a delegate as the database's commit hook.
    Any previously set hook is released.

    Params:
        commitHook = A delegate that should return a non-zero value
        if the operation must be rolled back, or 0 if it can commit.
        Pass `null` to disable the callback.

    See_Also: $(LINK http://www.sqlite.org/c3ref/commit_hook.html).
    +/
    void setCommitHook(int delegate() commitHook)
    {
        extern(C) static int callback(void* ptr)
        {
            auto dlg = delegateUnwrap!(int delegate())(ptr).dlg; 
            return dlg();
        }

        ptrFree(p.commitHook);
        p.commitHook = delegateWrap(commitHook);
        sqlite3_commit_hook(p.handle, &callback, p.commitHook);
    }

    /++
    Registers a delegate as the database's rollback hook.
    
    Any previously set hook is released.
    Pass `null` to disable the callback.

    See_Also: $(LINK http://www.sqlite.org/c3ref/commit_hook.html).
    +/
    void setRollbackHook(void delegate() rollbackHook)
    {
        extern(C) static void callback(void* ptr)
        {
            auto dlg = delegateUnwrap!(void delegate())(ptr).dlg; 
            dlg();
        }

        ptrFree(p.rollbackHook);
        p.rollbackHook = delegateWrap(rollbackHook);
        sqlite3_rollback_hook(p.handle, &callback, p.rollbackHook);
    }

    unittest
    {
        int i;
        auto db = Database(":memory:");
        db.setCommitHook({ i = 42; return SQLITE_OK; });
        db.setRollbackHook({ i = 666; });
        db.begin();
        db.execute("CREATE TABLE test (val INTEGER)");
        db.rollback();
        assert(i == 666);
        db.begin();
        db.execute("CREATE TABLE test (val INTEGER)");
        db.commit();
        assert(i == 42);
        db.setCommitHook(null);
        db.setRollbackHook(null);
    }

    /++
    Sets the progress handler.
    
    Any previously set handler is released.
    Pass `null` to disable the callback.

    Params:
        pace = The approximate number of virtual machine instructions that are
        evaluated between successive invocations of the handler.

        progressHandler = A delegate that should return 0 if the operation can continue
        or another value if it must be aborted.

    See_Also: $(LINK http://www.sqlite.org/c3ref/progress_handler.html).
    +/
    void setProgressHandler(int pace, int delegate() progressHandler)
    {
        extern(C) static int callback(void* ptr)
        {
            auto dlg = delegateUnwrap!(int delegate())(ptr).dlg; 
            return dlg();
        }

        ptrFree(p.progressHandler);
        p.progressHandler = delegateWrap(progressHandler);
        sqlite3_progress_handler(p.handle, pace, &callback, p.progressHandler);
    }

    /++
    Sets the trace callback.
    
    Any previously set trace callback is released.
    Pass `null` to disable the callback.

    The string parameter that is passed to the callback is the SQL text of the statement being 
    executed.

    See_Also: $(LINK http://www.sqlite.org/c3ref/profile.html).
    +/
    void setTraceCallback(void delegate(string sql) traceCallback)
    {
        extern(C) static void callback(void* ptr, const(char)* str)
        {
            auto dlg = delegateUnwrap!(void delegate(string))(ptr).dlg; 
            dlg(str.to!string);
        }

        ptrFree(p.traceCallback);
        p.traceCallback = delegateWrap(traceCallback);
        sqlite3_trace(p.handle, &callback, p.traceCallback);
    }

    /++
    Sets the profile callback.
    
    Any previously set profile callback is released.
    Pass `null` to disable the callback.

    The string parameter that is passed to the callback is the SQL text of the statement being 
    executed. The time unit is defined in SQLite's documentation as nanoseconds (subject to change,
    as the functionality is experimental).

    See_Also: $(LINK http://www.sqlite.org/c3ref/profile.html).
    +/
    void setProfileCallback(void delegate(string sql, ulong time) profileCallback)
    {
        extern(C) static void callback(void* ptr, const(char)* str, sqlite3_uint64 time)
        {
            auto dlg = delegateUnwrap!(void delegate(string, ulong))(ptr).dlg;
            dlg(str.to!string, time);
        }

        ptrFree(p.profileCallback);
        p.profileCallback = delegateWrap(profileCallback);
        sqlite3_profile(p.handle, &callback, p.profileCallback);
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
    assert(db2.p.refCountedStore.refCount == 2);
    assert(db1.p.refCountedStore.refCount == 2);
}

unittest
{
    auto db = Database(":memory:");
    assert(db.attachedFilePath("main") is null);
    assert(!db.isReadOnly);
    db.close();
}

unittest // Execute an SQL statement
{
    auto db = Database(":memory:");
    db.run("");
    db.run("-- This is a comment!");
    db.run(";");
    db.run("ANALYZE; VACUUM;");
}

version (none) unittest // Unexpected multiple statements
{
    auto db = Database(":memory:");
    db.execute("BEGIN; CREATE TABLE test (val INTEGER); ROLLBACK;");
    assertThrown(db.execute("DROP TABLE test"));

    db.execute("CREATE TABLE test (val INTEGER); DROP TABLE test;");
    assertNotThrown(db.execute("DROP TABLE test"));

    db.execute("SELECT 1; CREATE TABLE test (val INTEGER); DROP TABLE test;");
    assertThrown(db.execute("DROP TABLE test"));
}

unittest // Multiple statements with callback
{
    auto db = Database(":memory:");
    QueryCache[] rows;
    db.run("SELECT 1, 2, 3; SELECT 'A', 'B', 'C';", (ResultRange r) {
        rows ~= QueryCache(r);
        return true;
    });
    assert(equal!"a.as!int == b"(rows[0][0], [1, 2, 3]));
    assert(equal!"a.as!string == b"(rows[1][0], ["A", "B", "C"]));
}

unittest // Different arguments and result types with createFunction
{
    import std.math;

    auto db = Database(":memory:");

    T display(T)(T value)
    {
        return value;
    }

    db.createFunction("display_integer", &display!int);
    db.createFunction("display_float", &display!double);
    db.createFunction("display_text", &display!string);
    db.createFunction("display_blob", &display!(ubyte[]));

    assert(db.execute("SELECT display_integer(42)").oneValue!int == 42);
    assert(db.execute("SELECT display_float(3.14)").oneValue!double == 3.14);
    assert(db.execute("SELECT display_text('ABC')").oneValue!string == "ABC");
    assert(db.execute("SELECT display_blob(x'ABCD')").oneValue!(ubyte[]) == cast(ubyte[]) x"ABCD");

    assert(db.execute("SELECT display_integer(NULL)").oneValue!int == 0);
    assert(db.execute("SELECT display_float(NULL)").oneValue!double.isNaN);
    assert(db.execute("SELECT display_text(NULL)").oneValue!string is null);
    assert(db.execute("SELECT display_blob(NULL)").oneValue!(ubyte[]) is null);
}

unittest // Different Nullable argument types with createFunction
{
    import std.math;

    auto db = Database(":memory:");

    auto display(T : Nullable!U, U...)(T value)
    {
        if (value.isNull)
            return T();
        return value;
    }

    db.createFunction("display_integer", &display!(Nullable!int));
    db.createFunction("display_float", &display!(Nullable!double));
    db.createFunction("display_text", &display!(Nullable!string));
    db.createFunction("display_blob", &display!(Nullable!(ubyte[])));

    assert(db.execute("SELECT display_integer(42)").oneValue!(Nullable!int) == 42);
    assert(db.execute("SELECT display_float(3.14)").oneValue!(Nullable!double) == 3.14);
    assert(db.execute("SELECT display_text('ABC')").oneValue!(Nullable!string) == "ABC");
    assert(db.execute("SELECT display_blob(x'ABCD')").oneValue!(Nullable!(ubyte[])) == cast(ubyte[]) x"ABCD");

    assert(db.execute("SELECT display_integer(NULL)").oneValue!(Nullable!int).isNull);
    assert(db.execute("SELECT display_float(NULL)").oneValue!(Nullable!double).isNull);
    assert(db.execute("SELECT display_text(NULL)").oneValue!(Nullable!string).isNull);
    assert(db.execute("SELECT display_blob(NULL)").oneValue!(Nullable!(ubyte[])).isNull);
}

unittest // Callable struct with createFunction
{
    import std.functional : toDelegate;

    struct Fun
    {
        int factor;

        this(int factor)
        {
            this.factor = factor;
        }

        int opCall(int value)
        {
            return value * factor;
        }
    }

    auto f = Fun(2);
    auto db = Database(":memory:");
    db.createFunction("my_fun", toDelegate(f));
    assert(db.execute("SELECT my_fun(4)").oneValue!int == 8);
}

unittest // Callbacks
{
    bool wasTraced = false;
    bool wasProfiled = false;
    bool hasProgressed = false;

    auto db = Database(":memory:");
    db.setTraceCallback((string s) { wasTraced = true; });
    db.setProfileCallback((string s, ulong t) { wasProfiled = true; });
    db.setProgressHandler(1, { hasProgressed = true; return 0; });
    db.execute("SELECT 1;");
    // assert(wasTraced);
    // assert(wasProfiled);
    // assert(hasProgressed);
}


/++
An SQLite statement execution.

This struct is a reference-counted wrapper around a `sqlite3_stmt*` pointer. Instances
of this struct are typically returned by `Database.prepare()`.
+/
struct Statement
{
private:
    struct _Payload
    {
        Database db;
        sqlite3_stmt* handle; // null if error or empty statement

        ~this()
        {
            auto result = sqlite3_finalize(handle);
            enforce(result == SQLITE_OK, new SqliteException(errmsg(handle), result));
            handle = null;
        }

        @disable this(this);
        @disable void opAssign(_Payload);
    }
    alias Payload = RefCounted!(_Payload, RefCountedAutoInitialize.no);
    Payload p;

    this(Database db, string sql)
    {
        sqlite3_stmt* handle;
        const(char)* ptail;
        auto result = sqlite3_prepare_v2(db.handle(), sql.toStringz, sql.length.to!int,
            &handle, null);
        enforce(result == SQLITE_OK, new SqliteException(errmsg(db.handle()), result, sql));
        p = Payload(db, handle);
    }

    void checkResult(int result) 
    {
        enforce(result == SQLITE_OK, new SqliteException(errmsg(p.handle), result));
    }

public:
    /++
    Gets the SQLite internal _handle of the statement.
    +/
    sqlite3_stmt* handle() @property nothrow
    {
        return p.handle;
    }

    /++
    Explicitly finalizes the prepared statement.

    After a call to `finalize()`, the `Statement` object is destroyed and cannot be used.
    +/
    void finalize()
    {
        destroy(p);
    }

    /++
    Tells whether the statement is empty (no SQL statement).
    +/
    bool empty() @property nothrow
    {
        return p.handle is null;
    }
    ///
    unittest
    {
        auto db = Database(":memory:");
        auto statement = db.prepare(" ; ");
        assert(statement.empty);
    }

    /++
    Binds values to parameters of this statement, using parameter index.

    Params:
        index = The index of the parameter (starting from 1).

        value = The bound _value. The type of value must be compatible with the SQLite
        types: it must be a boolean or numeric type, a string, an array, null,
        or a Nullable!T where T is any of the previous types.
    +/
    void bind(T)(int index, T value)
        if (is(T == typeof(null)) || is(T == void*))
    {
        assert(p.handle, "Operation on an empty statement");
        checkResult(sqlite3_bind_null(p.handle, index));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isIntegral!T || isSomeChar!T)
    {
        assert(p.handle, "Operation on an empty statement");
        checkResult(sqlite3_bind_int64(p.handle, index, value.to!long));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isBoolean!T)
    {
        assert(p.handle, "Operation on an empty statement");
        checkResult(sqlite3_bind_int(p.handle, index, value.to!T));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isFloatingPoint!T)
    {
        assert(p.handle, "Operation on an empty statement");
        checkResult(sqlite3_bind_double(p.handle, index, value.to!double));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isSomeString!T)
    {
        assert(p.handle, "Operation on an empty statement");
        string str = value.to!string;
        auto ptr = anchorMem(cast(void*) str.ptr);
        checkResult(sqlite3_bind_text64(p.handle, index, cast(const(char)*) ptr, str.length, &releaseMem, SQLITE_UTF8));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isStaticArray!T)
    {
        assert(p.handle, "Operation on an empty statement");
        checkResult(sqlite3_bind_blob64(p.handle, index, cast(void*) value.ptr, value.sizeof, SQLITE_TRANSIENT));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (isDynamicArray!T && !isSomeString!T)
    {
        assert(p.handle, "Operation on an empty statement");
        auto arr = cast(void[]) value;
        checkResult(sqlite3_bind_blob64(p.handle, index, anchorMem(arr.ptr), arr.length, &releaseMem));
    }

    /// ditto
    void bind(T)(int index, T value)
        if (is(T == Nullable!U, U...))
    {
        if (value.isNull)
        {
            assert(p.handle, "Operation on an empty statement");
            checkResult(sqlite3_bind_null(p.handle, index));
        }
        else
            bind(index, value.get);
    }

    /++
    Binds values to parameters of this statement, using parameter names.

    Params:
        name = The name of the parameter, including the ':', '@' or '$' that introduced it.

        value = The bound _value. The type of value must be compatible with the SQLite
        types: it must be a boolean or numeric type, a string, an array, null,
        or a Nullable!T where T is any of the previous types.

    Warning:
        While convenient, this overload of `bind` is less performant, because it has to
        retrieve the column index with a call to the SQLite function
        `sqlite3_bind_parameter_index`.
    +/
    void bind(T)(string name, T value)
    {
        auto index = sqlite3_bind_parameter_index(p.handle, name.toStringz);
        enforce(index > 0, new SqliteException(format("no parameter named '%s'", name)));
        bind(index, value);
    }

    /++
    Binds all the arguments at once in order.
    +/
    void bindAll(Args...)(Args args)
    {
        foreach (index, _; Args)
            bind(index + 1, args[index]);
    }

    /++
    Clears the bindings.

    This does not reset the statement. Use `Statement.reset()` for this.
    +/
    void clearBindings()
    {
        assert(p.handle, "Operation on an empty statement");
        checkResult(sqlite3_clear_bindings(p.handle));
    }

    /++
    Executes the statement and return a (possibly empty) range of results.
    +/
    ResultRange execute()
    {
        return ResultRange(this);
    }

    /++
    Resets a this statement before a new execution.

    Calling this method invalidates any `ResultRange` struct returned by a previous call
    to `Database.execute()` or `Statement.execute()`.

    This does not clear the bindings. Use `Statement.clearBindings()` for this.
    +/
    void reset()
    {
        assert(p.handle, "Operation on an empty statement");
        checkResult(sqlite3_reset(p.handle));
    }

    /++
    Binds arguments, executes and resets the statement, in one call.

    This convenience function is equivalent to:
    ---
    bindAll(args);
    execute();
    reset();
    ---
    +/
    void inject(Args...)(Args args)
        if (!is(Args[0] == struct))
    {
        bindAll(args);
        execute();
        reset();
    }

    /++
    Binds the fields of a struct in order, executes and resets the statement, in one call.
    +/
    void inject(T)(ref const(T) obj)
        if (is(T == struct))
    {
        // Copy of FieldNameTuple, as long as GDC doesn't have it.
        alias FieldNames = staticMap!(NameOf, T.tupleof[0 .. $ - isNested!T]);

        foreach (i, field; FieldNames)
            bind(i + 1, __traits(getMember, obj, field));
        execute();
        reset();
    }

    /// Gets the count of bind parameters.
    int parameterCount() nothrow
    {
        assert(p.handle, "Operation on an empty statement");
        return sqlite3_bind_parameter_count(p.handle);
    }

    /++
    Gets the name of the bind parameter at the given index.

    Params:
        index = The index of the parameter (the first parameter has the index 1).

    Returns: The name of the parameter or null is not found or out of range.
    +/
    string parameterName(int index)
    {
        assert(p.handle, "Operation on an empty statement");
        return sqlite3_bind_parameter_name(p.handle, index).to!string;
    }

    /++
    Gets the index of a bind parameter.

    Returns: The index of the parameter (the first parameter has the index 1)
    or 0 is not found or out of range.
    +/
    int parameterIndex(string name)
    {
        assert(p.handle, "Operation on an empty statement");
        return sqlite3_bind_parameter_index(p.handle, name.toStringz);
    }
}

unittest
{
    Statement statement;
    {
        auto db = Database(":memory:");
        statement = db.prepare(" SELECT 42 ");
    }
    assert(statement.execute.oneValue!int == 42);
}

unittest
{
    auto db = Database(":memory:");
    auto statement = db.prepare(" SELECT 42 ");
    statement.finalize();
}

unittest // Simple parameters binding
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");

    auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
    statement.bind(1, 36);
    statement.clearBindings();
    statement.bind(1, 42);
    statement.execute();
    statement.reset();
    statement.bind(1, 42);
    statement.execute();

    assert(db.lastInsertRowid == 2);
    assert(db.changes == 1);
    assert(db.totalChanges == 2);

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
        assert(row.peek!int(0) == 42);
}

unittest // Multiple parameters binding
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto statement = db.prepare("INSERT INTO test (i, f, t) VALUES (:i, @f, $t)");

    assert(statement.parameterCount == 3);
    assert(statement.parameterName(2) == "@f");
    assert(statement.parameterName(4) == null);
    assert(statement.parameterIndex("$t") == 3);
    assert(statement.parameterIndex(":foo") == 0);

    statement.bind("$t", "TEXT");
    statement.bind(":i", 42);
    statement.bind("@f", 3.14);
    statement.execute();
    statement.reset();
    statement.bind(1, 42);
    statement.bind(2, 3.14);
    statement.bind(3, "TEXT");
    statement.execute();

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
    {
        assert(row.length == 3);
        assert(row.peek!int("i") == 42);
        assert(row.peek!double("f") == 3.14);
        assert(row.peek!string("t") == "TEXT");
    }
}

unittest // Multiple parameters binding: tuples
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto statement = db.prepare("INSERT INTO test (i, f, t) VALUES (?, ?, ?)");
    statement.bindAll(42, 3.14, "TEXT");
    statement.execute();

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
    {
        assert(row.length == 3);
        assert(row.peek!int(0) == 42);
        assert(row.peek!double(1) == 3.14);
        assert(row.peek!string(2) == "TEXT");
    }
}

unittest // Struct injecting
{
    static struct Test
    {
        int i;
        double f;
        string t;
    }

    auto test = Test(42, 3.14, "TEXT");

    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (i INTEGER, f FLOAT, t TEXT)");
    auto statement = db.prepare("INSERT INTO test (i, f, t) VALUES (?, ?, ?)");
    statement.inject(test);
    
    auto results = db.execute("SELECT * FROM test");
    assert(!results.empty);
    foreach (row; results)
    {
        assert(row.length == 3);
        assert(row.peek!int(0) == 42);
        assert(row.peek!double(1) == 3.14);
        assert(row.peek!string(2) == "TEXT");
    }
}

unittest // Static array binding
{
    ubyte[3] data = [1,2,3];

    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (a BLOB)");
    auto statement = db.prepare("INSERT INTO test (a) VALUES (?)");
    statement.bind(1, data);
    statement.execute();

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
    {
        assert(row.length == 1);
        auto rdata = row.peek!(ubyte[])(0);
        assert(rdata.length == 3);
        assert(rdata[0] == 1);
        assert(rdata[1] == 2);
        assert(rdata[2] == 3);
    }
}

unittest // Nullable binding
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (a, b, c, d, e);");

    auto statement = db.prepare("INSERT INTO test (a,b,c,d,e) VALUES (?,?,?,?,?)");
    statement.bind(1, Nullable!int(123));
    statement.bind(2, Nullable!int());
    statement.bind(3, Nullable!(uint, 0)(42));
    statement.bind(4, Nullable!(uint, 0)());
    statement.bind(5, Nullable!bool(false));
    statement.execute();

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
    {
        assert(row.length == 5);
        assert(row.peek!int(0) == 123);
        assert(row.columnType(1) == SqliteType.NULL);
        assert(row.peek!int(2) == 42);
        assert(row.columnType(3) == SqliteType.NULL);
        assert(!row.peek!bool(4));
    }
}

unittest // Nullable peek
{
    auto db = Database(":memory:");
    auto results = db.execute("SELECT 1, NULL, 8.5, NULL");
    foreach (row; results)
    {
        assert(row.length == 4);
        assert(row.peek!(Nullable!double)(2).get == 8.5);
        assert(row.peek!(Nullable!double)(3).isNull);
        assert(row.peek!(Nullable!(int, 0))(0).get == 1);
        assert(row.peek!(Nullable!(int, 0))(1).isNull);
    }
}

unittest // Bad bindings
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER)");
    auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
    assertThrown!SqliteException(statement.bind("foo", 1));
    assertThrown!SqliteException(statement.bindAll(10, 11));
}

unittest // GC anchoring test
{
    auto db = Database(":memory:");
    auto stmt = db.prepare("SELECT ?");

    auto str = ("I am test string").dup;
    stmt.bind(1, str);
    str = null;

    for(int i=0; i<3; i++) {
        GC.collect();
        GC.minimize();
    }

    ResultRange results = stmt.execute();
    foreach(row; results) {
        assert(row.length == 1);
        assert(row.peek!string(0) == "I am test string");
    }
}


/++
An input range interface to access the rows resulting from an SQL query.

The elements of the range are `Row` structs. A `Row` is just a view of the current
row when iterating the results of a `ResultRange`. It becomes invalid as soon as 
`ResultRange.popFront()` is called (it contains undefined data afterwards). Use
`QueryCache` to store the content of rows past the execution of the statement.

Instances of this struct are typically returned by `Database.execute()` or
`Statement.execute()`.
+/
struct ResultRange
{
private:
    struct _Payload
    {
        Statement statement;
        int state;

        @disable this(this);
        @disable void opAssign(_Payload);
    }
    alias Payload = RefCounted!(_Payload, RefCountedAutoInitialize.no);
    Payload p;

    this(Statement statement)
    {
        p = Payload(statement);
        if (!p.statement.empty)
            p.state = sqlite3_step(p.statement.handle);
        else
            p.state = SQLITE_DONE;

        enforce(p.state == SQLITE_ROW || p.state == SQLITE_DONE,
                new SqliteException(errmsg(p.statement.handle), p.state));
    }

public:
    /++
    Range interface.
    +/
    bool empty() @property
    {
        assert(p.state);
        return p.state == SQLITE_DONE;
    }

    /// ditto
    Row front() @property
    {
        assert(p.state);
        enforce(!empty, new SqliteException("No rows available"));
        return Row(p.statement);
    }

    /// ditto
    void popFront()
    {
        assert(p.state);
        enforce(!empty, new SqliteException("No rows available"));
        p.state = sqlite3_step(p.statement.handle);
        enforce(p.state == SQLITE_DONE || p.state == SQLITE_ROW, new SqliteException(errmsg(p.statement.handle), p.state));
    }

    /++
    Gets only the first value of the first row returned by the execution of the statement.
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
        auto count = db.execute("SELECT count(*) FROM test").oneValue!long;
        assert(count == 0);
    }
}

unittest // Statement error
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val INTEGER NOT NULL)");
    auto stmt = db.prepare("INSERT INTO test (val) VALUES (?)");
    stmt.bind(1, null);
    assertThrown!SqliteException(stmt.execute());
}

/++
A row returned when stepping over an SQLite prepared statement.

The data of each column can be retrieved:
$(UL
    $(LI using Row as a random-access range of ColumnData.)
    $(LI using the more direct peek functions.)
)

Warning:
    The data of the row is invalid when the next row is accessed (after a call to
    `ResultRange.popFront()`).
+/
struct Row
{
    private
    {
        Statement statement;
        int frontIndex;
        int backIndex;
    }

    this(Statement statement)
    {
        this.statement = statement;
        backIndex = sqlite3_column_count(statement.handle) - 1;
    }

    /// Range interface.
    bool empty() @property nothrow
    {
        return length == 0;
    }

    /// ditto
    ColumnData front() @property
    {
        return opIndex(0);
    }

    /// ditto
    void popFront() nothrow
    {
        frontIndex++;
    }

    /// ditto
    Row save() @property
    {
        return this;
    }

    /// ditto
    ColumnData back() @property
    {
        return opIndex(backIndex - frontIndex);
    }

    /// ditto
    void popBack() nothrow
    {
        backIndex--;
    }

    /// ditto
    int length() @property nothrow
    {
        return backIndex - frontIndex + 1;
    }

    /// ditto
    ColumnData opIndex(int index)
    {
        auto i = internalIndex(index);

        auto type = sqlite3_column_type(statement.handle, i);

        final switch (type)
        {
            case SqliteType.INTEGER:
                return ColumnData(peek!long(index));

            case SqliteType.FLOAT:
                return ColumnData(peek!double(index));

            case SqliteType.TEXT:
                return ColumnData(peek!string(index));

            case SqliteType.BLOB:
                return ColumnData(peek!(ubyte[], PeekMode.copy)(index));

            case SqliteType.NULL:
                return ColumnData(null);
        }
    }

    /// Ditto
    ColumnData opIndex(string columnName)
    {
        return opIndex(indexForName(columnName));
    }

    /++
    Returns the data of a column directly.

    Contrary to `opIndex`, the `peek` functions return the data directly, automatically cast to T,
    without the overhead of using a wrapping type (`ColumnData`).

    When using `peek` to retrieve a BLOB, you can use either:
        $(UL
            $(LI `peek!(ubyte[], PeekMode.copy)(index)`,
              in which case the function returns a copy of the data that will outlive the step
              to the next row,
            or)
            $(LI `peek!(ubyte[], PeekMode.slice)(index)`,
              in which case a slice of SQLite's internal buffer is returned (see Warnings).)
        )

    Params:
        T = The type of the returned data. T must be a boolean, a built-in numeric type, a
        string, an array or a `Nullable`.
        $(TABLE
            $(TR
                $(TH Condition on T)
                $(TH Requested database type)
            )
            $(TR
                $(TD `isIntegral!T || isBoolean!T`)
                $(TD INTEGER)
            )
            $(TR
                $(TD `isFloatingPoint!T`)
                $(TD FLOAT)
            )
            $(TR
                $(TD `isSomeString!T`)
                $(TD TEXT)
            )
            $(TR
                $(TD `isArray!T`)
                $(TD BLOB)
            )
            $(TR
                $(TD `is(T == Nullable!U, U...)`)
                $(TD NULL or U)
            )
        )

        index = The index of the column in the prepared statement or
        the name of the column, as specified in the prepared statement
        with an AS clause. The index of the first column is 0.

    Returns:
        A value of type T. The returned value is T.init if the data type is NULL.
        In all other cases, the data is fetched from SQLite (which returns a value
        depending on its own conversion rules;
        see $(LINK http://www.sqlite.org/c3ref/column_blob.html) and
        $(LINK http://www.sqlite.org/lang_expr.html#castexpr)), and it is converted
        to T using `std.conv.to!T`.

    Warnings:
        When using `PeekMode.slice`, the data of the slice will be $(B invalidated)
        when the next row is accessed. A copy of the data has to be made somehow for it to 
        outlive the next step on the same statement.

        When using referring to the column by name, the names of all the columns are
        tested each time this function is called: use
        numeric indexing for better performance.
    +/
    T peek(T)(int index)
        if (isBoolean!T || isIntegral!T)
    {
        return sqlite3_column_int64(statement.handle, internalIndex(index)).to!T();
    }

    /// ditto
    T peek(T)(int index)
        if (isFloatingPoint!T)
    {
        auto i = internalIndex(index);
        if (sqlite3_column_type(statement.handle, i) == SqliteType.NULL)
            return T.init;
        return sqlite3_column_double(statement.handle, i).to!T();
    }

    /// ditto
    T peek(T)(int index)
        if (isSomeString!T)
    {
        return sqlite3_column_text(statement.handle, internalIndex(index)).to!T;
    }

    /// ditto
    T peek(T, PeekMode mode = PeekMode.copy)(int index)
        if (isArray!T && !isSomeString!T)
    {
        auto i = internalIndex(index);
        auto ptr = sqlite3_column_blob(statement.handle, i);
        auto length = sqlite3_column_bytes(statement.handle, i);

        static if (mode == PeekMode.copy)
        {
            ubyte[] blob;
            blob.length = length;
            memcpy(blob.ptr, ptr, length);
            return cast(T) blob;
        }
        else static if (mode == PeekMode.slice)
            return cast(T) ptr[0..length];
        else
            static assert(false);
    }

    /// ditto
    T peek(T)(int index)
        if (isInstanceOf!(Nullable, T)
            && (!isArray!(TemplateArgsOf!T[0]) || isSomeString!(TemplateArgsOf!T[0])))
    {
        alias U = TemplateArgsOf!T[0];
        if (sqlite3_column_type(statement.handle, internalIndex(index)) == SqliteType.NULL)
            return T();
        return T(peek!U(index));
    }

    /// ditto
    T peek(T, PeekMode mode = PeekMode.copy)(int index)
        if (isInstanceOf!(Nullable, T)
            && isArray!(TemplateArgsOf!T[0]) && !isSomeString!(TemplateArgsOf!T[0]))
    {
        alias U = TemplateArgsOf!T[0];
        if (sqlite3_column_type(statement.handle, internalIndex(index)) == SqliteType.NULL)
            return T();
        return T(peek!(U, mode)(index));
    }

    /// ditto
    T peek(T)(string columnName)
    {
        return peek!T(indexForName(columnName));
    }

    /++
    Determines the type of the data in a particular column.

    `columnType` returns the type of the actual data in that column, whereas
    `columnDeclaredTypeName` returns the name of the type as declared in the SELECT statement.

    See_Also: $(LINK http://www.sqlite.org/c3ref/column_blob.html) and
    $(LINK http://www.sqlite.org/c3ref/column_decltype.html).
    +/
    SqliteType columnType(int index)
    {
        return cast(SqliteType) sqlite3_column_type(statement.handle, internalIndex(index));
    }
    /// Ditto
    SqliteType columnType(string columnName)
    {
        return columnType(indexForName(columnName));
    }
    /// Ditto
    string columnDeclaredTypeName(int index)
    {
        return sqlite3_column_decltype(statement.handle, internalIndex(index)).to!string;
    }
    /// Ditto
    string columnDeclaredTypeName(string columnName)
    {
        return columnDeclaredTypeName(indexForName(columnName));
    }
    ///
    unittest
    {
        auto db = Database(":memory:");
        db.run("CREATE TABLE items (name TEXT, price REAL);
                INSERT INTO items VALUES ('car', 20000);
                INSERT INTO items VALUES ('air', 'free');");
        
        auto results = db.execute("SELECT name, price FROM items");

        auto row = results.front;
        assert(row.columnType(0) == SqliteType.TEXT);
        assert(row.columnType("price") == SqliteType.FLOAT);
        assert(row.columnDeclaredTypeName(0) == "TEXT");
        assert(row.columnDeclaredTypeName("price") == "REAL");

        results.popFront();
        row = results.front;
        assert(row.columnType(0) == SqliteType.TEXT);
        assert(row.columnType("price") == SqliteType.TEXT);
        assert(row.columnDeclaredTypeName(0) == "TEXT");
        assert(row.columnDeclaredTypeName("price") == "REAL");
    }

    /++
    Determines the name of a particular column.

    See_Also: $(LINK http://www.sqlite.org/c3ref/column_name.html).
    +/
    string columnName(int index)
    {
        return sqlite3_column_name(statement.handle, internalIndex(index)).to!string;
    }
    ///
    unittest
    {
        auto db = Database(":memory:");
        db.run("CREATE TABLE items (name TEXT, price REAL);
                INSERT INTO items VALUES ('car', 20000);");
        
        auto row = db.execute("SELECT name, price FROM items").front;
        assert(row.columnName(1) == "price");
    }

    version (SQLITE_ENABLE_COLUMN_METADATA)
    {
        /++
        Determines the name of the database, table, or column that is the origin of a
        particular result column in SELECT statement.

        These methods are defined only when the library is compiled with
        `-version=SQLITE_ENABLE_COLUMN_METADATA`.

        See_Also: $(LINK http://www.sqlite.org/c3ref/column_database_name.html).
        +/
        string columnDatabaseName(int index)
        {
            return sqlite3_column_database_name(statement.handle, internalIndex(index)).to!string;
        }
        /// Ditto
        string columnDatabaseName(string columnName)
        {
            return columnDatabaseName(indexForName(columnName));
        }
        /// Ditto
        string columnTableName(int index)
        {
            return sqlite3_column_database_name(statement.handle, internalIndex(index)).to!string;
        }
        /// Ditto
        string columnTableName(string columnName)
        {
            return columnTableName(indexForName(columnName));
        }
        /// Ditto
        string columnOriginName(int index)
        {
            return sqlite3_column_origin_name(statement.handle, internalIndex(index)).to!string;
        }
        /// Ditto
        string columnOriginName(string columnName)
        {
            return columnOriginName(indexForName(columnName));
        }
    }

    /++
    Returns a struct with field members populated from the row's data.

    Neither the names of the fields nor the names of the columns are used on checked. The fields
    are filled with the columns' data in order. Thus, the order of the struct members must be the
    same as the order of the columns in the prepared statement.

    SQLite's conversion rules will be used. For instance, if a string field has the same rank
    as an INTEGER column, the field's data will be the string representation of the integer.
    +/
    T as(T)()
        if (is(T == struct))
    {
        // Copy of FieldNameTuple, as long as GDC doesn't have it.
        alias FieldNames = staticMap!(NameOf, T.tupleof[0 .. $ - isNested!T]);

        alias FieldTypes = FieldTypeTuple!T;

        T obj;
        foreach (i, fieldName; FieldNames)
            __traits(getMember, obj, fieldName) = peek!(FieldTypes[i])(i);
        return obj;
    }
    ///
    unittest
    {
        struct Item
        {
            int _id;
            string name;
        }

        auto db = Database(":memory:");
        db.run("CREATE TABLE items (name TEXT);
                INSERT INTO items VALUES ('Light bulb')");

        auto results = db.execute("SELECT rowid AS id, name FROM items");
        auto row = results.front;
        auto thing = row.as!Item();

        assert(thing == Item(1, "Light bulb"));
    }

private:
    int internalIndex(int index)
    {
        auto i = index + frontIndex;
        enforce(i >= 0 && i <= backIndex,
            new SqliteException(format("invalid column index: %d", i)));
        return i;
    }

    int indexForName(string name)
    {
        foreach (i; frontIndex .. backIndex + 1)
            if (sqlite3_column_name(statement.handle, i).to!string == name)
                return i;

        throw new SqliteException("invalid column name: '%s'".format(name));
    }
}

/// Behavior of the `Row.peek()` method for arrays
enum PeekMode
{
    copy, /// Return a copy of the data into a new array
    slice /// Return a slice of the data
}

version (unittest)
{
    static assert(isRandomAccessRange!Row);
    static assert(is(ElementType!Row == ColumnData));
}

unittest // Peek
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (value);
            INSERT INTO test VALUES (NULL);
            INSERT INTO test VALUES (42);
            INSERT INTO test VALUES (3.14);
            INSERT INTO test VALUES ('ABC');
            INSERT INTO test VALUES (x'DEADBEEF');");

    import std.math : isNaN;
    auto results = db.execute("SELECT * FROM test");
    auto row = results.front;
    assert(row.peek!long(0) == 0);
    assert(row.peek!double(0).isNaN);
    assert(row.peek!string(0) is null);
    assert(row.peek!(ubyte[])(0) is null);
    results.popFront();
    row = results.front;
    assert(row.peek!long(0) == 42);
    assert(row.peek!double(0) == 42);
    assert(row.peek!string(0) == "42");
    assert(row.peek!(ubyte[])(0) == cast(ubyte[]) "42");
    results.popFront();
    row = results.front;
    assert(row.peek!long(0) == 3);
    assert(row.peek!double(0) == 3.14);
    assert(row.peek!string(0) == "3.14");
    assert(row.peek!(ubyte[])(0) == cast(ubyte[]) "3.14");
    results.popFront();
    row = results.front;
    assert(row.peek!long(0) == 0);
    assert(row.peek!double(0) == 0.0);
    assert(row.peek!string(0) == "ABC");
    assert(row.peek!(ubyte[])(0) == cast(ubyte[]) "ABC");
    results.popFront();
    row = results.front;
    assert(row.peek!long(0) == 0);
    assert(row.peek!double(0) == 0.0);
    assert(row.peek!string(0) == x"DEADBEEF");
    assert(row.peek!(ubyte[])(0) == cast(ubyte[]) x"DEADBEEF");
}

unittest // Row life-time
{
    auto db = Database(":memory:");
    auto row = db.execute("SELECT 1 AS one").front;
    assert(row[0].as!long == 1);
    assert(row["one"].as!long == 1);
}

unittest // Bad column index
{
    auto db = Database(":memory:");
    auto row = db.execute("SELECT 1 AS one").front;
    assertThrown!SqliteException(row[1].as!long);
    assertThrown!SqliteException(row["two"].as!long);
}

unittest // PeekMode
{
    alias Blob = ubyte[];

    auto db = Database(":memory:");
    db.run("CREATE TABLE test (value);
            INSERT INTO test VALUES (x'01020304');
            INSERT INTO test VALUES (x'0A0B0C0D');");

    auto results = db.execute("SELECT * FROM test");
    auto row = results.front;
    auto b1 = row.peek!(Blob, PeekMode.copy)(0);
    auto b2 = row.peek!(Blob, PeekMode.slice)(0);
    results.popFront();
    row = results.front;
    auto b3 = row.peek!(Blob, PeekMode.slice)(0);
    auto b4 = row.peek!(Nullable!Blob, PeekMode.copy)(0);
    assert(b1 == cast(Blob) x"01020304");
    // assert(b2 != cast(Blob) x"01020304"); // PASS if SQLite reuses internal buffer
    // assert(b2 == cast(Blob) x"0A0B0C0D"); // PASS (idem)
    assert(b3 == cast(Blob) x"0A0B0C0D");
    assert(!b4.isNull && b4 == cast(Blob) x"0A0B0C0D");
}

unittest // Row random-access range interface
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (a INTEGER, b INTEGER, c INTEGER, d INTEGER);
        INSERT INTO test VALUES (1, 2, 3, 4);
        INSERT INTO test VALUES (5, 6, 7, 8);");

    {
        auto results = db.execute("SELECT * FROM test");
        auto values = [1, 2, 3, 4, 5, 6, 7, 8];
        foreach (row; results)
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
        auto results = db.execute("SELECT * FROM test");
        auto values = [4, 3, 2, 1, 8, 7, 6, 5];
        foreach (row; results)
        {
            while (!row.empty)
            {
                assert(row.back.as!int == values.front);
                row.popBack();
                values.popFront();
            }
        }
    }

    {
        auto row = db.execute("SELECT * FROM test").front;
        row.popFront();
        auto copy = row.save();
        row.popFront();
        assert(row.front.as!int == 3);
        assert(copy.front.as!int == 2);
    }
}


/++
Some data retrieved from a column.
+/
struct ColumnData
{
    import std.variant : Algebraic, VariantException;

    alias SqliteVariant = Algebraic!(long, double, string, ubyte[], typeof(null));

    private
    {
        SqliteVariant _value;
        SqliteType _type;
    }

    /++
    Creates a new `ColumnData` from the value.
    +/
    this(T)(inout T value) inout
        if (isBoolean!T || isIntegral!T)
    {
        _value = SqliteVariant(value.to!long);
        _type = SqliteType.INTEGER;
    }

    /// ditto
    this(T)(T value)
        if (isFloatingPoint!T)
    {
        _value = SqliteVariant(value.to!double);
        _type = SqliteType.FLOAT;
    }

    /// ditto
    this(T)(T value)
        if (isSomeString!T)
    {
        if (value is null)
        {
            _value = SqliteVariant(null);
            _type = SqliteType.NULL;
        }
        else
        {
            _value = SqliteVariant(value.to!string);
            _type = SqliteType.TEXT;
        }
    }

    /// ditto
    this(T)(T value)
        if (isArray!T && !isSomeString!T)
    {
        if (value is null)
        {
            _value = SqliteVariant(null);
            _type = SqliteType.NULL;
        }
        else
        {
            _value = SqliteVariant(value.to!(ubyte[]));
            _type = SqliteType.BLOB;
        }
    }
    /// ditto
    this(T)(T value)
        if (is(T == typeof(null)))
    {
        _value = SqliteVariant(null);
        _type = SqliteType.NULL;
    }

    /++
    Returns the Sqlite type of the column.
    +/
    SqliteType type() const
    {
        return _type;
    }

    /++
    Returns the data converted to T.

    If the data is NULL, defaultValue is returned.
    +/
    auto as(T)(T defaultValue = T.init)
        if (isBoolean!T || isNumeric!T || isSomeString!T)
    {
        if (_type == SqliteType.NULL)
            return defaultValue;

        return _value.coerce!T;
    }

    /// ditto
    auto as(T)(T defaultValue = T.init)
        if (isArray!T && !isSomeString!T)
    {
        if (_type == SqliteType.NULL)
            return defaultValue;

        ubyte[] data;
        try
            data = _value.get!(ubyte[]);
        catch (VariantException e)
            throw new SqliteException("impossible to convert this column to a " ~ T.stringof);

        return cast(T) data;
    }

    /// ditto
    auto as(T : Nullable!U, U...)(T defaultValue = T.init)
    {
        if (_type == SqliteType.NULL)
            return defaultValue;
        
        return T(as!U());
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        if (_type == SqliteType.NULL)
            sink("null");
        else
            sink(_value.toString);
    }
}

unittest // ColumnData-compatible types
{
    alias AllCases = TypeTuple!(bool, true, int, int.max, float, float.epsilon,
        real, 42.0L, string, "おはよう！", const(ubyte)[], [0x00, 0xFF],
        string, "", Nullable!byte, 42);

    void test(Cases...)()
    {
        auto cd = ColumnData(Cases[1]);
        assert(cd.as!(Cases[0]) == Cases[1]);
        static if (Cases.length > 2)
            test!(Cases[2..$])();
    }

    test!AllCases();
}

unittest // ColumnData.toString
{
    auto db = Database(":memory:");
    auto rc = QueryCache(db.execute("SELECT 42, 3.14, 'foo_bar', x'00FF', NULL"));
    assert("%(%s%)".format(rc) == "[42, 3.14, foo_bar, [0, 255], null]");
}

unittest // Integral values
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (val INTEGER)");

    auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
    statement.inject(cast(byte) 42);
    statement.inject(42U);
    statement.inject(42UL);
    statement.inject('\x2A');

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
        assert(row.peek!long(0) == 42);
}

unittest // Floating point values
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (val FLOAT)");

    auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
    statement.inject(42.0F);
    statement.inject(42.0);
    statement.inject(42.0L);
    statement.inject("42");

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
        assert(row.peek!double(0) == 42.0);
}

unittest // Text values
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (val TEXT);
            INSERT INTO test (val) VALUES ('I am a text.')");

    auto results = db.execute("SELECT * FROM test");
    assert(results.front.peek!string(0) == "I am a text.");

    assertThrown!SqliteException(results.front[0].as!(ubyte[]));
}

unittest // Blob values
{
    auto db = Database(":memory:");
    db.execute("CREATE TABLE test (val BLOB)");

    auto statement = db.prepare("INSERT INTO test (val) VALUES (?)");
    ubyte[] array = [1, 2, 3];
    statement.inject(array);
    ubyte[3] sarray = [1, 2, 3];
    statement.inject(sarray);

    auto results = db.execute("SELECT * FROM test");
    foreach (row; results)
    {
        assert(row.peek!(ubyte[])(0) ==  [1, 2, 3]);
        assert(row[0].as!(ubyte[]) == [1, 2, 3]);
    }
}

unittest // Null values
{
    import std.math : isNaN;

    auto db = Database(":memory:");
    db.run("CREATE TABLE test (val TEXT);
            INSERT INTO test (val) VALUES (NULL)");

    auto results = db.execute("SELECT * FROM test");
    assert(results.front.peek!bool(0) == false);
    assert(results.front.peek!long(0) == 0);
    assert(results.front.peek!double(0).isNaN);
    assert(results.front.peek!string(0) is null);
    assert(results.front.peek!(ubyte[])(0) is null);
    assert(results.front[0].as!bool == false);
    /+assert(results.front[0].as!long == 0);
    assert(results.front[0].as!double.isNaN);
    assert(results.front[0].as!string is null);
    assert(results.front[0].as!(ubyte[]) is null);+/
}


/// Information about a column.
struct ColumnMetadata
{
    string declaredTypeName; ///
    string collationSequenceName; ///
    bool isNotNull; ///
    bool isPrimaryKey; ///
    bool isAutoIncrement; ///
}


/++
Caches all the results of a query in memory at once.

Allows to iterate on the rows and their columns with an array-like interface. The rows can
be viewed as an array of `ColumnData` or as an associative array of `ColumnData`
indexed by the column names.
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
                colapp.put(row[i]);
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
    Creates and populates the cache from the results of the statement.
    +/
    this(ResultRange results)
    {
        if (!results.empty)
        {
            auto first = results.front;
            foreach (i; 0 .. first.length)
            {
                auto name = sqlite3_column_name(first.statement.handle, i).to!string;
                columnIndexes[name] = i;
            }
        }

        auto rowapp = appender!(CachedRow[]);
        while (!results.empty)
        {
            rowapp.put(CachedRow(results.front, columnIndexes));
            results.popFront();
        }
        rows = rowapp.data;
    }
}
///
unittest
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (msg TEXT, num FLOAT);
            INSERT INTO test (msg, num) VALUES ('ABC', 123);
            INSERT INTO test (msg, num) VALUES ('DEF', 456);");

    auto results = db.execute("SELECT * FROM test");
    auto data = QueryCache(results);
    assert(data.length == 2);
    assert(data[0].front.as!string == "ABC");
    assert(data[0][1].as!int == 123);
    assert(data[1]["msg"].as!string == "DEF");
    assert(data[1]["num"].as!int == 456);
}

deprecated("Kept for compatibility. Use QueryCache instead.")
alias RowCache = QueryCache;

unittest // QueryCache copies
{
    auto db = Database(":memory:");
    db.run("CREATE TABLE test (msg TEXT);
            INSERT INTO test (msg) VALUES ('ABC')");

    static getdata(Database db)
    {
        return QueryCache(db.execute("SELECT * FROM test"));
    }

    auto data = getdata(db);
    assert(data.length == 1);
    assert(data[0][0].as!string == "ABC");
}


/++
Turns $(D_PARAM value) into a _literal that can be used in an SQLite expression.
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
    /++
    The _code of the error that raised the exception, or 0 if this _code is not known.
    +/
    int code;

    /++
    The SQL code that raised the exception, if applicable.
    +/
    string sql;

    private this(string msg, string sql, int code,
                 string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        this.sql = sql;
        this.code = code;
        super(msg, file, line, next);
    }

    this(string msg, int code, string sql = null,
         string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        this("error %d: %s".format(code, msg), sql, code, file, line, next);
    }

    this(string msg, string sql = null,
         string file = __FILE__, size_t line = __LINE__, Throwable next = null)
    {
        this(msg, sql, 0, file, line, next);
    }
}


private:

string errmsg(sqlite3* db)
{
    return sqlite3_errmsg(db).to!string;
}

string errmsg(sqlite3_stmt* stmt)
{
    return errmsg(sqlite3_db_handle(stmt));
}

auto byStatement(string sql)
{
    static struct ByStatement
    {
        string sql;
        size_t end;

        this(string sql)
        {
            this.sql = sql;
            end = findEnd();
        }

        bool empty()
        {
            return !sql.length;
        }

        string front()
        {
            return sql[0 .. end];
        }

        void popFront()
        {
            sql = sql[end .. $];
            end = findEnd();
        }

    private:
        size_t findEnd()
        {
            size_t pos;
            bool complete;
            do
            {
                auto tail = sql[pos .. $];
                auto offset = tail.countUntil(';') + 1;
                pos += offset;
                if (offset == 0)
                    pos = sql.length;
                auto part = sql[0 .. pos];
                complete = cast(bool) sqlite3_complete(part.toStringz);
            }
            while (!complete && pos < sql.length);
            return pos;
        }
    }

    return ByStatement(sql);
}
unittest
{
    auto sql = "CREATE TABLE test (dummy);
        CREATE TRIGGER trig INSERT ON test BEGIN SELECT 1; SELECT 'a;b'; END;
        SELECT 'c;d';;
        CREATE";
    assert(equal(sql.byStatement.map!(s => s.strip), [
        "CREATE TABLE test (dummy);",
        "CREATE TRIGGER trig INSERT ON test BEGIN SELECT 1; SELECT 'a;b'; END;",
        "SELECT 'c;d';",
        ";",
        "CREATE"
    ]));
}

struct WrappedDelegate(T)
{
    T dlg;
    string name;
}

void* delegateWrap(T)(T dlg, string name = null)
    if (isFunctionPointer!T || isDelegate!T)
{
    import std.functional : toDelegate;

    if (dlg is null)
        return null;

    alias D = typeof(toDelegate(dlg));
    auto d = cast(WrappedDelegate!D*) malloc(WrappedDelegate!D.sizeof);
    d.dlg = toDelegate(dlg);
    d.name = name;
    return cast(void*) d;
}

WrappedDelegate!T* delegateUnwrap(T)(void* ptr)
    if (isCallable!T)
{
    return cast(WrappedDelegate!T*) ptr;
}

extern(C) void ptrFree(void* ptr)
{
    free(ptr);
}

// Anchors and returns a pointer to D memory, so that it will not
// be moved or collected. For use with releaseMem.
void* anchorMem(void* ptr)
{
    GC.addRoot(ptr);
    GC.setAttr(ptr, GC.BlkAttr.NO_MOVE);
    return ptr;
}

// Passed to sqlite3_xxx_blob64/sqlite3_xxx_text64 to unanchor memory.
extern(C) void releaseMem(void* ptr)
{
    GC.setAttr(ptr, GC.BlkAttr.NO_MOVE);
    GC.removeRoot(ptr);
}

// getValue and setResult function templates
// used by createFunction and createAggregate

auto getValue(T)(sqlite3_value* argv)
    if (isBoolean!T)
{
    return sqlite3_value_int64(argv) != 0;
}

auto getValue(T)(sqlite3_value* argv)
    if (isIntegral!T)
{
    return sqlite3_value_int64(argv).to!T;
}

auto getValue(T)(sqlite3_value* argv)
    if (isFloatingPoint!T)
{
    if (sqlite3_value_type(argv) == SqliteType.NULL)
        return double.nan;
    return sqlite3_value_double(argv).to!T;
}

auto getValue(T)(sqlite3_value* argv)
    if (isSomeString!T)
{
    return sqlite3_value_text(argv).to!T;
}

auto getValue(T)(sqlite3_value* argv)
    if (isArray!T && !isSomeString!T)
{
    auto n = sqlite3_value_bytes(argv);
    ubyte[] blob;
    blob.length = n;
    memcpy(blob.ptr, sqlite3_value_blob(argv), n);
    return blob.to!T;
}

auto getValue(T : Nullable!U, U...)(sqlite3_value* argv)
{
    if (sqlite3_value_type(argv) == SqliteType.NULL)
        return T();
    return T(getValue!(U[0])(argv));
}

void setResult(T)(sqlite3_context* context, T value)
    if (isIntegral!T || isBoolean!T)
{
    sqlite3_result_int64(context, value.to!long);
}

void setResult(T)(sqlite3_context* context, T value)
    if (isFloatingPoint!T)
{
    sqlite3_result_double(context, value.to!double);
}

void setResult(T)(sqlite3_context* context, T value)
    if (isSomeString!T)
{
    auto val = value.to!string;
    sqlite3_result_text64(context, cast(const(char)*) anchorMem(cast(void*) val.ptr),
        val.length, &releaseMem, SQLITE_UTF8);
}

void setResult(T)(sqlite3_context* context, T value)
    if (isDynamicArray!T && !isSomeString!T)
{
    auto val = cast(void[]) value;
    sqlite3_result_blob64(context, anchorMem(val.ptr), val.length, &releaseMem);
}

void setResult(T)(sqlite3_context* context, T value)
    if (isStaticArray!T)
{
    auto val = cast(void[]) value;
    sqlite3_result_blob64(context, val.ptr, val.sizeof, SQLITE_TRANSIENT);
}

void setResult(T : Nullable!U, U...)(sqlite3_context* context, T value)
{
    if (value.isNull)
        sqlite3_result_null(context);
    else
        setResult(context, value.get);
}

// Copy from std.traits, as long as GDC doesn't have it.
enum NameOf(alias T) = T.stringof;
