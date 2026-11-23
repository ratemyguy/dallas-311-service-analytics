"""Download Dallas 311 service requests from the City of Dallas Open Data portal (Socrata).

Dataset: "311 Service Requests October 1, 2020 to Present" (id d7e7-envw)
https://www.dallasopendata.com/Services/311-Service-Requests-October-1-2020-to-Present/d7e7-envw

Pulls two extracts as CSV (no API key needed; the portal throttles anonymous use, so pages are modest):
  1. every request created on or after 2024-10-01 (fiscal years 2025, 2026 and 2027 to date)
  2. requests created earlier that are still open today (so the backlog analysis is complete)

Usage:  python -I etl/fetch_311.py data/raw/dallas_311
"""
from __future__ import annotations

import csv
import datetime as dt
import json
import pathlib
import sys
import time

import requests

ENDPOINT = "https://www.dallasopendata.com/resource/d7e7-envw.csv"
COLUMNS = [
    "service_request_number", "address", "city_council_district", "department",
    "service_request_type", "ert_estimated_response_time", "overall_service_request_due_date",
    "status", "created_date", "update_date", "closed_date", "outcome", "priority",
    "method_received_description", "lat_location",
]
OPEN_STATUSES = [
    "New", "In Progress", "Escalated", "On Hold",
    "New (Duplicate)", "In Progress (Duplicate)", "Escalated (Duplicate)", "On Hold (Duplicate)",
]
EXTRACTS = {
    "requests_since_2024_10_01": "created_date >= '2024-10-01T00:00:00'",
    "open_requests_before_2024_10_01": (
        "created_date < '2024-10-01T00:00:00' AND status in ("
        + ",".join(f"'{s}'" for s in OPEN_STATUSES) + ")"
    ),
}
PAGE_SIZE = 100_000


def fetch_extract(name: str, where: str, out_dir: pathlib.Path) -> int:
    """Page through one filtered extract and write a single CSV. Returns the row count."""
    out_path = out_dir / f"{name}.csv"
    rows_written, offset, header_done = 0, 0, False
    with out_path.open("w", newline="", encoding="utf-8") as out:
        writer = csv.writer(out)
        while True:
            params = {
                "$select": ",".join(COLUMNS),
                "$where": where,
                "$order": ":id",
                "$limit": PAGE_SIZE,
                "$offset": offset,
            }
            for attempt in range(5):
                try:
                    resp = requests.get(ENDPOINT, params=params, timeout=300)
                    resp.raise_for_status()
                    break
                except requests.RequestException as exc:  # throttling or a dropped connection
                    wait = 10 * (attempt + 1)
                    print(f"  retry {attempt + 1} after error: {exc} (waiting {wait}s)", flush=True)
                    time.sleep(wait)
            else:
                raise SystemExit(f"giving up on {name} at offset {offset}")
            reader = csv.reader(resp.text.splitlines())
            header = next(reader)
            page = list(reader)
            if not header_done:
                writer.writerow(header)
                header_done = True
            writer.writerows(page)
            rows_written += len(page)
            print(f"  {name}: offset {offset:>9,} -> {len(page):>7,} rows (total {rows_written:,})", flush=True)
            if len(page) < PAGE_SIZE:
                return rows_written
            offset += PAGE_SIZE


def main() -> None:
    out_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "data/raw/dallas_311")
    out_dir.mkdir(parents=True, exist_ok=True)
    pulled_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0)
    counts = {name: fetch_extract(name, where, out_dir) for name, where in EXTRACTS.items()}
    meta = {
        "dataset": "d7e7-envw",
        "source": "https://www.dallasopendata.com/Services/311-Service-Requests-October-1-2020-to-Present/d7e7-envw",
        "pulled_at_utc": pulled_at.isoformat(),
        "row_counts": counts,
        "filters": EXTRACTS,
    }
    (out_dir / "pull_metadata.json").write_text(json.dumps(meta, indent=2))
    print(json.dumps(meta, indent=2))


if __name__ == "__main__":
    main()
