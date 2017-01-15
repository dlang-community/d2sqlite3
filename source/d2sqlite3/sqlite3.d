// Generated with `dstep --package "d2sqlite3" -o source/d2sqlite3/sqlite3.d c/sqlite3.h --comments=false --skip SQLITE_STDCALL`
module d2sqlite3.sqlite3;

import core.stdc.stdarg;

extern (C) nothrow @nogc: // DSTEP manual fix

// DSTEP manual fix -->
struct sqlite3;
struct sqlite3_stmt;
struct sqlite3_context;
struct sqlite3_blob;
struct sqlite3_mutex;
struct sqlite3_pcache;
struct sqlite3_backup;
struct Fts5Context;
struct Fts5Tokenizer;
// <--

enum SQLITE_VERSION = "3.16.2";
enum SQLITE_VERSION_NUMBER = 3016002;
enum SQLITE_SOURCE_ID = "2017-01-06 16:32:41 a65a62893ca8319e89e48b8a38cf8a59c69a8209";

extern __gshared const(char)[] sqlite3_version;
const(char)* sqlite3_libversion ();
const(char)* sqlite3_sourceid ();
int sqlite3_libversion_number ();

int sqlite3_compileoption_used (const(char)* zOptName);
const(char)* sqlite3_compileoption_get (int N);

int sqlite3_threadsafe ();

alias long sqlite_int64;
alias ulong sqlite_uint64;

alias long sqlite3_int64;
alias ulong sqlite3_uint64;

int sqlite3_close (sqlite3*);
int sqlite3_close_v2 (sqlite3*);

alias int function (void*, int, char**, char**) sqlite3_callback;

int sqlite3_exec (
    sqlite3*,
    const(char)* sql,
    int function (void*, int, char**, char**) callback,
    void*,
    char** errmsg);

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
enum SQLITE_NOTICE = 27;
enum SQLITE_WARNING = 28;
enum SQLITE_ROW = 100;
enum SQLITE_DONE = 101;

enum SQLITE_IOERR_READ = SQLITE_IOERR | (1 << 8);
enum SQLITE_IOERR_SHORT_READ = SQLITE_IOERR | (2 << 8);
enum SQLITE_IOERR_WRITE = SQLITE_IOERR | (3 << 8);
enum SQLITE_IOERR_FSYNC = SQLITE_IOERR | (4 << 8);
enum SQLITE_IOERR_DIR_FSYNC = SQLITE_IOERR | (5 << 8);
enum SQLITE_IOERR_TRUNCATE = SQLITE_IOERR | (6 << 8);
enum SQLITE_IOERR_FSTAT = SQLITE_IOERR | (7 << 8);
enum SQLITE_IOERR_UNLOCK = SQLITE_IOERR | (8 << 8);
enum SQLITE_IOERR_RDLOCK = SQLITE_IOERR | (9 << 8);
enum SQLITE_IOERR_DELETE = SQLITE_IOERR | (10 << 8);
enum SQLITE_IOERR_BLOCKED = SQLITE_IOERR | (11 << 8);
enum SQLITE_IOERR_NOMEM = SQLITE_IOERR | (12 << 8);
enum SQLITE_IOERR_ACCESS = SQLITE_IOERR | (13 << 8);
enum SQLITE_IOERR_CHECKRESERVEDLOCK = SQLITE_IOERR | (14 << 8);
enum SQLITE_IOERR_LOCK = SQLITE_IOERR | (15 << 8);
enum SQLITE_IOERR_CLOSE = SQLITE_IOERR | (16 << 8);
enum SQLITE_IOERR_DIR_CLOSE = SQLITE_IOERR | (17 << 8);
enum SQLITE_IOERR_SHMOPEN = SQLITE_IOERR | (18 << 8);
enum SQLITE_IOERR_SHMSIZE = SQLITE_IOERR | (19 << 8);
enum SQLITE_IOERR_SHMLOCK = SQLITE_IOERR | (20 << 8);
enum SQLITE_IOERR_SHMMAP = SQLITE_IOERR | (21 << 8);
enum SQLITE_IOERR_SEEK = SQLITE_IOERR | (22 << 8);
enum SQLITE_IOERR_DELETE_NOENT = SQLITE_IOERR | (23 << 8);
enum SQLITE_IOERR_MMAP = SQLITE_IOERR | (24 << 8);
enum SQLITE_IOERR_GETTEMPPATH = SQLITE_IOERR | (25 << 8);
enum SQLITE_IOERR_CONVPATH = SQLITE_IOERR | (26 << 8);
enum SQLITE_IOERR_VNODE = SQLITE_IOERR | (27 << 8);
enum SQLITE_IOERR_AUTH = SQLITE_IOERR | (28 << 8);
enum SQLITE_LOCKED_SHAREDCACHE = SQLITE_LOCKED | (1 << 8);
enum SQLITE_BUSY_RECOVERY = SQLITE_BUSY | (1 << 8);
enum SQLITE_BUSY_SNAPSHOT = SQLITE_BUSY | (2 << 8);
enum SQLITE_CANTOPEN_NOTEMPDIR = SQLITE_CANTOPEN | (1 << 8);
enum SQLITE_CANTOPEN_ISDIR = SQLITE_CANTOPEN | (2 << 8);
enum SQLITE_CANTOPEN_FULLPATH = SQLITE_CANTOPEN | (3 << 8);
enum SQLITE_CANTOPEN_CONVPATH = SQLITE_CANTOPEN | (4 << 8);
enum SQLITE_CORRUPT_VTAB = SQLITE_CORRUPT | (1 << 8);
enum SQLITE_READONLY_RECOVERY = SQLITE_READONLY | (1 << 8);
enum SQLITE_READONLY_CANTLOCK = SQLITE_READONLY | (2 << 8);
enum SQLITE_READONLY_ROLLBACK = SQLITE_READONLY | (3 << 8);
enum SQLITE_READONLY_DBMOVED = SQLITE_READONLY | (4 << 8);
enum SQLITE_ABORT_ROLLBACK = SQLITE_ABORT | (2 << 8);
enum SQLITE_CONSTRAINT_CHECK = SQLITE_CONSTRAINT | (1 << 8);
enum SQLITE_CONSTRAINT_COMMITHOOK = SQLITE_CONSTRAINT | (2 << 8);
enum SQLITE_CONSTRAINT_FOREIGNKEY = SQLITE_CONSTRAINT | (3 << 8);
enum SQLITE_CONSTRAINT_FUNCTION = SQLITE_CONSTRAINT | (4 << 8);
enum SQLITE_CONSTRAINT_NOTNULL = SQLITE_CONSTRAINT | (5 << 8);
enum SQLITE_CONSTRAINT_PRIMARYKEY = SQLITE_CONSTRAINT | (6 << 8);
enum SQLITE_CONSTRAINT_TRIGGER = SQLITE_CONSTRAINT | (7 << 8);
enum SQLITE_CONSTRAINT_UNIQUE = SQLITE_CONSTRAINT | (8 << 8);
enum SQLITE_CONSTRAINT_VTAB = SQLITE_CONSTRAINT | (9 << 8);
enum SQLITE_CONSTRAINT_ROWID = SQLITE_CONSTRAINT | (10 << 8);
enum SQLITE_NOTICE_RECOVER_WAL = SQLITE_NOTICE | (1 << 8);
enum SQLITE_NOTICE_RECOVER_ROLLBACK = SQLITE_NOTICE | (2 << 8);
enum SQLITE_WARNING_AUTOINDEX = SQLITE_WARNING | (1 << 8);
enum SQLITE_AUTH_USER = SQLITE_AUTH | (1 << 8);
enum SQLITE_OK_LOAD_PERMANENTLY = SQLITE_OK | (1 << 8);

