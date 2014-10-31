/++
This is an application inspired by the proof-of-concept SQLAR archive utility.

See:
    $(LINK http://www.sqlite.org/sqlar/doc/trunk/README.md).
+/
module dsqlar;

version (Windows)
    pragma(msg, "\nWARNING !!!\nDevelopped for POSIX systems only.\nNot tested on Windows.\n");

import d2sqlite3;
import sizefmt;
import std.array;
import std.conv;
import std.exception;
import std.file;
import std.path;
import std.stdio;
import std.string;
import std.c.stdlib : exit;
import core.stdc.time : time_t;
import etc.c.zlib;

alias Size = SizeBase!(config!`{ spacing: Spacing.tabular }`);

enum sqlCreateSchema =
`CREATE TABLE IF NOT EXISTS sqlar (
    name TEXT PRIMARY KEY,
    mode INT,
    mtime INT,
    sz INT,
    data BLOB
);`;

struct Options
{
    bool list;
    bool nocompress;
    bool extract;
    bool verbose;
    string archive;
    string[] paths;
}

__gshared Options options;

void error(string msg, bool showUsage = false)
{
    import core.runtime : Runtime;

    if (msg)
        stderr.writeln(msg, "\n");

    if (showUsage)
    {
        stderr.writefln("Usage: %s [options] archive [files...]\n"~
                        "Options:\n"~
                        "   -l      List files in archive\n"~
                        "   -n      Do not compress files\n"~
                        "   -x      Extract files from archive\n"~
                        "   -v      Verbose output\n", Runtime.args[0]);
    }

    exit(msg ? 1 : 0);
}

void processCmdLine(string[] args)
{
    import std.getopt;

    getopt(args, config.bundling, config.passThrough,
           "l", &options.list,
           "n", &options.nocompress,
           "x", &options.extract,
           "v", &options.verbose,
           "help|h", { error(null, true); });

    args.popFront();

    if (args.empty)
        error("Please provide the path of an archive", true);

    options.archive = args.front;
    args.popFront();

    options.paths = args;
}

void addFile(Query query, DirEntry de)
{
    assert(de.isFile || de.isSymlink);

    // Size limitation for SQLite blobs
    enforce(de.size < 1_000_000_000,
            "%s: File is too long (%s)".format(de.name, Size(de.size)));

    auto sourceData = cast(ubyte[]) read(de.name);
    size_t sourceSize = sourceData.length;
    size_t destSize = 13 + sourceSize + (sourceSize + 999) / 1000;

    // Reused buffer
    static ubyte[] destData;
    if (destData.length < destSize)
        destData.length = destSize;

    ubyte[] usedData;
    if (!options.nocompress)
    {
        auto result = compress(destData.ptr, &destSize, sourceData.ptr, sourceSize);
        enforce(result == Z_OK, "%s: Cannot compress file".format(de.name));
        if (destSize < sourceSize)
        {
            usedData = destData;
            usedData.length = destSize;
        }
        else
            usedData = sourceData;
    }
    else
        usedData = sourceData;

    query.bind(1, de.name);
    query.bind(2, de.attributes);
    query.bind(3, de.timeLastModified.toUnixTime);
    query.bind(4, de.size);
    query.bind(5, usedData);
    query.execute();
    query.reset();

    if (options.verbose)
    {
        if (destSize < sourceSize)
        {
            double pct = 100 * destSize / cast(double) sourceSize;
            writefln("Deflated: %s (%.1f%%)", de.name, 100 - pct);
        }
        else
            writefln("Added   : %s", de.name);
    }
}

void add()
{
    if (!options.paths.length)
        error("Please provide files or directories to add to archive", true);

    try
    {
        auto db = Database(options.archive);
        db.execute("BEGIN");
        scope (success) db.execute("COMMIT;");
        scope (failure) db.execute("ROLLBACK");

        db.execute(sqlCreateSchema);

        auto query = db.query(
            "REPLACE INTO sqlar(name,mode,mtime,sz,data) "~
            "VALUES(?1,?2,?3,?4,?5)");

        foreach (path; options.paths)
        {
            enforce(!relativePath(path).startsWith(".."),
                    "Path is not below the current directory: %s".format(path));

            auto de = DirEntry(path);
            if (de.isDir)
            {
                foreach (de2; dirEntries(de.name, SpanMode.depth))
                    if (de2.isFile || de2.isSymlink)
                        addFile(query, de2);
            }
            else if (de.isFile || de.isSymlink)
                addFile(query, de);
        }
    }
    catch (Exception e)
        error("Error while archiving: %s".format(e.msg));
}

void list()
{
    try
    {
        auto db = Database(options.archive, SQLITE_OPEN_READONLY);
        db.execute("BEGIN");
        scope (success) db.execute("COMMIT;");
        scope (failure) db.execute("ROLLBACK");

        if (options.verbose)
        {
            writefln("%10s %10s  %-4s  %-19s  %-s",
                     "Full Size",
                     "Compressed",
                     "Mode",
                     "Date/Time",
                     "File");

            auto query = db.query("SELECT name, sz, length(data), mode, datetime(mtime,'unixepoch') "~
                                  "FROM sqlar ORDER BY name");
            while (!query.empty)
            {
                auto row = query.front;
                writefln("%s %s  %4o  %s  %10s",
                         Size(row.peek!size_t(1)),
                         Size(row.peek!size_t(2)),
                         row.peek!uint(3) & octal!777,
                         row.peek!string(4),
                         row.peek!string(0));
                query.popFront();
            }
        }
        else
        {
            auto query = db.query("SELECT name FROM sqlar ORDER BY name");
            while (!query.empty)
            {
                writeln(query.front.peek!string(0));
                query.popFront();
            }
        }
    }
    catch (Exception e)
        error("Error while listing archive: %s".format(e.msg));
}

bool nameOnList(string name)
{
    import std.algorithm : canFind;
    return options.paths.canFind(name);
}

void extract()
{
    version (Posix)
        import core.sys.posix.sys.stat : chmod, mode_t;

    try
    {
        auto db = Database(options.archive, SQLITE_OPEN_READONLY);
        db.execute("BEGIN");
        scope (success) db.execute("COMMIT;");
        scope (failure) db.execute("ROLLBACK");

        db.createFunction!(nameOnList, "name_on_list");

        Query query;
        if (options.paths.length)
            query = db.query("SELECT name, mode, mtime, sz, data FROM sqlar "~
                             "WHERE name_on_list(name)");
        else
            query = db.query("SELECT name, mode, mtime, sz, data FROM sqlar");

        while (!query.empty)
        {
            auto row = query.front;
            auto path = row.peek!string(0);
            auto mode = row.peek!uint(1);
            auto time = row.peek!time_t(2);
            auto size = row.peek!size_t(3);
            auto data = row.peek!(ubyte[])(4);

            auto dir = path.dirName;
            enforce(!relativePath(dir).startsWith(".."),
                    "Path is not below the current directory: %s".format(dir));

            if (!dir.exists)
                mkdirRecurse(dir);

            auto file = File(path, "wb");
            if (data.length < size)
            {
                static ubyte[] destData;
                if (destData.length < size)
                    destData.length = size;
                
                auto result = uncompress(destData.ptr, &size, data.ptr, data.length);
                enforce(result == Z_OK, "%s: Cannot uncompress file".format(path));
                file.rawWrite(destData[0 .. size]);
                file.close();
                if (options.verbose)
                    writefln("Inflated : %s", path);
            }
            else
            {
                file.rawWrite(data);
                file.close();
                if (options.verbose)
                    writefln("Extracted: %s", path);
            }
            version (Posix)
                chmod(path.toStringz, cast(mode_t) mode);
                
            query.popFront();
        }
    }
    catch (Exception e)
        error("Error while extracting: %s".format(e.msg));
}

void main(string[] args)
{
    processCmdLine(args);

    if (options.list)
        list();
    else if (options.extract)
        extract();
    else
        add();
}