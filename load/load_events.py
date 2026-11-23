"""Loads play-event files into the warehouse's raw tables (docs/analytics-design.md, section 6.4).

    python load/load_events.py data/real              real events, from `node infra/deploy.mjs events`
    python load/load_events.py data/simulated         simulated events, from the simulator in game/
    python load/load_events.py data/real --dry-run    read and count the files, connect to nothing

Each folder goes to its own table: raw.events_real or raw.events_simulated. Real and simulated rows never share a
table, and dbt adds the source column when it unions them. A file holds one JSON event per line (.jsonl or .jsonl.gz).
Loading a file again changes nothing, because event_id is the key. Every file gets a row in raw.loads, which the source
freshness test reads. The export's last line, counts of events the server turned away, goes to raw.rejects.
"""
import gzip
import json
import os
import sys
from collections import Counter
from pathlib import Path

COLUMNS = ["event_id", "event_name", "schema_version", "player_id", "session_id", "event_seq",
           "client_ts", "sent_at", "received_at", "site", "edition", "build", "props"]


def read_lines(path):
    """The file's JSON lines, unzipped if it ends in .gz."""
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def warehouse_url():
    """WAREHOUSE_URL from the environment, or else from analytics/.env."""
    if os.environ.get("WAREHOUSE_URL"):
        return os.environ["WAREHOUSE_URL"]
    env = Path(__file__).resolve().parent.parent / ".env"
    if env.exists():
        for line in env.read_text(encoding="utf-8").splitlines():
            if line.startswith("WAREHOUSE_URL="):
                return line.split("=", 1)[1].strip()
    sys.exit("Set WAREHOUSE_URL, or copy analytics/.env.example to analytics/.env")


def create_tables(cur, table):
    cur.execute("create schema if not exists raw")
    cur.execute(f"""
        create table if not exists raw.{table} (
            event_id uuid primary key,
            event_name text not null,
            schema_version int not null,
            player_id uuid not null,
            session_id uuid not null,
            event_seq int not null,
            client_ts timestamptz not null,
            sent_at timestamptz not null,
            received_at timestamptz not null,
            site text not null,
            edition text not null,
            build text not null,
            props jsonb not null,
            _file text not null,
            _loaded_at timestamptz not null default now()
        )""")
    cur.execute("""
        create table if not exists raw.loads (
            file text primary key,
            source text not null,
            rows_in_file int not null,
            rows_new int not null,
            newest_received_at timestamptz,
            loaded_at timestamptz not null default now()
        )""")
    cur.execute("""
        create table if not exists raw.rejects (
            day date not null,
            site text not null,
            event_name text not null,
            reason text not null,
            n int not null,
            primary key (day, site, event_name, reason)
        )""")


def load_file(cur, path, table, source):
    lines = read_lines(path)
    events = [e for e in lines if "event_id" in e]
    rejects = [r for line in lines for r in line.get("rejects", [])]
    # Copy into a temporary table first, then insert what's new: a file loaded twice adds nothing.
    cur.execute(f"create temp table incoming (like raw.{table} including defaults) on commit drop")
    with cur.copy(f"copy incoming ({', '.join(COLUMNS)}, _file) from stdin") as copy:
        for e in events:
            copy.write_row([json.dumps(e[c]) if c == "props" else e[c] for c in COLUMNS] + [path.name])
    cur.execute(f"insert into raw.{table} select * from incoming on conflict (event_id) do nothing")
    new_rows = cur.rowcount
    for r in rejects:
        cur.execute("""
            insert into raw.rejects (day, site, event_name, reason, n) values (%s, %s, %s, %s, %s)
            on conflict (day, site, event_name, reason) do update set n = excluded.n""",
            [r["day"], r["site"], r["event_name"], r["reason"], r["n"]])
    newest = max((e["received_at"] for e in events), default=None)
    cur.execute("""
        insert into raw.loads (file, source, rows_in_file, rows_new, newest_received_at) values (%s, %s, %s, %s, %s)
        on conflict (file) do update set rows_new = excluded.rows_new, loaded_at = now()""",
        [path.name, source, len(events), new_rows, newest])
    return len(events), new_rows


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    folder = Path(sys.argv[1])
    source = "simulated" if folder.name == "simulated" else "real"
    table = f"events_{source}"
    files = sorted(list(folder.glob("*.jsonl")) + list(folder.glob("*.jsonl.gz")))
    if not files:
        sys.exit(f"No .jsonl or .jsonl.gz files in {folder}")

    if "--dry-run" in sys.argv:
        for path in files:
            names = Counter(e["event_name"] for e in read_lines(path) if "event_id" in e)
            print(f"{path.name}: {sum(names.values())} events {dict(names)}")
        return

    import psycopg  # only needed when loading
    with psycopg.connect(warehouse_url()) as conn:
        with conn.cursor() as cur:
            create_tables(cur, table)
        conn.commit()
        for path in files:
            with conn.cursor() as cur:
                rows, new = load_file(cur, path, table, source)
            conn.commit()
            print(f"{path.name}: {rows} events, {new} new, into raw.{table}")


if __name__ == "__main__":
    main()
