"""Draw the README charts from the CSVs in results/ (run after the SQL step).

Usage: python -I src/make_charts.py
"""
from __future__ import annotations

import pathlib

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import numpy as np  # noqa: E402
import pandas as pd  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
IMAGES = ROOT / "images"
NAVY, TEAL, YELLOW, ORANGE, GRAY = "#1F3A5F", "#2A9D8F", "#E9C46A", "#E76F51", "#8D99AE"
SOURCE = "Source: City of Dallas Open Data, 311 Service Requests (d7e7-envw). Analysis: Jude (Joochan) Lee."

plt.rcParams.update({
    "figure.dpi": 150, "savefig.dpi": 150, "font.size": 10, "axes.titlesize": 13,
    "axes.titleweight": "bold", "axes.titlelocation": "left", "axes.spines.top": False,
    "axes.spines.right": False, "axes.grid": True, "grid.color": "#E5E7EB", "grid.linewidth": 0.8,
    "axes.axisbelow": True, "font.family": "DejaVu Sans",
})


def read(name: str) -> pd.DataFrame:
    return pd.read_csv(RESULTS / name)


def finish(fig: plt.Figure, filename: str, note: str = SOURCE) -> None:
    fig.text(0.01, 0.01, note, fontsize=7.5, color=GRAY, ha="left", va="bottom")
    fig.savefig(IMAGES / filename, bbox_inches="tight", facecolor="white")
    plt.close(fig)
    print(f"  images/{filename}")


def monthly_volume() -> None:
    m = read("02_monthly_volume.csv")
    m["created_month"] = pd.to_datetime(m["created_month"])
    m = m[~m["is_partial_month"].astype(str).str.lower().isin(["t", "true"])]
    k = read("01_kpis_by_fiscal_year.csv").set_index("fiscal_year")
    change = 100 * (k.loc[2026, "requests"] / k.loc[2025, "requests"] - 1)

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(8, 6.4), sharex=True, gridspec_kw={"height_ratios": [2, 1.2]})
    width = 20
    ax1.bar(m["created_month"], m["external_requests"], width=width, color=NAVY, label="Reported from outside the city")
    ax1.bar(m["created_month"], m["city_initiated"], width=width, bottom=m["external_requests"], color=TEAL,
            label="Started by city staff (proactive / internal)")
    ax1.set_ylabel("Requests per month")
    ax1.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v / 1000:.0f}k"))
    ax1.legend(frameon=False, loc="upper right", fontsize=8.5)
    ax1.set_title(f"Requests fell {abs(change):.0f}% in FY2026 while on-time closures rose "
                  f"from {k.loc[2025, 'pct_on_time']:.1f}% to {k.loc[2026, 'pct_on_time']:.1f}%")
    ax2.plot(m["created_month"], m["pct_on_time"], color=ORANGE, marker="o", markersize=3.5, linewidth=2)
    ax2.set_ylabel("Closed on time (%)")
    ax2.set_ylim(84, 97)
    for ax in (ax1, ax2):
        for boundary in ("2025-10-01", "2026-10-01"):
            if m["created_month"].max() >= pd.Timestamp(boundary):
                ax.axvline(pd.Timestamp(boundary) - pd.Timedelta(days=15), color=GRAY, linestyle="--", linewidth=1)
    ax1.text(pd.Timestamp("2025-01-15"), ax1.get_ylim()[1] * 0.97, "FY2025", color=GRAY, fontsize=9)
    ax1.text(pd.Timestamp("2026-01-15"), ax1.get_ylim()[1] * 0.97, "FY2026", color=GRAY, fontsize=9)
    if m["created_month"].max() >= pd.Timestamp("2026-10-01"):
        ax1.text(pd.Timestamp("2026-09-20"), ax1.get_ylim()[1] * 0.90, "FY2027 →", color=GRAY, fontsize=8)
    ax2.xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%b\n%Y"))
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    finish(fig, "01_monthly_volume_and_on_time.png")


def due_date_coverage() -> None:
    d = read("03_department_scorecard.csv")
    d = d[d["requests_fy2026"] >= 3000].copy()
    d["pct_with_due_date"] = 100 - d["pct_resolved_without_due_date"]
    d = d.sort_values("requests_fy2026")
    fig, ax = plt.subplots(figsize=(8, 4.6))
    colors = [ORANGE if v < 50 else NAVY for v in d["pct_with_due_date"]]
    ax.barh(d["department"], d["pct_with_due_date"], color=colors)
    for y, (pct, share) in enumerate(zip(d["pct_with_due_date"], d["pct_of_fy2026_requests"])):
        ax.text(pct + 1, y, f"{pct:.0f}%  (dept = {share:.0f}% of all requests)", va="center", fontsize=8.5)
    cc = d.loc[d["department"] == "Code Compliance"].iloc[0]
    ax.set_xlim(0, 135)
    ax.set_xticks(range(0, 101, 20))
    ax.set_xlabel("Resolved FY2026 requests that carried a published due date (%)")
    ax.set_title(f"Code Compliance handles {cc['pct_of_fy2026_requests']:.0f}% of requests but publishes a due date "
                 f"on only {100 - cc['pct_resolved_without_due_date']:.0f}% of them")
    ax.grid(axis="y", visible=False)
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    finish(fig, "02_due_date_coverage.png")


