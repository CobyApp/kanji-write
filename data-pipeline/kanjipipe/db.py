import sqlite3

from kanjipipe.schema import DDL


def init_db(path: str) -> sqlite3.Connection:
    """Open (or create) a SQLite database at *path*, apply the schema, and return the connection.

    Pass ``":memory:"`` for an in-process throwaway database (useful in tests).
    The caller owns the returned connection and is responsible for closing it.
    Foreign keys are enabled on every connection returned by this function.
    """
    conn = sqlite3.connect(path)
    conn.execute("PRAGMA foreign_keys = ON")
    conn.executescript(DDL)
    conn.commit()
    return conn