enum SQLITE_OPEN_READONLY = 0x00000001;
enum SQLITE_OPEN_READWRITE = 0x00000002;
enum SQLITE_OPEN_CREATE = 0x00000004;
enum SQLITE_OPEN_DELETEONCLOSE = 0x00000008;
enum SQLITE_OPEN_EXCLUSIVE = 0x00000010;
enum SQLITE_OPEN_AUTOPROXY = 0x00000020;
enum SQLITE_OPEN_URI = 0x00000040;
enum SQLITE_OPEN_MEMORY = 0x00000080;
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
enum SQLITE_IOCAP_POWERSAFE_OVERWRITE = 0x00001000;
enum SQLITE_IOCAP_IMMUTABLE = 0x00002000;

enum SQLITE_LOCK_NONE = 0;
enum SQLITE_LOCK_SHARED = 1;
enum SQLITE_LOCK_RESERVED = 2;
enum SQLITE_LOCK_PENDING = 3;
enum SQLITE_LOCK_EXCLUSIVE = 4;

enum SQLITE_SYNC_NORMAL = 0x00002;
enum SQLITE_SYNC_FULL = 0x00003;
enum SQLITE_SYNC_DATAONLY = 0x00010;

struct sqlite3_file
{
    struct sqlite3_io_methods
    {
        int iVersion;
        int function (sqlite3_file*) xClose;
        int function (sqlite3_file*, void*, int iAmt, sqlite3_int64 iOfst) xRead;
        int function (sqlite3_file*, const(void)*, int iAmt, sqlite3_int64 iOfst) xWrite;
        int function (sqlite3_file*, sqlite3_int64 size) xTruncate;
        int function (sqlite3_file*, int flags) xSync;
        int function (sqlite3_file*, sqlite3_int64* pSize) xFileSize;
        int function (sqlite3_file*, int) xLock;
        int function (sqlite3_file*, int) xUnlock;
        int function (sqlite3_file*, int* pResOut) xCheckReservedLock;
        int function (sqlite3_file*, int op, void* pArg) xFileControl;
        int function (sqlite3_file*) xSectorSize;
        int function (sqlite3_file*) xDeviceCharacteristics;

        int function (sqlite3_file*, int iPg, int pgsz, int, void**) xShmMap;
        int function (sqlite3_file*, int offset, int n, int flags) xShmLock;
        void function (sqlite3_file*) xShmBarrier;
        int function (sqlite3_file*, int deleteFlag) xShmUnmap;

        int function (sqlite3_file*, sqlite3_int64 iOfst, int iAmt, void** pp) xFetch;
        int function (sqlite3_file*, sqlite3_int64 iOfst, void* p) xUnfetch;
    }

    const(sqlite3_io_methods)* pMethods;
}

enum SQLITE_FCNTL_LOCKSTATE = 1;
enum SQLITE_FCNTL_GET_LOCKPROXYFILE = 2;
enum SQLITE_FCNTL_SET_LOCKPROXYFILE = 3;
enum SQLITE_FCNTL_LAST_ERRNO = 4;
enum SQLITE_FCNTL_SIZE_HINT = 5;
enum SQLITE_FCNTL_CHUNK_SIZE = 6;
enum SQLITE_FCNTL_FILE_POINTER = 7;
enum SQLITE_FCNTL_SYNC_OMITTED = 8;
enum SQLITE_FCNTL_WIN32_AV_RETRY = 9;
enum SQLITE_FCNTL_PERSIST_WAL = 10;
enum SQLITE_FCNTL_OVERWRITE = 11;
enum SQLITE_FCNTL_VFSNAME = 12;
enum SQLITE_FCNTL_POWERSAFE_OVERWRITE = 13;
enum SQLITE_FCNTL_PRAGMA = 14;
enum SQLITE_FCNTL_BUSYHANDLER = 15;
enum SQLITE_FCNTL_TEMPFILENAME = 16;
enum SQLITE_FCNTL_MMAP_SIZE = 18;
enum SQLITE_FCNTL_TRACE = 19;
enum SQLITE_FCNTL_HAS_MOVED = 20;
enum SQLITE_FCNTL_SYNC = 21;
enum SQLITE_FCNTL_COMMIT_PHASETWO = 22;
enum SQLITE_FCNTL_WIN32_SET_HANDLE = 23;
enum SQLITE_FCNTL_WAL_BLOCK = 24;
enum SQLITE_FCNTL_ZIPVFS = 25;
enum SQLITE_FCNTL_RBU = 26;
enum SQLITE_FCNTL_VFS_POINTER = 27;
enum SQLITE_FCNTL_JOURNAL_POINTER = 28;
enum SQLITE_FCNTL_WIN32_GET_HANDLE = 29;
enum SQLITE_FCNTL_PDB = 30;

enum SQLITE_GET_LOCKPROXYFILE = SQLITE_FCNTL_GET_LOCKPROXYFILE;
enum SQLITE_SET_LOCKPROXYFILE = SQLITE_FCNTL_SET_LOCKPROXYFILE;
enum SQLITE_LAST_ERRNO = SQLITE_FCNTL_LAST_ERRNO;

alias void function () sqlite3_syscall_ptr;

