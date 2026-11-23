"""Turn the CSVs in results/ into the JSON the GitHub Pages dashboard (docs/index.html) reads.

Usage: python -I src/build_dashboard.py
"""
from __future__ import annotations

import datetime as dt
import json
import pathlib

import pandas as pd

ROOT = pathlib.Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
OUT = ROOT / "docs" / "data" / "dashboard.json"
META = ROOT / "data" / "raw" / "dallas_311" / "pull_metadata.json"


def read(name: str) -> pd.DataFrame:
    return pd.read_csv(RESULTS / name)


def records(df: pd.DataFrame) -> list[dict]:
    """JSON-safe records (NaN -> None)."""
    return json.loads(df.to_json(orient="records", date_format="iso"))


def main() -> None:
    meta = json.loads(META.read_text())
    kpis = read("01_kpis_by_fiscal_year.csv")
    backlog = read("09_backlog_aging.csv")
    quality = read("data_quality.csv")

    monthly = read("12_monthly_department_kpis.csv")
    monthly["created_month"] = pd.to_datetime(monthly["created_month"]).dt.strftime("%Y-%m")
    as_of = str(backlog["as_of"].iloc[0])[:10]
    current_month = as_of[:7]
    monthly = monthly[monthly["created_month"] < current_month]          # drop the partial month
    all_depts = (monthly.groupby("created_month", as_index=False)
                 [["requests", "external_requests", "sla_eligible_closed", "closed_on_time"]].sum())
    all_depts["department"] = "All departments"
    monthly = pd.concat([all_depts, monthly.drop(columns="median_days_to_close")], ignore_index=True)
    monthly["pct_on_time"] = (100 * monthly["closed_on_time"] / monthly["sla_eligible_closed"]).round(1)
    dept_order = (read("03_department_scorecard.csv").sort_values("requests_fy2026", ascending=False)
                  ["department"].tolist())

    core_rows = int(quality.loc[quality["check_name"] == "Rows in core.service_request", "row_count"].iloc[0])
    payload = {
        "meta": {
            "title": "Dallas 311 Service Performance",
            "as_of": as_of,
            "pulled_at_utc": meta["pulled_at_utc"],
            "built_at_utc": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
            "requests_in_database": core_rows,
            "source_url": meta["source"],
            "repo_url": "https://github.com/ratemyguy/dallas-311-service-analytics",
        },
        "kpis": records(kpis),
        "backlog_total": {
            "open_requests": int(backlog["open_requests"].sum()),
            "past_due": int(backlog["past_due"].sum()),
        },
        "departments": ["All departments"] + dept_order,
        "monthly": records(monthly.sort_values(["department", "created_month"])),
        "scorecard": records(read("03_department_scorecard.csv")),
        "late_hotspots": records(read("05_late_hotspots.csv").head(10)),
        "districts": records(read("06_district_equity.csv")),
        "backlog": records(backlog.drop(columns="as_of")),
        "phone_by_hour": records(read("08_phone_demand_by_hour.csv")),
        "channels": records(read("07_channel_mix.csv")),
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(payload, separators=(",", ":")))
    print(f"  wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size / 1024:.0f} KB)")


if __name__ == "__main__":
    main()
