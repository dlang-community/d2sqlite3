module sql3fun;

import sqlite3;
import std.exception;
import std.string;
import std.traits;

version(none) {
    
    void createFunction(F)(ref Database db, F fun, string name = null) {
        static assert(isDelegate!F || isFunctionPointer!F);

        alias ParameterTypeTuple!F PT;
        alias ReturnType!F RT;
        enum paramcount = PT.length;

        sqlite3_value*[] values;
        values.length = paramcount;

        /+
        .
        .
        .
        +/

        mixin(`
            extern(C) static void _generated(sqlite3_context* c, int argc, sqlite3_value** argv) {
                assert(argc == 2);

                if (isSomeString!RT) {
                    auto result = "..." ;
                    sqlite3_result_text(c, cast(char*) result.toStringz, -1, null);
                }
            }
        `);

        /+
        auto result = sqlite3_create_function(db.handle, cast(char*) name.toStringz, paramcount,
            SQLITE_UTF8, null, &_generated, null, null);
        enforce(result == SQLITE_OK, new SqliteException(db.errorMsg, result));
        +/
    }

    unittest {
        string my_function(string s, int i) {
            return "COUCOU";
        }

        auto db = Database(":memory:");
        createFunction(db, "my_function", &my_function);
    }
    
}
