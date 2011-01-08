module test;

import sqlite;
import std.stdio, std.string;

void main() {
    auto db = SqliteDatabase(":memory:");
    auto query = SqliteQuery(db,
        "CREATE TABLE person (
            id INTEGER PRIMARY KEY,
            last_name TEXT NOT NULL,
            first_name TEXT,
            score REAL
        )");
    query.execute;
    
    with (SqliteQuery(db, "INSERT INTO person (last_name, first_name, score)
                           VALUES (:last_name, :first_name, :score)"))
    {
        bind(":last_name", "Smith");
        bind(":first_name", "Robert");
        bind(":score", 77.5);
        execute;
        reset;
        bind(":last_name", "Doe");
        bind(":first_name", "John");
        bind(":score", null);
        execute;
    }
    
    query = SqliteQuery(db, "SELECT * FROM person");
    auto rows = query.rows;
    query.reset;
    foreach (row; query.rows)
    {
        auto id = row["id"].as!int;
        auto name = format("%s %s", row["first_name"].as!string, row["last_name"].as!string);
        auto score = row["score"].as!(real, 0.0);
        writefln("[%d] %s scores %.1f", id, name, score);
    }
    
    query = SqliteQuery(db, "SELECT COUNT(*) FROM person");
    writefln("Number of persons: %d", query.rows.front[0].as!int);
}
