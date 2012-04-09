module sformat;

import std.conv;
import std.string;

string render(string templ, string[string] args)
{
    string markupStart = "@{";
    string markuEnd = "}";
    
    string result;
    auto str = templ;
    while (true)
    {
        auto p_start = str.indexOf(markupStart);
        if (p_start < 0)
        {
            result ~= str;
            break;
        }
        else
        {
            result ~= str[0 .. p_start];
            str = str[p_start + markupStart.length .. $];
            
            auto p_end = str.indexOf(markuEnd);
            if (p_end < 0)
                assert(false, "Tag misses ending }");
            auto key = strip(str[0 .. p_end]);
            
            auto value = key in args;
            if (!value)
                assert(false, "Key '" ~ key ~ "' has no associated value");
            result ~= *value;
            
            str = str[p_end + markuEnd.length .. $];
        }
    }
    
    return result;
}

unittest
{
    enum tpl = q{
        string @{function_name}() {
            return "Hello world!";
        }
    };
    mixin(render(tpl, ["function_name": "hello_world"]));
    static assert(hello_world() == "Hello world!");
}