def department_on_time() -> None:
    d = read("03_department_scorecard.csv")
    d = d[d["sla_eligible_fy2026"] >= 1000].sort_values("pct_on_time_fy2026")
    fig, ax = plt.subplots(figsize=(8, 4.8))
    y = np.arange(len(d))
    ax.hlines(y, d["pct_on_time_fy2025"], d["pct_on_time_fy2026"], color=GRAY, linewidth=2)
    ax.scatter(d["pct_on_time_fy2025"], y, color=GRAY, s=36, label="FY2025", zorder=3)
    ax.scatter(d["pct_on_time_fy2026"], y, color=TEAL, s=48, label="FY2026", zorder=3)
    labels = [f"{dep}*" if dep == "Code Compliance" else dep for dep in d["department"]]
    ax.set_yticks(y, labels)
    for yi, (v, ch) in enumerate(zip(d["pct_on_time_fy2026"], d["on_time_change_pts"])):
        ax.text(max(v, d["pct_on_time_fy2025"].iloc[yi]) + 0.6, yi, f"{v:.1f}% ({ch:+.1f})", va="center", fontsize=8.5)
    ax.set_xlim(min(65, d[["pct_on_time_fy2025", "pct_on_time_fy2026"]].min().min() - 3), 102)
    ax.set_xlabel("Requests closed by their due date (%)")
    best = d.sort_values("on_time_change_pts").iloc[-1]
    low = d.iloc[0]
    ax.set_title(f"{best['department']} improved most ({best['on_time_change_pts']:+.1f} pts); "
                 f"{low['department']} is lowest at {low['pct_on_time_fy2026']:.1f}%")
    ax.legend(frameon=False, loc="lower right")
    ax.grid(axis="y", visible=False)
    fig.tight_layout(rect=(0, 0.06, 1, 1))
    finish(fig, "03_department_on_time.png",
           SOURCE + "\n*Code Compliance: measured on the ~6% of its resolved requests that have a due date. "
                    "Departments with 1,000+ measurable closes.")


def late_hotspots() -> None:
    h = read("05_late_hotspots.csv").head(10).iloc[::-1]
    top2 = read("05_late_hotspots.csv").head(2)["pct_of_all_late_closes"].sum()
    fig, ax = plt.subplots(figsize=(8, 4.8))
    colors = [ORANGE if dep == "Animal Services" else NAVY for dep in h["department"]]
    ax.barh(h["request_type_name"], h["closed_late"], color=colors)
    for yi, (n, pct, tgt) in enumerate(zip(h["closed_late"], h["pct_on_time"], h["typical_target"])):
        ax.text(n + 30, yi, f"{n:,} late · {pct:.0f}% on time · target {tgt}", va="center", fontsize=8)
    ax.set_xlim(0, h["closed_late"].max() * 1.75)
    ax.set_xlabel("FY2026 requests closed after their due date")
    ax.set_title(f"Two Animal Services request types produce {top2:.0f}% of all late closes")
    ax.grid(axis="y", visible=False)
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    finish(fig, "04_late_hotspots.png")


def district_equity() -> None:
    d = read("06_district_equity.csv").sort_values("gap_pts")
    fig, ax = plt.subplots(figsize=(8, 4.6))
    colors = [ORANGE if g <= -1 else (TEAL if g >= 1 else GRAY) for g in d["gap_pts"]]
    ylabels = [f"District {int(x)}" for x in d["council_district"]]
    ax.barh(ylabels, d["gap_pts"], xerr=d["moe_95_pts"], color=colors, capsize=3, ecolor="#555")
    ax.axvline(0, color="#333", linewidth=1)
    for yi, (g, obs, exp) in enumerate(zip(d["gap_pts"], d["pct_on_time_observed"], d["pct_on_time_expected_for_mix"])):
        ax.text(2.35, yi, f"{obs:.1f}% vs {exp:.1f}% expected", va="center", fontsize=8)
    ax.set_xlim(-2.6, 4.6)
    ax.set_xlabel("On-time rate minus the rate expected for the district's mix of request types (percentage points)")
    worst = d.iloc[0]["gap_pts"]
    trailing = ", ".join(str(int(x)) for x in sorted(d.loc[d["gap_pts"] <= -1, "council_district"]))
    ax.set_title(f"Adjusted for request mix, every district is within {abs(worst):.1f} points of its expected\n"
                 f"on-time rate; districts {trailing} trail")
    ax.grid(axis="y", visible=False)
    fig.tight_layout(rect=(0, 0.05, 1, 1))
    finish(fig, "05_district_mix_adjusted.png",
           SOURCE + "\nFY2026 resolved requests with a due date. Error bars: 95% margin of error of the observed rate.")


