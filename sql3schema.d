/++
Example:
---

struct Student {
    string first_name;
    string last_name;
    int group;
    double mark;
    ubyte[] picture;
}

auto db = Database(":memory:");
db.createTable!Student();
---

Equivalent to SQL:
---
CREATE TABLE student (
    id INTEGER PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    mark FLOAT,
    picture BLOB
)
---

+/
module sql3schema;

import sqlite3;

