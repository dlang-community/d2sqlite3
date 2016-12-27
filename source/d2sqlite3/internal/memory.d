module d2sqlite3.internal.memory;

import std.traits : isFunctionPointer, isDelegate, isCallable;
import core.memory : GC;
import core.stdc.stdlib : malloc, free;

package(d2sqlite3):

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