struct sqlite3_vfs
{
    int iVersion;
    int szOsFile;
    int mxPathname;
    sqlite3_vfs* pNext;
    const(char)* zName;
    void* pAppData;
    int function (sqlite3_vfs*, const(char)* zName, sqlite3_file*, int flags, int* pOutFlags) xOpen;
    int function (sqlite3_vfs*, const(char)* zName, int syncDir) xDelete;
    int function (sqlite3_vfs*, const(char)* zName, int flags, int* pResOut) xAccess;
    int function (sqlite3_vfs*, const(char)* zName, int nOut, char* zOut) xFullPathname;
    void* function (sqlite3_vfs*, const(char)* zFilename) xDlOpen;
    void function (sqlite3_vfs*, int nByte, char* zErrMsg) xDlError;
    void function (sqlite3_vfs*, void*, const(char)* zSymbol) function (sqlite3_vfs*, void*, const(char)* zSymbol) xDlSym;
    void function (sqlite3_vfs*, void*) xDlClose;
    int function (sqlite3_vfs*, int nByte, char* zOut) xRandomness;
    int function (sqlite3_vfs*, int microseconds) xSleep;
    int function (sqlite3_vfs*, double*) xCurrentTime;
    int function (sqlite3_vfs*, int, char*) xGetLastError;

    int function (sqlite3_vfs*, sqlite3_int64*) xCurrentTimeInt64;

    int function (sqlite3_vfs*, const(char)* zName, sqlite3_syscall_ptr) xSetSystemCall;
    sqlite3_syscall_ptr function (sqlite3_vfs*, const(char)* zName) xGetSystemCall;
    const(char)* function (sqlite3_vfs*, const(char)* zName) xNextSystemCall;
}

enum SQLITE_ACCESS_EXISTS = 0;
enum SQLITE_ACCESS_READWRITE = 1;
enum SQLITE_ACCESS_READ = 2;

enum SQLITE_SHM_UNLOCK = 1;
enum SQLITE_SHM_LOCK = 2;
enum SQLITE_SHM_SHARED = 4;
enum SQLITE_SHM_EXCLUSIVE = 8;

enum SQLITE_SHM_NLOCK = 8;

int sqlite3_initialize ();
int sqlite3_shutdown ();
int sqlite3_os_init ();
int sqlite3_os_end ();

int sqlite3_config (int, ...);

int sqlite3_db_config (sqlite3*, int op, ...);

struct sqlite3_mem_methods
{
    void* function (int) xMalloc;
    void function (void*) xFree;
    void* function (void*, int) xRealloc;
    int function (void*) xSize;
    int function (int) xRoundup;
    int function (void*) xInit;
    void function (void*) xShutdown;
    void* pAppData;
}

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
enum SQLITE_CONFIG_URI = 17;
enum SQLITE_CONFIG_PCACHE2 = 18;
enum SQLITE_CONFIG_GETPCACHE2 = 19;
enum SQLITE_CONFIG_COVERING_INDEX_SCAN = 20;
enum SQLITE_CONFIG_SQLLOG = 21;
enum SQLITE_CONFIG_MMAP_SIZE = 22;
enum SQLITE_CONFIG_WIN32_HEAPSIZE = 23;
enum SQLITE_CONFIG_PCACHE_HDRSZ = 24;
enum SQLITE_CONFIG_PMASZ = 25;
enum SQLITE_CONFIG_STMTJRNL_SPILL = 26;

enum SQLITE_DBCONFIG_MAINDBNAME = 1000;
enum SQLITE_DBCONFIG_LOOKASIDE = 1001;
enum SQLITE_DBCONFIG_ENABLE_FKEY = 1002;
enum SQLITE_DBCONFIG_ENABLE_TRIGGER = 1003;
enum SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER = 1004;
enum SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION = 1005;
enum SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE = 1006;

int sqlite3_extended_result_codes (sqlite3*, int onoff);

sqlite3_int64 sqlite3_last_insert_rowid (sqlite3*);

int sqlite3_changes (sqlite3*);

int sqlite3_total_changes (sqlite3*);

void sqlite3_interrupt (sqlite3*);

int sqlite3_complete (const(char)* sql);
int sqlite3_complete16 (const(void)* sql);

int sqlite3_busy_handler (sqlite3*, int function (void*, int), void*);

int sqlite3_busy_timeout (sqlite3*, int ms);

int sqlite3_get_table (
    sqlite3* db,
    const(char)* zSql,
    char*** pazResult,
    int* pnRow,
    int* pnColumn,
    char** pzErrmsg);
void sqlite3_free_table (char** result);

char* sqlite3_mprintf (const(char)*, ...);
char* sqlite3_vmprintf (const(char)*, va_list);
char* sqlite3_snprintf (int, char*, const(char)*, ...);
char* sqlite3_vsnprintf (int, char*, const(char)*, va_list);

void* sqlite3_malloc (int);
void* sqlite3_malloc64 (sqlite3_uint64);
void* sqlite3_realloc (void*, int);
void* sqlite3_realloc64 (void*, sqlite3_uint64);
void sqlite3_free (void*);
sqlite3_uint64 sqlite3_msize (void*);

sqlite3_int64 sqlite3_memory_used ();
sqlite3_int64 sqlite3_memory_highwater (int resetFlag);

void sqlite3_randomness (int N, void* P);

int sqlite3_set_authorizer (
    sqlite3*,
    int function (void*, int, const(char)*, const(char)*, const(char)*, const(char)*) xAuth,
    void* pUserData);

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
enum SQLITE_RECURSIVE = 33;

void* sqlite3_trace (
    sqlite3*,
    void function (void*, const(char)*) xTrace,
    void*);
void* sqlite3_profile (
    sqlite3*,
    void function (void*, const(char)*, sqlite3_uint64) xProfile,
    void*);

enum SQLITE_TRACE_STMT = 0x01;
enum SQLITE_TRACE_PROFILE = 0x02;
enum SQLITE_TRACE_ROW = 0x04;
enum SQLITE_TRACE_CLOSE = 0x08;

int sqlite3_trace_v2 (
    sqlite3*,
    uint uMask,
    int function (uint, void*, void*, void*) xCallback,
    void* pCtx);

void sqlite3_progress_handler (sqlite3*, int, int function (void*), void*);

int sqlite3_open (const(char)* filename, sqlite3** ppDb);
int sqlite3_open16 (const(void)* filename, sqlite3** ppDb);
int sqlite3_open_v2 (
    const(char)* filename,
    sqlite3** ppDb,
    int flags,
    const(char)* zVfs);

const(char)* sqlite3_uri_parameter (const(char)* zFilename, const(char)* zParam);
int sqlite3_uri_boolean (const(char)* zFile, const(char)* zParam, int bDefault);
sqlite3_int64 sqlite3_uri_int64 (const(char)*, const(char)*, sqlite3_int64);

