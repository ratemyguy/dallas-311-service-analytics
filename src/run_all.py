"""Rebuild everything: PostgreSQL database -> data-quality checks -> analysis CSVs -> charts -> dashboard data.

Usage (from the repo root):
    python -I src/run_all.py            # build from the CSVs already in data/raw/dallas_311/
    python -I src/run_all.py --fetch    # download a fresh extract from the Dallas Open Data portal first

Connection: set DATABASE_URL (default postgresql://postgres@localhost:55432/dallas311).
The database itself is created if it does not exist.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import pathlib
import re
import subprocess
import sys
import time
from zoneinfo import ZoneInfo

import psycopg

ROOT = pathlib.Path(__file__).resolve().parents[1]
RAW = ROOT / "data" / "raw" / "dallas_311"
SQL = ROOT / "sql"
RESULTS = ROOT / "results"
DEFAULT_URL = "postgresql://postgres@localhost:55432/dallas311"
RAW_COLUMNS = [
    "service_request_number", "address", "city_council_district", "department",
    "service_request_type", "ert_estimated_response_time", "overall_service_request_due_date",
    "status", "created_date", "update_date", "closed_date", "outcome", "priority",
    "method_received_description", "lat_location",
]
BUILD_STEPS = ["02_transform.sql", "03_indexes.sql", "04_analytics.sql", "05_roles.sql"]


def log(msg: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def ensure_database(url: str) -> None:
    """Create the target database if it is missing (connects to the maintenance db 'postgres')."""
    dbname = psycopg.conninfo.conninfo_to_dict(url)["dbname"]
    admin_url = psycopg.conninfo.make_conninfo(url, dbname="postgres")
    with psycopg.connect(admin_url, autocommit=True) as conn:
        exists = conn.execute("SELECT 1 FROM pg_database WHERE datname = %s", (dbname,)).fetchone()
        if not exists:
            conn.execute(psycopg.sql.SQL("CREATE DATABASE {}").format(psycopg.sql.Identifier(dbname)))
            log(f"created database {dbname}")


def run_sql_file(conn: psycopg.Connection, path: pathlib.Path) -> None:
    """Run a .sql file (several statements, no parameters -> simple query protocol)."""
    start = time.time()
    conn.execute(path.read_text())
    log(f"ran {path.relative_to(ROOT)} in {time.time() - start:.1f}s")


def record_extract_info(conn: psycopg.Connection) -> None:
    meta = json.loads((RAW / "pull_metadata.json").read_text())
    pulled_utc = dt.datetime.fromisoformat(meta["pulled_at_utc"])
    pulled_local = pulled_utc.astimezone(ZoneInfo("America/Chicago")).replace(tzinfo=None)
    conn.execute(
        "INSERT INTO core.extract_info (pulled_at_utc, pulled_at_local, source_url) VALUES (%s, %s, %s)",
        (pulled_utc, pulled_local, meta["source"]),
    )


def load_staging(conn: psycopg.Connection) -> None:
    """Bulk-load every raw CSV with COPY; each row remembers its source file."""
    cols = ", ".join(RAW_COLUMNS)
    for csv_path in sorted(RAW.glob("*.csv")):
        start = time.time()
        conn.execute(
            psycopg.sql.SQL("ALTER TABLE staging.sr_raw ALTER COLUMN source_file SET DEFAULT {}").format(
                psycopg.sql.Literal(csv_path.stem)
            )
        )
        with conn.cursor() as cur:
            with cur.copy(f"COPY staging.sr_raw ({cols}) FROM STDIN WITH (FORMAT csv, HEADER true)") as copy:
                with csv_path.open("rb") as fh:
                    while chunk := fh.read(1 << 20):
                        copy.write(chunk)
        n = conn.execute("SELECT count(*) FROM staging.sr_raw WHERE source_file = %s", (csv_path.stem,)).fetchone()[0]
        log(f"loaded {n:,} rows from {csv_path.name} in {time.time() - start:.1f}s")
    conn.execute("ALTER TABLE staging.sr_raw ALTER COLUMN source_file DROP DEFAULT")


def export_query(conn: psycopg.Connection, sql_path: pathlib.Path, out_csv: pathlib.Path) -> None:
    """Run one SELECT and stream its result to CSV with COPY ... TO STDOUT."""
    query = re.sub(r";\s*$", "", sql_path.read_text().strip())
    with conn.cursor() as cur, out_csv.open("wb") as fh:
        with cur.copy(f"COPY ({query}) TO STDOUT WITH (FORMAT csv, HEADER true)") as copy:
            for data in copy:
                fh.write(data)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--fetch", action="store_true", help="download a fresh extract first")
    args = parser.parse_args()

    if args.fetch or not (RAW / "pull_metadata.json").exists():
        log("downloading from the Dallas Open Data portal ...")
        subprocess.run([sys.executable, "-I", str(ROOT / "etl" / "fetch_311.py"), str(RAW)], check=True)

    url = os.environ.get("DATABASE_URL", DEFAULT_URL)
    ensure_database(url)
    RESULTS.mkdir(exist_ok=True)
    with psycopg.connect(url, autocommit=True) as conn:
        run_sql_file(conn, SQL / "01_schema.sql")
        record_extract_info(conn)
        load_staging(conn)
        for step in BUILD_STEPS:
            run_sql_file(conn, SQL / step)

        export_query(conn, SQL / "06_data_quality.sql", RESULTS / "data_quality.csv")
        log("wrote results/data_quality.csv")
        for sql_path in sorted((SQL / "analysis").glob("*.sql")):
            out = RESULTS / f"{sql_path.stem}.csv"
            export_query(conn, sql_path, out)
            log(f"wrote results/{out.name}")

    for script in ("make_charts.py", "build_dashboard.py"):
        subprocess.run([sys.executable, "-I", str(ROOT / "src" / script)], check=True)
        log(f"ran src/{script}")
    log("done")


if __name__ == "__main__":
    main()
