import std.algorithm, std.stdio;

struct S {}

struct A {
    private struct inner {
        char dummy;
        S* s;
        int blabla;
    }
    inner i;
    
    this(int foo) {
        i.s = new S;
    }
    
    void opAssign(A rhs) {
        swap(i, rhs.i);
    }
    
    void useIt() {
        assert(i.s);
    }
}

void main() {
    A a = A(1);
    auto a2 = a;
    a.useIt;
    a2.useIt;
}