int sqlite3_errcode (sqlite3* db);
int sqlite3_extended_errcode (sqlite3* db);
const(char)* sqlite3_errmsg (sqlite3*);
const(void)* sqlite3_errmsg16 (sqlite3*);
const(char)* sqlite3_errstr (int);

int sqlite3_limit (sqlite3*, int id, int newVal);

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
enum SQLITE_LIMIT_WORKER_THREADS = 11;

int sqlite3_prepare (
    sqlite3* db,
    const(char)* zSql,
    int nByte,
    sqlite3_stmt** ppStmt,
    const(char*)* pzTail);
int sqlite3_prepare_v2 (
    sqlite3* db,
    const(char)* zSql,
    int nByte,
    sqlite3_stmt** ppStmt,
    const(char*)* pzTail);
int sqlite3_prepare16 (
    sqlite3* db,
    const(void)* zSql,
    int nByte,
    sqlite3_stmt** ppStmt,
    const(void*)* pzTail);
int sqlite3_prepare16_v2 (
    sqlite3* db,
    const(void)* zSql,
    int nByte,
    sqlite3_stmt** ppStmt,
    const(void*)* pzTail);

const(char)* sqlite3_sql (sqlite3_stmt* pStmt);
char* sqlite3_expanded_sql (sqlite3_stmt* pStmt);

int sqlite3_stmt_readonly (sqlite3_stmt* pStmt);

int sqlite3_stmt_busy (sqlite3_stmt*);

struct Mem;
alias Mem sqlite3_value;

int sqlite3_bind_blob (sqlite3_stmt*, int, const(void)*, int n, void function (void*));
int sqlite3_bind_blob64 (
    sqlite3_stmt*,
    int,
    const(void)*,
    sqlite3_uint64,
    void function (void*));
int sqlite3_bind_double (sqlite3_stmt*, int, double);
int sqlite3_bind_int (sqlite3_stmt*, int, int);
int sqlite3_bind_int64 (sqlite3_stmt*, int, sqlite3_int64);
int sqlite3_bind_null (sqlite3_stmt*, int);
int sqlite3_bind_text (sqlite3_stmt*, int, const(char)*, int, void function (void*));
int sqlite3_bind_text16 (sqlite3_stmt*, int, const(void)*, int, void function (void*));
int sqlite3_bind_text64 (
    sqlite3_stmt*,
    int,
    const(char)*,
    sqlite3_uint64,
    void function (void*),
    ubyte encoding);
int sqlite3_bind_value (sqlite3_stmt*, int, const(sqlite3_value)*);
int sqlite3_bind_zeroblob (sqlite3_stmt*, int, int n);
int sqlite3_bind_zeroblob64 (sqlite3_stmt*, int, sqlite3_uint64);

int sqlite3_bind_parameter_count (sqlite3_stmt*);

const(char)* sqlite3_bind_parameter_name (sqlite3_stmt*, int);

int sqlite3_bind_parameter_index (sqlite3_stmt*, const(char)* zName);

int sqlite3_clear_bindings (sqlite3_stmt*);

int sqlite3_column_count (sqlite3_stmt* pStmt);

const(char)* sqlite3_column_name (sqlite3_stmt*, int N);
const(void)* sqlite3_column_name16 (sqlite3_stmt*, int N);

const(char)* sqlite3_column_database_name (sqlite3_stmt*, int);
const(void)* sqlite3_column_database_name16 (sqlite3_stmt*, int);
const(char)* sqlite3_column_table_name (sqlite3_stmt*, int);
const(void)* sqlite3_column_table_name16 (sqlite3_stmt*, int);
const(char)* sqlite3_column_origin_name (sqlite3_stmt*, int);
const(void)* sqlite3_column_origin_name16 (sqlite3_stmt*, int);

const(char)* sqlite3_column_decltype (sqlite3_stmt*, int);
const(void)* sqlite3_column_decltype16 (sqlite3_stmt*, int);

int sqlite3_step (sqlite3_stmt*);

int sqlite3_data_count (sqlite3_stmt* pStmt);

enum SQLITE_INTEGER = 1;
enum SQLITE_FLOAT = 2;
enum SQLITE_BLOB = 4;
enum SQLITE_NULL = 5;

enum SQLITE_TEXT = 3;

enum SQLITE3_TEXT = 3;

const(void)* sqlite3_column_blob (sqlite3_stmt*, int iCol);
int sqlite3_column_bytes (sqlite3_stmt*, int iCol);
int sqlite3_column_bytes16 (sqlite3_stmt*, int iCol);
double sqlite3_column_double (sqlite3_stmt*, int iCol);
int sqlite3_column_int (sqlite3_stmt*, int iCol);
sqlite3_int64 sqlite3_column_int64 (sqlite3_stmt*, int iCol);
const(char)* sqlite3_column_text (sqlite3_stmt*, int iCol); // DSTEP Manual fix
const(void)* sqlite3_column_text16 (sqlite3_stmt*, int iCol);
int sqlite3_column_type (sqlite3_stmt*, int iCol);
sqlite3_value* sqlite3_column_value (sqlite3_stmt*, int iCol);

int sqlite3_finalize (sqlite3_stmt* pStmt);

int sqlite3_reset (sqlite3_stmt* pStmt);

int sqlite3_create_function (
    sqlite3* db,
    const(char)* zFunctionName,
    int nArg,
    int eTextRep,
    void* pApp,
    void function (sqlite3_context*, int, sqlite3_value**) xFunc,
    void function (sqlite3_context*, int, sqlite3_value**) xStep,
    void function (sqlite3_context*) xFinal);
int sqlite3_create_function16 (
    sqlite3* db,
    const(void)* zFunctionName,
    int nArg,
    int eTextRep,
    void* pApp,
    void function (sqlite3_context*, int, sqlite3_value**) xFunc,
    void function (sqlite3_context*, int, sqlite3_value**) xStep,
    void function (sqlite3_context*) xFinal);
int sqlite3_create_function_v2 (
    sqlite3* db,
    const(char)* zFunctionName,
    int nArg,
    int eTextRep,
    void* pApp,
    void function (sqlite3_context*, int, sqlite3_value**) xFunc,
    void function (sqlite3_context*, int, sqlite3_value**) xStep,
    void function (sqlite3_context*) xFinal,
    void function (void*) xDestroy);

enum SQLITE_UTF8 = 1;
enum SQLITE_UTF16LE = 2;
enum SQLITE_UTF16BE = 3;
enum SQLITE_UTF16 = 4;
enum SQLITE_ANY = 5;
enum SQLITE_UTF16_ALIGNED = 8;