def backlog() -> None:
    b = read("09_backlog_aging.csv")
    total, past_due = b["open_requests"].sum(), b["past_due"].sum()
    top = b.head(8).iloc[::-1]
    buckets = [("age_0_7_days", "0–7 days", "#A8DADC"), ("age_8_30_days", "8–30", TEAL),
               ("age_31_90_days", "31–90", YELLOW), ("age_91_365_days", "91–365", ORANGE),
               ("age_over_365_days", "Over a year", "#9B2226")]
    fig, ax = plt.subplots(figsize=(8, 4.6))
    left = np.zeros(len(top))
    for col, label, color in buckets:
        ax.barh(top["department"], top[col], left=left, color=color, label=label)
        left += top[col].to_numpy()
    for yi, (n, pd_pct) in enumerate(zip(top["open_requests"], top["pct_past_due"])):
        ax.text(n + 60, yi, f"{n:,} open · {pd_pct:.0f}% past due", va="center", fontsize=8)
    ax.set_xlim(0, top["open_requests"].max() * 1.45)
    ax.set_xlabel("Open requests by age")
    cc_share = 100 * b.loc[b["department"] == "Code Compliance", "open_requests"].iloc[0] / total
    pdd = b.loc[b["department"] == "Planning & Development"].iloc[0]
    ax.set_title(f"{total:,} requests were open; Code Compliance holds {cc_share:.0f}%, and Planning & Development's\n"
                 f"median open request is {pdd['median_age_days']:.0f} days old")
    ax.legend(frameon=False, ncol=1, loc="center right", fontsize=8, title="Age of open request", title_fontsize=8)
    ax.grid(axis="y", visible=False)
    as_of = str(b["as_of"].iloc[0])[:10]
    fig.tight_layout(rect=(0, 0.04, 1, 1))
    finish(fig, "06_backlog_aging.png", SOURCE + f" Open, non-duplicate requests as of {as_of}. "
                                                f"{past_due:,} ({100 * past_due / total:.0f}%) were past due.")


def phone_heatmap() -> None:
    p = read("08_phone_demand_by_hour.csv")
    grid = p.pivot_table(index="weekday", columns="hour", values="phone_requests", aggfunc="sum").fillna(0)
    order = p.drop_duplicates("weekday").sort_values("iso_weekday")["weekday"].tolist()
    grid = grid.loc[order]
    weekday_core = p[(p["iso_weekday"] <= 5) & (p["hour"].between(8, 16))]["phone_requests"].sum()
    share = 100 * weekday_core / p["phone_requests"].sum()
    peak = p.sort_values("phone_requests").iloc[-1]
    fig, ax = plt.subplots(figsize=(9, 3.6))
    im = ax.imshow(grid.to_numpy(), aspect="auto", cmap="Blues")
    ax.set_yticks(range(len(order)), order)
    ax.set_xticks(range(0, 24, 2), [f"{h:02d}:00" for h in range(0, 24, 2)], fontsize=8)
    ax.grid(False)
    cbar = fig.colorbar(im, ax=ax, pad=0.01)
    cbar.set_label("Phone requests (FY2026)")
    ax.set_title(f"{share:.0f}% of 311 phone requests arrive on weekdays 8 AM–5 PM; "
                 f"the busiest hour is {peak['weekday']} {int(peak['hour'])}:00")
    fig.tight_layout(rect=(0, 0.05, 1, 1))
    finish(fig, "07_phone_demand_heatmap.png")


def seasonality() -> None:
    s = read("11_seasonality_top_types.csv")
    s["created_month"] = pd.to_datetime(s["created_month"])
    cc = s[s["request_type_name"] == "Code Concern - CCS"].set_index("created_month")["requests"]
    fy26 = cc[(cc.index >= "2025-10-01") & (cc.index < "2026-10-01")]
    peak, trough = fy26.idxmax(), fy26.idxmin()
    fig, ax = plt.subplots(figsize=(8, 3.8))
    ax.plot(cc.index, cc.values, color=NAVY, marker="o", markersize=3.5, linewidth=2)
    ax.annotate(f"{peak:%b %Y}: {fy26.max():,}", (peak, fy26.max()), textcoords="offset points", xytext=(6, 6), fontsize=8.5)
    ax.annotate(f"{trough:%b %Y}: {fy26.min():,}", (trough, fy26.min()), textcoords="offset points", xytext=(10, -3), fontsize=8.5)
    ax.set_ylabel("Requests per month")
    ax.yaxis.set_major_formatter(matplotlib.ticker.FuncFormatter(lambda v, _: f"{v:,.0f}"))
    ax.set_title(f"Code Concern requests are seasonal: in FY2026, {peak:%B} brought {fy26.max() / fy26.min():.1f}× "
                 f"as many as {trough:%B}")
    ax.xaxis.set_major_formatter(matplotlib.dates.DateFormatter("%b\n%Y"))
    fig.tight_layout(rect=(0, 0.05, 1, 1))
    finish(fig, "08_code_concern_seasonality.png")


def main() -> None:
    IMAGES.mkdir(exist_ok=True)
    for chart in (monthly_volume, due_date_coverage, department_on_time, late_hotspots, district_equity,
                  backlog, phone_heatmap, seasonality):
        chart()


if __name__ == "__main__":
    main()
