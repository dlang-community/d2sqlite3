module d2sqlite3.database;

import d2sqlite3.statement;
import d2sqlite3.results;
import d2sqlite3.sqlite3;
import d2sqlite3.internal.memory;
import d2sqlite3.internal.util;

import std.conv : to;
import std.exception : enforce;
import std.string : format, toStringz;
import std.typecons : Nullable;

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
Gets the library's version number (e.g. 3_008_007).
+/
int versionNumber() nothrow
{
    return sqlite3_libversion_number();
}

/++
Tells whether SQLite was compiled with the thread-safe options.

See_also: ($LINK http://www.sqlite.org/c3ref/threadsafe.html).
+/
bool threadSafe() nothrow
{
    return cast(bool) sqlite3_threadsafe();
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
    import std.traits : isFunctionPointer, isDelegate;
    import std.typecons : RefCounted, RefCountedAutoInitialize;

private:
    struct Payload
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
            if (!handle)
                return;
        
            sqlite3_progress_handler(handle, 0, null, null);
            auto result = sqlite3_close(handle);
            // Check that destructor was not call by the GC
            // See https://p0nce.github.io/d-idioms/#GC-proof-resource-class
            import core.exception : InvalidMemoryOperationError;
            try
            {
                enforce(result == SQLITE_OK, new SqliteException(errmsg(handle), result));
            }
            catch (InvalidMemoryOperationError e)
            {
                import core.stdc.stdio : fprintf, stderr;
                fprintf(stderr, "Error: release of Database resource incorrectly"
                                ~ " depends on destructors called by the GC.\n");
                assert(false); // crash
            }
            handle = null;
            ptrFree(updateHook);
            ptrFree(commitHook);
            ptrFree(rollbackHook);
            ptrFree(progressHandler);
            ptrFree(traceCallback);
            ptrFree(profileCallback);
        }
    }

    RefCounted!(Payload, RefCountedAutoInitialize.no) p;

    void check(int result)
    {
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
        enforce(result == SQLITE_OK, new SqliteException(hdl ? errmsg(hdl) : "Error opening the database", result));
        p = Payload(hdl);
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
        assert(p.handle);
        return sqlite3_db_filename(p.handle, database.toStringz).to!string;
    }

    /++
    Gets the read-only status of an attached database.

    Params:
        database = The name of an attached database.
    +/
    bool isReadOnly(string database = "main")
    {
        immutable ret = sqlite3_db_readonly(p.handle, database.toStringz);
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
    void run(string script, bool delegate(ResultRange) dg = null)
    {
        foreach (sql; script.byStatement)
        {
            auto stmt = prepare(sql);
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
        assert(p.handle);
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
            immutable ret = sqlite3_load_extension(p.handle, path.toStringz, entryPoint.toStringz, null);
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
        import std.meta : AliasSeq, staticMap, EraseAll;
        import std.traits : variadicFunctionStyle, Variadic, ParameterTypeTuple,
            ParameterDefaultValueTuple, ReturnType, Unqual;

        static assert(variadicFunctionStyle!(fun) == Variadic.no
            || is(ParameterTypeTuple!fun == AliasSeq!(ColumnData[])),
            "only type-safe variadic functions with ColumnData arguments are supported");

        static if (is(ParameterTypeTuple!fun == AliasSeq!(ColumnData[])))
        {
            extern(C) static nothrow
            void x_func(sqlite3_context* context, int argc, sqlite3_value** argv)
            {
                string name;
                try
                {
                    import std.array : appender;
                    auto args = appender!(ColumnData[]);

                    for (int i = 0; i < argc; ++i)
                    {
                        auto value = argv[i];
                        immutable type = sqlite3_value_type(value);

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
                    sqlite3_result_error(context, "error in function %s(): %s"
                        .nothrowFormat(name, e.msg).toStringz, -1);
                }
            }
        }
        else
        {
            static assert(!is(ReturnType!fun == void), "function must not return void");

            alias PT = staticMap!(Unqual, ParameterTypeTuple!fun);
            alias PD = ParameterDefaultValueTuple!fun;

            extern (C) static nothrow
            void x_func(sqlite3_context* context, int argc, sqlite3_value** argv)
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
                        auto txt = ("too many arguments in function %s(), expecting at most %s"
                            ).format(name, maxArgc);
                        sqlite3_result_error(context, txt.toStringz, -1);
                    }
                    else if (argc < minArgc)
                    {
                        auto txt = ("too few arguments in function %s(), expecting at least %s"
                            ).format(name, minArgc);
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
                    sqlite3_result_error(context, "error in function %s(): %s"
                        .nothrowFormat(name, e.msg).toStringz, -1);
                }
            }
        }

        assert(name.length, "function has an empty name");

        if (!fun)
            createFunction(name, null);

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
            import std.array : appender;
            import std.string : format, join;

            auto app = appender!(string[]);
            foreach (arg; args)
            {
                if (arg.type == SqliteType.TEXT)
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

    /// Ditto
    void createFunction(T)(string name, T fun = null)
        if (is(T == typeof(null)))
    {
        assert(name.length, "function has an empty name");
        assert(p.handle);
        check(sqlite3_create_function_v2(p.handle, name.toStringz, -1, SQLITE_UTF8,
                null, fun, null, null, null));
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
        import std.meta : staticMap;
        import std.traits : isAggregateType, ReturnType, variadicFunctionStyle, Variadic,
            Unqual, ParameterTypeTuple;
        import core.stdc.stdlib : malloc;

        static assert(isAggregateType!T,
            T.stringof ~ " should be an aggregate type");
        static assert(is(typeof(T.accumulate) == function),
            T.stringof ~ " should have a method named accumulate");
        static assert(is(typeof(T.result) == function),
            T.stringof ~ " should have a method named result");
        static assert(is(typeof({
                alias RT = ReturnType!(T.result);
                setResult!RT(null, RT.init);
            })), T.stringof ~ ".result should return an SQLite-compatible type");
        static assert(variadicFunctionStyle!(T.accumulate) == Variadic.no,
            "variadic functions are not supported");
        static assert(variadicFunctionStyle!(T.result) == Variadic.no,
            "variadic functions are not supported");

        alias PT = staticMap!(Unqual, ParameterTypeTuple!(T.accumulate));
        alias RT = ReturnType!(T.result);

        static struct Context
        {
            T aggregate;
            string functionName;
        }

        extern(C) static nothrow
        void x_step(sqlite3_context* context, int /* argc */, sqlite3_value** argv)
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
                sqlite3_result_error(context, "error in aggregate function %s(): %s"
                    .nothrowFormat(ctx.functionName, e.msg).toStringz, -1);
            }
        }

        extern(C) static nothrow
        void x_final(sqlite3_context* context)
        {
            auto ctx = cast(Context*) sqlite3_user_data(context);
            if (!ctx)
            {
                sqlite3_result_error_nomem(context);
                return;
            }

            try
            {
                setResult(context, ctx.aggregate.result());
            }
            catch (Exception e)
            {
                sqlite3_result_error(context, "error in aggregate function %s(): %s"
                    .nothrowFormat(ctx.functionName, e.msg).toStringz, -1);
            }
        }

        static if (is(T == class) || is(T == Interface))
            assert(agg, "Attempt to create an aggregate function from a null reference");

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
        import std.array : Appender, join;

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

    /++
    Creates and registers a collation function in the database.

    Params:
        name = The name that the function will have in the database.

        fun = a delegate or function that implements the collation. The function $(D_PARAM fun)
        must be `nothrow`` and satisfy these criteria:
            $(UL
                $(LI Takes two string arguments (s1 and s2). These two strings are slices of C-style strings
                  that SQLite manages internally, so there is no guarantee that they are still valid 
                  when the function returns.)
                $(LI Returns an integer (ret).)
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
        import std.traits : isImplicitlyConvertible, functionAttributes, FunctionAttribute,
            ParameterTypeTuple, isSomeString, ReturnType;
        
        static assert(isImplicitlyConvertible!(typeof(fun("a", "b")), int),
            "the collation function has a wrong signature");

        static assert(functionAttributes!(T) & FunctionAttribute.nothrow_,
            "only nothrow functions are allowed as collations");

        alias PT = ParameterTypeTuple!fun;
        static assert(isSomeString!(PT[0]),
            "the first argument of function " ~ name ~ " should be a string");
        static assert(isSomeString!(PT[1]),
            "the second argument of function " ~ name ~ " should be a string");
        static assert(isImplicitlyConvertible!(ReturnType!fun, int),
            "function " ~ name ~ " should return a value convertible to an int");

        extern (C) static nothrow
        int x_compare(void* ptr, int n1, const(void)* str1, int n2, const(void)* str2)
        {
            static string slice(const(void)* str, int n) nothrow
            {
                // The string data is owned by SQLite, so it should be safe
                // to take a slice of it.
                return str ? (cast(immutable) (cast(const(char)*) str)[0 .. n]) : null;
            }

            return delegateUnwrap!T(ptr).dlg(slice(str1, n1), slice(str2, n2));
        }

        assert(p.handle);
        auto dgw = delegateWrap(fun, name);
        auto result = sqlite3_create_collation_v2(p.handle, name.toStringz, SQLITE_UTF8,
            delegateWrap(fun, name), &x_compare, &ptrFree);
        if (result != SQLITE_OK)
        {
            ptrFree(dgw);
            throw new SqliteException(errmsg(p.handle), result);
        }
    }
    ///
    unittest // Collation creation
    {
        // The implementation of the collation
        int my_collation(string s1, string s2) nothrow
        {
            import std.uni : icmp;
            import std.exception : assumeWontThrow;
            
            return assumeWontThrow(icmp(s1, s2));
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
    Registers a delegate of type `UpdateHookDelegate` as the database's update hook.

    Any previously set hook is released. Pass `null` to disable the callback.

    See_Also: $(LINK http://www.sqlite.org/c3ref/commit_hook.html).
    +/
    void setUpdateHook(UpdateHookDelegate updateHook)
    {
        extern(C) static nothrow
        void callback(void* ptr, int type, char* dbName, char* tableName, long rowid)
        {
            WrappedDelegate!UpdateHookDelegate* dg;
            dg = delegateUnwrap!UpdateHookDelegate(ptr);
            dg.dlg(type, dbName.to!string, tableName.to!string, rowid);
        }

        ptrFree(p.updateHook);
        p.updateHook = delegateWrap(updateHook);
        sqlite3_update_hook(p.handle, &callback, p.updateHook);
    }

    /++
    Registers a delegate of type `CommitHookDelegate` as the database's commit hook.
    Any previously set hook is released.

    Params:
        commitHook = A delegate that should return a non-zero value
        if the operation must be rolled back, or 0 if it can commit.
        Pass `null` to disable the callback.

    See_Also: $(LINK http://www.sqlite.org/c3ref/commit_hook.html).
    +/
    void setCommitHook(CommitHookDelegate commitHook)
    {
        extern(C) static nothrow
        int callback(void* ptr)
        {
            auto dlg = delegateUnwrap!CommitHookDelegate(ptr).dlg;
            return dlg();
        }

        ptrFree(p.commitHook);
        p.commitHook = delegateWrap(commitHook);
        sqlite3_commit_hook(p.handle, &callback, p.commitHook);
    }

    /++
    Registers a delegate of type `RoolbackHookDelegate` as the database's rollback hook.

    Any previously set hook is released.
    Pass `null` to disable the callback.

    See_Also: $(LINK http://www.sqlite.org/c3ref/commit_hook.html).
    +/
    void setRollbackHook(RoolbackHookDelegate rollbackHook)
    {
        extern(C) static nothrow
        void callback(void* ptr)
        {
            auto dlg = delegateUnwrap!RoolbackHookDelegate(ptr).dlg;
            dlg();
        }

        ptrFree(p.rollbackHook);
        p.rollbackHook = delegateWrap(rollbackHook);
        sqlite3_rollback_hook(p.handle, &callback, p.rollbackHook);
    }

    /++
    Registers a delegate of type `ProgressHandlerDelegate` as the progress handler.

    Any previously set handler is released.
    Pass `null` to disable the callback.

    Params:
        pace = The approximate number of virtual machine instructions that are
        evaluated between successive invocations of the handler.

        progressHandler = A delegate that should return 0 if the operation can continue
        or another value if it must be aborted.

    See_Also: $(LINK http://www.sqlite.org/c3ref/progress_handler.html).
    +/
    void setProgressHandler(int pace, ProgressHandlerDelegate progressHandler)
    {
        extern(C) static nothrow
        int callback(void* ptr)
        {
            auto dlg = delegateUnwrap!ProgressHandlerDelegate(ptr).dlg;
            return dlg();
        }

        ptrFree(p.progressHandler);
        p.progressHandler = delegateWrap(progressHandler);
        sqlite3_progress_handler(p.handle, pace, &callback, p.progressHandler);
    }

    /++
    Registers a delegate of type `TraceCallbackDelegate` as the trace callback.

    Any previously set trace callback is released.
    Pass `null` to disable the callback.

    The string parameter that is passed to the callback is the SQL text of the statement being
    executed.

    See_Also: $(LINK http://www.sqlite.org/c3ref/profile.html).
    +/
    void setTraceCallback(TraceCallbackDelegate traceCallback)
    {
        extern(C) static nothrow
        void callback(void* ptr, const(char)* str)
        {
            auto dlg = delegateUnwrap!TraceCallbackDelegate(ptr).dlg;
            dlg(str.to!string);
        }

        ptrFree(p.traceCallback);
        p.traceCallback = delegateWrap(traceCallback);
        sqlite3_trace(p.handle, &callback, p.traceCallback);
    }

    /++
    Registers a delegate of type `ProfileCallbackDelegate` as the profile callback.

    Any previously set profile callback is released.
    Pass `null` to disable the callback.

    The string parameter that is passed to the callback is the SQL text of the statement being
    executed. The time unit is defined in SQLite's documentation as nanoseconds (subject to change,
    as the functionality is experimental).

    See_Also: $(LINK http://www.sqlite.org/c3ref/profile.html).
    +/
    void setProfileCallback(ProfileCallbackDelegate profileCallback)
    {
        extern(C) static nothrow
        void callback(void* ptr, const(char)* str, sqlite3_uint64 time)
        {
            auto dlg = delegateUnwrap!ProfileCallbackDelegate(ptr).dlg;
            dlg(str.to!string, time);
        }

        ptrFree(p.profileCallback);
        p.profileCallback = delegateWrap(profileCallback);
        sqlite3_profile(p.handle, &callback, p.profileCallback);
    }
}

/// Delegate types
alias UpdateHookDelegate = void delegate(int type, string dbName, string tableName, long rowid) nothrow;
/// ditto
alias CommitHookDelegate = int delegate() nothrow;
/// ditto
alias RoolbackHookDelegate = void delegate() nothrow;
/// ditto
alias ProgressHandlerDelegate = int delegate() nothrow;
/// ditto
alias TraceCallbackDelegate = void delegate(string sql) nothrow;
/// ditto
alias ProfileCallbackDelegate = void delegate(string sql, ulong time) nothrow;

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