enum SQLITE_DETERMINISTIC = 0x800;

int sqlite3_aggregate_count (sqlite3_context*);
int sqlite3_expired (sqlite3_stmt*);
int sqlite3_transfer_bindings (sqlite3_stmt*, sqlite3_stmt*);
int sqlite3_global_recover ();
void sqlite3_thread_cleanup ();
int sqlite3_memory_alarm (
    void function (void*, sqlite3_int64, int),
    void*,
    sqlite3_int64);

const(void)* sqlite3_value_blob (sqlite3_value*);
int sqlite3_value_bytes (sqlite3_value*);
int sqlite3_value_bytes16 (sqlite3_value*);
double sqlite3_value_double (sqlite3_value*);
int sqlite3_value_int (sqlite3_value*);
sqlite3_int64 sqlite3_value_int64 (sqlite3_value*);
const(ubyte)* sqlite3_value_text (sqlite3_value*);
const(void)* sqlite3_value_text16 (sqlite3_value*);
const(void)* sqlite3_value_text16le (sqlite3_value*);
const(void)* sqlite3_value_text16be (sqlite3_value*);
int sqlite3_value_type (sqlite3_value*);
int sqlite3_value_numeric_type (sqlite3_value*);

uint sqlite3_value_subtype (sqlite3_value*);

sqlite3_value* sqlite3_value_dup (const(sqlite3_value)*);
void sqlite3_value_free (sqlite3_value*);

void* sqlite3_aggregate_context (sqlite3_context*, int nBytes);

void* sqlite3_user_data (sqlite3_context*);

sqlite3* sqlite3_context_db_handle (sqlite3_context*);

void* sqlite3_get_auxdata (sqlite3_context*, int N);
void sqlite3_set_auxdata (sqlite3_context*, int N, void*, void function (void*));

alias void function (void*) sqlite3_destructor_type;
enum SQLITE_STATIC = cast(sqlite3_destructor_type) 0;
enum SQLITE_TRANSIENT = cast(sqlite3_destructor_type) -1;

void sqlite3_result_blob (sqlite3_context*, const(void)*, int, void function (void*));
void sqlite3_result_blob64 (
    sqlite3_context*,
    const(void)*,
    sqlite3_uint64,
    void function (void*));
void sqlite3_result_double (sqlite3_context*, double);
void sqlite3_result_error (sqlite3_context*, const(char)*, int);
void sqlite3_result_error16 (sqlite3_context*, const(void)*, int);
void sqlite3_result_error_toobig (sqlite3_context*);
void sqlite3_result_error_nomem (sqlite3_context*);
void sqlite3_result_error_code (sqlite3_context*, int);
void sqlite3_result_int (sqlite3_context*, int);
void sqlite3_result_int64 (sqlite3_context*, sqlite3_int64);
void sqlite3_result_null (sqlite3_context*);
void sqlite3_result_text (sqlite3_context*, const(char)*, int, void function (void*));
void sqlite3_result_text64 (
    sqlite3_context*,
    const(char)*,
    sqlite3_uint64,
    void function (void*),
    ubyte encoding);
void sqlite3_result_text16 (sqlite3_context*, const(void)*, int, void function (void*));
void sqlite3_result_text16le (sqlite3_context*, const(void)*, int, void function (void*));
void sqlite3_result_text16be (sqlite3_context*, const(void)*, int, void function (void*));
void sqlite3_result_value (sqlite3_context*, sqlite3_value*);
void sqlite3_result_zeroblob (sqlite3_context*, int n);
int sqlite3_result_zeroblob64 (sqlite3_context*, sqlite3_uint64 n);

void sqlite3_result_subtype (sqlite3_context*, uint);

int sqlite3_create_collation (
    sqlite3*,
    const(char)* zName,
    int eTextRep,
    void* pArg,
    int function (void*, int, const(void)*, int, const(void)*) xCompare);
int sqlite3_create_collation_v2 (
    sqlite3*,
    const(char)* zName,
    int eTextRep,
    void* pArg,
    int function (void*, int, const(void)*, int, const(void)*) xCompare,
    void function (void*) xDestroy);
int sqlite3_create_collation16 (
    sqlite3*,
    const(void)* zName,
    int eTextRep,
    void* pArg,
    int function (void*, int, const(void)*, int, const(void)*) xCompare);

int sqlite3_collation_needed (
    sqlite3*,
    void*,
    void function (void*, sqlite3*, int eTextRep, const(char)*));
int sqlite3_collation_needed16 (
    sqlite3*,
    void*,
    void function (void*, sqlite3*, int eTextRep, const(void)*));

int sqlite3_sleep (int);

extern __gshared char* sqlite3_temp_directory;

extern __gshared char* sqlite3_data_directory;

int sqlite3_get_autocommit (sqlite3*);

sqlite3* sqlite3_db_handle (sqlite3_stmt*);

const(char)* sqlite3_db_filename (sqlite3* db, const(char)* zDbName);

int sqlite3_db_readonly (sqlite3* db, const(char)* zDbName);

sqlite3_stmt* sqlite3_next_stmt (sqlite3* pDb, sqlite3_stmt* pStmt);

void* sqlite3_commit_hook (sqlite3*, int function (void*), void*);
void* sqlite3_rollback_hook (sqlite3*, void function (void*), void*);

void* sqlite3_update_hook (
    sqlite3*,
    void function (void*, int, const(char)*, const(char)*, sqlite3_int64),
    void*);

int sqlite3_enable_shared_cache (int);

int sqlite3_release_memory (int);

int sqlite3_db_release_memory (sqlite3*);

sqlite3_int64 sqlite3_soft_heap_limit64 (sqlite3_int64 N);

void sqlite3_soft_heap_limit (int N);

int sqlite3_table_column_metadata (
    sqlite3* db,
    const(char)* zDbName,
    const(char)* zTableName,
    const(char)* zColumnName,
    const(char*)* pzDataType,
    const(char*)* pzCollSeq,
    int* pNotNull,
    int* pPrimaryKey,
    int* pAutoinc);

int sqlite3_load_extension (
    sqlite3* db,
    const(char)* zFile,
    const(char)* zProc,
    char** pzErrMsg);

int sqlite3_enable_load_extension (sqlite3* db, int onoff);

int sqlite3_auto_extension (void function () xEntryPoint);

int sqlite3_cancel_auto_extension (void function () xEntryPoint);

void sqlite3_reset_auto_extension ();

