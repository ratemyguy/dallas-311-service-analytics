-- Did service get better, or did the city just receive easier requests? (FY2025 -> FY2026)
-- Splits the change in the citywide on-time rate into:
--   mix effect          = FY2026 request mix at FY2025 per-type rates  - FY2025 actual rate
--   performance effect  = FY2026 actual rate - FY2026 mix at FY2025 per-type rates
-- Restricted to request types measured in both years (coverage reported).
WITH by_type AS (
    SELECT fiscal_year, request_type_name, department_short,
           count(*)                   AS n,
           avg(closed_on_time::int)   AS rate
    FROM analytics.service_requests
    WHERE sla_eligible AND fiscal_year IN (2025, 2026)
    GROUP BY fiscal_year, request_type_name, department_short
),
paired AS (
    SELECT t25.request_type_name, t25.n AS n25, t25.rate AS rate25, t26.n AS n26, t26.rate AS rate26
    FROM by_type t25
    JOIN by_type t26
      ON t26.request_type_name = t25.request_type_name
     AND t26.department_short  = t25.department_short
     AND t26.fiscal_year = 2026
    WHERE t25.fiscal_year = 2025
),
totals AS (
    SELECT
        sum(n25 * rate25) / sum(n25)  AS actual_2025,
        sum(n26 * rate26) / sum(n26)  AS actual_2026,
        sum(n26 * rate25) / sum(n26)  AS fy2026_mix_at_2025_rates,
        sum(n25) AS n25_paired, sum(n26) AS n26_paired, count(*) AS request_types_in_both
    FROM paired
),
all_eligible AS (
    SELECT count(*) FILTER (WHERE fiscal_year = 2025) AS n25_all,
           count(*) FILTER (WHERE fiscal_year = 2026) AS n26_all
    FROM analytics.service_requests
    WHERE sla_eligible AND fiscal_year IN (2025, 2026)
)
SELECT
    request_types_in_both,
    round(100.0 * n25_paired / n25_all, 1)                                  AS pct_fy2025_closes_covered,
    round(100.0 * n26_paired / n26_all, 1)                                  AS pct_fy2026_closes_covered,
    round(100 * actual_2025, 2)                                             AS pct_on_time_fy2025,
    round(100 * actual_2026, 2)                                             AS pct_on_time_fy2026,
    round(100 * (actual_2026 - actual_2025), 2)                             AS total_change_pts,
    round(100 * (fy2026_mix_at_2025_rates - actual_2025), 2)                AS mix_effect_pts,
    round(100 * (actual_2026 - fy2026_mix_at_2025_rates), 2)                AS performance_effect_pts
FROM totals CROSS JOIN all_eligible;
