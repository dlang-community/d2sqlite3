import std.stdio;

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