struct sqlite3_module
{
    int iVersion;
    int function (sqlite3*, void* pAux, int argc, const(char*)* argv, sqlite3_vtab** ppVTab, char**) xCreate;
    int function (sqlite3*, void* pAux, int argc, const(char*)* argv, sqlite3_vtab** ppVTab, char**) xConnect;
    int function (sqlite3_vtab* pVTab, sqlite3_index_info*) xBestIndex;
    int function (sqlite3_vtab* pVTab) xDisconnect;
    int function (sqlite3_vtab* pVTab) xDestroy;
    int function (sqlite3_vtab* pVTab, sqlite3_vtab_cursor** ppCursor) xOpen;
    int function (sqlite3_vtab_cursor*) xClose;
    int function (sqlite3_vtab_cursor*, int idxNum, const(char)* idxStr, int argc, sqlite3_value** argv) xFilter;
    int function (sqlite3_vtab_cursor*) xNext;
    int function (sqlite3_vtab_cursor*) xEof;
    int function (sqlite3_vtab_cursor*, sqlite3_context*, int) xColumn;
    int function (sqlite3_vtab_cursor*, sqlite3_int64* pRowid) xRowid;
    int function (sqlite3_vtab*, int, sqlite3_value**, sqlite3_int64*) xUpdate;
    int function (sqlite3_vtab* pVTab) xBegin;
    int function (sqlite3_vtab* pVTab) xSync;
    int function (sqlite3_vtab* pVTab) xCommit;
    int function (sqlite3_vtab* pVTab) xRollback;
    int function (sqlite3_vtab* pVtab, int nArg, const(char)* zName, void function (sqlite3_context*, int, sqlite3_value**)* pxFunc, void** ppArg) xFindFunction;
    int function (sqlite3_vtab* pVtab, const(char)* zNew) xRename;

    int function (sqlite3_vtab* pVTab, int) xSavepoint;
    int function (sqlite3_vtab* pVTab, int) xRelease;
    int function (sqlite3_vtab* pVTab, int) xRollbackTo;
}

struct sqlite3_index_info
{
    int nConstraint;

    struct sqlite3_index_constraint
    {
        int iColumn;
        ubyte op;
        ubyte usable;
        int iTermOffset;
    }

    sqlite3_index_constraint* aConstraint;
    int nOrderBy;

    struct sqlite3_index_orderby
    {
        int iColumn;
        ubyte desc;
    }

    sqlite3_index_orderby* aOrderBy;

    struct sqlite3_index_constraint_usage
    {
        int argvIndex;
        ubyte omit;
    }

    sqlite3_index_constraint_usage* aConstraintUsage;
    int idxNum;
    char* idxStr;
    int needToFreeIdxStr;
    int orderByConsumed;
    double estimatedCost;

    sqlite3_int64 estimatedRows;

    int idxFlags;

    sqlite3_uint64 colUsed;
}

enum SQLITE_INDEX_SCAN_UNIQUE = 1;

enum SQLITE_INDEX_CONSTRAINT_EQ = 2;
enum SQLITE_INDEX_CONSTRAINT_GT = 4;
enum SQLITE_INDEX_CONSTRAINT_LE = 8;
enum SQLITE_INDEX_CONSTRAINT_LT = 16;
enum SQLITE_INDEX_CONSTRAINT_GE = 32;
enum SQLITE_INDEX_CONSTRAINT_MATCH = 64;
enum SQLITE_INDEX_CONSTRAINT_LIKE = 65;
enum SQLITE_INDEX_CONSTRAINT_GLOB = 66;
enum SQLITE_INDEX_CONSTRAINT_REGEXP = 67;

int sqlite3_create_module (
    sqlite3* db,
    const(char)* zName,
    const(sqlite3_module)* p,
    void* pClientData);
int sqlite3_create_module_v2 (
    sqlite3* db,
    const(char)* zName,
    const(sqlite3_module)* p,
    void* pClientData,
    void function (void*) xDestroy);

struct sqlite3_vtab
{
    const(sqlite3_module)* pModule;
    int nRef;
    char* zErrMsg;
}

struct sqlite3_vtab_cursor
{
    sqlite3_vtab* pVtab;
}

int sqlite3_declare_vtab (sqlite3*, const(char)* zSQL);

int sqlite3_overload_function (sqlite3*, const(char)* zFuncName, int nArg);

int sqlite3_blob_open (
    sqlite3*,
    const(char)* zDb,
    const(char)* zTable,
    const(char)* zColumn,
    sqlite3_int64 iRow,
    int flags,
    sqlite3_blob** ppBlob);

int sqlite3_blob_reopen (sqlite3_blob*, sqlite3_int64);

int sqlite3_blob_close (sqlite3_blob*);

int sqlite3_blob_bytes (sqlite3_blob*);

int sqlite3_blob_read (sqlite3_blob*, void* Z, int N, int iOffset);

int sqlite3_blob_write (sqlite3_blob*, const(void)* z, int n, int iOffset);

sqlite3_vfs* sqlite3_vfs_find (const(char)* zVfsName);
int sqlite3_vfs_register (sqlite3_vfs*, int makeDflt);
int sqlite3_vfs_unregister (sqlite3_vfs*);

sqlite3_mutex* sqlite3_mutex_alloc (int);
void sqlite3_mutex_free (sqlite3_mutex*);
void sqlite3_mutex_enter (sqlite3_mutex*);
int sqlite3_mutex_try (sqlite3_mutex*);
void sqlite3_mutex_leave (sqlite3_mutex*);

struct sqlite3_mutex_methods
{
    int function () xMutexInit;
    int function () xMutexEnd;
    sqlite3_mutex* function (int) xMutexAlloc;
    void function (sqlite3_mutex*) xMutexFree;
    void function (sqlite3_mutex*) xMutexEnter;
    int function (sqlite3_mutex*) xMutexTry;
    void function (sqlite3_mutex*) xMutexLeave;
    int function (sqlite3_mutex*) xMutexHeld;
    int function (sqlite3_mutex*) xMutexNotheld;
}

int sqlite3_mutex_held (sqlite3_mutex*);
int sqlite3_mutex_notheld (sqlite3_mutex*);

