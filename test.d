import std.stdio;

struct OpIndexAssign {
    void opIndexAssign(uint val, uint index) {}
    uint opIndex(uint index) { return 42; }
}

struct Struct {
    OpIndexAssign oas;

    OpIndexAssign getter() @property {
        return oas;
    }
}

void main() {
    Struct s;
    s.oas[5] = 5;  // Works
    s.getter()[5] = 5;  // Fails
}

__EOF__ 

struct Param {
    void opIndexAssign(string value, string key) {
        writeln(key, " = ", value);
    }
}

struct Thing {
    Param _params;
    
    @property Param params() {
        return _params;
    }
}

void main() {
    Thing thing;
    thing.params()["name"] = "Thing"; // OK
    thing.params["name"] = "Thing"; // Error: no [] operator overload for type Param
}