enum SQLITE_MUTEX_FAST = 0;
enum SQLITE_MUTEX_RECURSIVE = 1;
enum SQLITE_MUTEX_STATIC_MASTER = 2;
enum SQLITE_MUTEX_STATIC_MEM = 3;
enum SQLITE_MUTEX_STATIC_MEM2 = 4;
enum SQLITE_MUTEX_STATIC_OPEN = 4;
enum SQLITE_MUTEX_STATIC_PRNG = 5;
enum SQLITE_MUTEX_STATIC_LRU = 6;
enum SQLITE_MUTEX_STATIC_LRU2 = 7;
enum SQLITE_MUTEX_STATIC_PMEM = 7;
enum SQLITE_MUTEX_STATIC_APP1 = 8;
enum SQLITE_MUTEX_STATIC_APP2 = 9;
enum SQLITE_MUTEX_STATIC_APP3 = 10;
enum SQLITE_MUTEX_STATIC_VFS1 = 11;
enum SQLITE_MUTEX_STATIC_VFS2 = 12;
enum SQLITE_MUTEX_STATIC_VFS3 = 13;

sqlite3_mutex* sqlite3_db_mutex (sqlite3*);

int sqlite3_file_control (sqlite3*, const(char)* zDbName, int op, void*);

int sqlite3_test_control (int op, ...);

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
enum SQLITE_TESTCTRL_SCRATCHMALLOC = 17;
enum SQLITE_TESTCTRL_LOCALTIME_FAULT = 18;
enum SQLITE_TESTCTRL_EXPLAIN_STMT = 19;
enum SQLITE_TESTCTRL_ONCE_RESET_THRESHOLD = 19;
enum SQLITE_TESTCTRL_NEVER_CORRUPT = 20;
enum SQLITE_TESTCTRL_VDBE_COVERAGE = 21;
enum SQLITE_TESTCTRL_BYTEORDER = 22;
enum SQLITE_TESTCTRL_ISINIT = 23;
enum SQLITE_TESTCTRL_SORTER_MMAP = 24;
enum SQLITE_TESTCTRL_IMPOSTER = 25;
enum SQLITE_TESTCTRL_LAST = 25;

int sqlite3_status (int op, int* pCurrent, int* pHighwater, int resetFlag);
int sqlite3_status64 (
    int op,
    sqlite3_int64* pCurrent,
    sqlite3_int64* pHighwater,
    int resetFlag);

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

int sqlite3_db_status (sqlite3*, int op, int* pCur, int* pHiwtr, int resetFlg);

enum SQLITE_DBSTATUS_LOOKASIDE_USED = 0;
enum SQLITE_DBSTATUS_CACHE_USED = 1;
enum SQLITE_DBSTATUS_SCHEMA_USED = 2;
enum SQLITE_DBSTATUS_STMT_USED = 3;
enum SQLITE_DBSTATUS_LOOKASIDE_HIT = 4;
enum SQLITE_DBSTATUS_LOOKASIDE_MISS_SIZE = 5;
enum SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL = 6;
enum SQLITE_DBSTATUS_CACHE_HIT = 7;
enum SQLITE_DBSTATUS_CACHE_MISS = 8;
enum SQLITE_DBSTATUS_CACHE_WRITE = 9;
enum SQLITE_DBSTATUS_DEFERRED_FKS = 10;
enum SQLITE_DBSTATUS_CACHE_USED_SHARED = 11;
enum SQLITE_DBSTATUS_MAX = 11;

int sqlite3_stmt_status (sqlite3_stmt*, int op, int resetFlg);

enum SQLITE_STMTSTATUS_FULLSCAN_STEP = 1;
enum SQLITE_STMTSTATUS_SORT = 2;
enum SQLITE_STMTSTATUS_AUTOINDEX = 3;
enum SQLITE_STMTSTATUS_VM_STEP = 4;

struct sqlite3_pcache_page
{
    void* pBuf;
    void* pExtra;
}

struct sqlite3_pcache_methods2
{
    int iVersion;
    void* pArg;
    int function (void*) xInit;
    void function (void*) xShutdown;
    sqlite3_pcache* function (int szPage, int szExtra, int bPurgeable) xCreate;
    void function (sqlite3_pcache*, int nCachesize) xCachesize;
    int function (sqlite3_pcache*) xPagecount;
    sqlite3_pcache_page* function (sqlite3_pcache*, uint key, int createFlag) xFetch;
    void function (sqlite3_pcache*, sqlite3_pcache_page*, int discard) xUnpin;
    void function (sqlite3_pcache*, sqlite3_pcache_page*, uint oldKey, uint newKey) xRekey;
    void function (sqlite3_pcache*, uint iLimit) xTruncate;
    void function (sqlite3_pcache*) xDestroy;
    void function (sqlite3_pcache*) xShrink;
}

struct sqlite3_pcache_methods
{
    void* pArg;
    int function (void*) xInit;
    void function (void*) xShutdown;
    sqlite3_pcache* function (int szPage, int bPurgeable) xCreate;
    void function (sqlite3_pcache*, int nCachesize) xCachesize;
    int function (sqlite3_pcache*) xPagecount;
    void* function (sqlite3_pcache*, uint key, int createFlag) xFetch;
    void function (sqlite3_pcache*, void*, int discard) xUnpin;
    void function (sqlite3_pcache*, void*, uint oldKey, uint newKey) xRekey;
    void function (sqlite3_pcache*, uint iLimit) xTruncate;
    void function (sqlite3_pcache*) xDestroy;
}

sqlite3_backup* sqlite3_backup_init (
    sqlite3* pDest,
    const(char)* zDestName,
    sqlite3* pSource,
    const(char)* zSourceName);
int sqlite3_backup_step (sqlite3_backup* p, int nPage);
int sqlite3_backup_finish (sqlite3_backup* p);
int sqlite3_backup_remaining (sqlite3_backup* p);
int sqlite3_backup_pagecount (sqlite3_backup* p);

int sqlite3_unlock_notify (
    sqlite3* pBlocked,
    void function (void** apArg, int nArg) xNotify,
    void* pNotifyArg);

int sqlite3_stricmp (const(char)*, const(char)*);
int sqlite3_strnicmp (const(char)*, const(char)*, int);

int sqlite3_strglob (const(char)* zGlob, const(char)* zStr);

int sqlite3_strlike (const(char)* zGlob, const(char)* zStr, uint cEsc);

void sqlite3_log (int iErrCode, const(char)* zFormat, ...);

void* sqlite3_wal_hook (
    sqlite3*,
    int function (void*, sqlite3*, const(char)*, int),
    void*);

int sqlite3_wal_autocheckpoint (sqlite3* db, int N);

int sqlite3_wal_checkpoint (sqlite3* db, const(char)* zDb);

int sqlite3_wal_checkpoint_v2 (
    sqlite3* db,
    const(char)* zDb,
    int eMode,
    int* pnLog,
    int* pnCkpt);

enum SQLITE_CHECKPOINT_PASSIVE = 0;
enum SQLITE_CHECKPOINT_FULL = 1;
enum SQLITE_CHECKPOINT_RESTART = 2;
enum SQLITE_CHECKPOINT_TRUNCATE = 3;

int sqlite3_vtab_config (sqlite3*, int op, ...);

enum SQLITE_VTAB_CONSTRAINT_SUPPORT = 1;

int sqlite3_vtab_on_conflict (sqlite3*);

enum SQLITE_ROLLBACK = 1;

enum SQLITE_FAIL = 3;

enum SQLITE_REPLACE = 5;

enum SQLITE_SCANSTAT_NLOOP = 0;
enum SQLITE_SCANSTAT_NVISIT = 1;
enum SQLITE_SCANSTAT_EST = 2;
enum SQLITE_SCANSTAT_NAME = 3;
enum SQLITE_SCANSTAT_EXPLAIN = 4;
enum SQLITE_SCANSTAT_SELECTID = 5;

int sqlite3_stmt_scanstatus (
    sqlite3_stmt* pStmt,
    int idx,
    int iScanStatusOp,
    void* pOut);

void sqlite3_stmt_scanstatus_reset (sqlite3_stmt*);

int sqlite3_db_cacheflush (sqlite3*);

int sqlite3_system_errno (sqlite3*);

struct sqlite3_snapshot
{
    ubyte[48] hidden;
}

int sqlite3_snapshot_get (
    sqlite3* db,
    const(char)* zSchema,
    sqlite3_snapshot** ppSnapshot);

int sqlite3_snapshot_open (
    sqlite3* db,
    const(char)* zSchema,
    sqlite3_snapshot* pSnapshot);

void sqlite3_snapshot_free (sqlite3_snapshot*);

int sqlite3_snapshot_cmp (sqlite3_snapshot* p1, sqlite3_snapshot* p2);

int sqlite3_snapshot_recover (sqlite3* db, const(char)* zDb);

alias double sqlite3_rtree_dbl;

int sqlite3_rtree_geometry_callback (
    sqlite3* db,
    const(char)* zGeom,
    int function (sqlite3_rtree_geometry*, int, sqlite3_rtree_dbl*, int*) xGeom,
    void* pContext);

struct sqlite3_rtree_geometry
{
    void* pContext;
    int nParam;
    sqlite3_rtree_dbl* aParam;
    void* pUser;
    void function (void*) xDelUser;
}

int sqlite3_rtree_query_callback (
    sqlite3* db,
    const(char)* zQueryFunc,
    int function (sqlite3_rtree_query_info*) xQueryFunc,
    void* pContext,
    void function (void*) xDestructor);

struct sqlite3_rtree_query_info
{
    void* pContext;
    int nParam;
    sqlite3_rtree_dbl* aParam;
    void* pUser;
    void function (void*) xDelUser;
    sqlite3_rtree_dbl* aCoord;
    uint* anQueue;
    int nCoord;
    int iLevel;
    int mxLevel;
    sqlite3_int64 iRowid;
    sqlite3_rtree_dbl rParentScore;
    int eParentWithin;
    int eWithin;
    sqlite3_rtree_dbl rScore;

    sqlite3_value** apSqlParam;
}

enum NOT_WITHIN = 0;
enum PARTLY_WITHIN = 1;
enum FULLY_WITHIN = 2;

alias void function (const(Fts5ExtensionApi)* pApi, Fts5Context* pFts, sqlite3_context* pCtx, int nVal, sqlite3_value** apVal) fts5_extension_function;

struct Fts5PhraseIter
{
    const(ubyte)* a;
    const(ubyte)* b;
}

struct Fts5ExtensionApi
{
    int iVersion;

    void* function (Fts5Context*) xUserData;

    int function (Fts5Context*) xColumnCount;
    int function (Fts5Context*, sqlite3_int64* pnRow) xRowCount;
    int function (Fts5Context*, int iCol, sqlite3_int64* pnToken) xColumnTotalSize;

    int function (Fts5Context*, const(char)* pText, int nText, void* pCtx, int function (void*, int, const(char)*, int, int, int) xToken) xTokenize;

    int function (Fts5Context*) xPhraseCount;
    int function (Fts5Context*, int iPhrase) xPhraseSize;

    int function (Fts5Context*, int* pnInst) xInstCount;
    int function (Fts5Context*, int iIdx, int* piPhrase, int* piCol, int* piOff) xInst;

    sqlite3_int64 function (Fts5Context*) xRowid;
    int function (Fts5Context*, int iCol, const(char*)* pz, int* pn) xColumnText;
    int function (Fts5Context*, int iCol, int* pnToken) xColumnSize;

    int function (Fts5Context*, int iPhrase, void* pUserData, int function (const(Fts5ExtensionApi)*, Fts5Context*, void*)) xQueryPhrase;
    int function (Fts5Context*, void* pAux, void function (void*) xDelete) xSetAuxdata;
    void* function (Fts5Context*, int bClear) xGetAuxdata;

    int function (Fts5Context*, int iPhrase, Fts5PhraseIter*, int*, int*) xPhraseFirst;
    void function (Fts5Context*, Fts5PhraseIter*, int* piCol, int* piOff) xPhraseNext;

    int function (Fts5Context*, int iPhrase, Fts5PhraseIter*, int*) xPhraseFirstColumn;
    void function (Fts5Context*, Fts5PhraseIter*, int* piCol) xPhraseNextColumn;
}

struct fts5_tokenizer
{
    int function (void*, const(char*)* azArg, int nArg, Fts5Tokenizer** ppOut) xCreate;
    void function (Fts5Tokenizer*) xDelete;
    int function (Fts5Tokenizer*, void* pCtx, int flags, const(char)* pText, int nText, int function (void* pCtx, int tflags, const(char)* pToken, int nToken, int iStart, int iEnd) xToken) xTokenize;
}

enum FTS5_TOKENIZE_QUERY = 0x0001;
enum FTS5_TOKENIZE_PREFIX = 0x0002;
enum FTS5_TOKENIZE_DOCUMENT = 0x0004;
enum FTS5_TOKENIZE_AUX = 0x0008;

enum FTS5_TOKEN_COLOCATED = 0x0001;

struct fts5_api
{
    int iVersion;

    int function (fts5_api* pApi, const(char)* zName, void* pContext, fts5_tokenizer* pTokenizer, void function (void*) xDestroy) xCreateTokenizer;

    int function (fts5_api* pApi, const(char)* zName, void** ppContext, fts5_tokenizer* pTokenizer) xFindTokenizer;

    int function (fts5_api* pApi, const(char)* zName, void* pContext, fts5_extension_function xFunction, void function (void*) xDestroy) xCreateFunction;
}
