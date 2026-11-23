-- FY2026 department scorecard with FY2025 comparison.
-- On-time % covers requests the department resolved AND that carried a published due date.
WITH by_dept AS (
    SELECT
        department_short,
        fiscal_year,
        count(*)                                                           AS requests,
        count(*) FILTER (WHERE is_resolved)                                AS resolved,
        count(*) FILTER (WHERE is_resolved AND due_at IS NULL)             AS resolved_without_due_date,
        count(*) FILTER (WHERE sla_eligible)                               AS sla_eligible,
        avg(closed_on_time::int) FILTER (WHERE sla_eligible)               AS on_time_rate,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_close) FILTER (WHERE is_resolved) AS median_days,
        percentile_cont(0.9) WITHIN GROUP (ORDER BY days_to_close) FILTER (WHERE is_resolved) AS p90_days
    FROM analytics.service_requests
    WHERE fiscal_year IN (2025, 2026)
    GROUP BY department_short, fiscal_year
)
SELECT
    cur.department_short                                                          AS department,
    cur.requests                                                                  AS requests_fy2026,
    round(100.0 * cur.requests / sum(cur.requests) OVER (), 1)                    AS pct_of_fy2026_requests,
    prev.requests                                                                 AS requests_fy2025,
    round(100.0 * (cur.requests - prev.requests) / NULLIF(prev.requests, 0), 1)   AS volume_change_pct,
    round(100.0 * cur.resolved_without_due_date / NULLIF(cur.resolved, 0), 1)     AS pct_resolved_without_due_date,
    cur.sla_eligible                                                              AS sla_eligible_fy2026,
    round(100.0 * cur.on_time_rate, 1)                                            AS pct_on_time_fy2026,
    round(100.0 * prev.on_time_rate, 1)                                           AS pct_on_time_fy2025,
    round(100.0 * (cur.on_time_rate - prev.on_time_rate), 1)                      AS on_time_change_pts,
    round(cur.median_days::numeric, 2)                                            AS median_days_to_close_fy2026,
    round(cur.p90_days::numeric, 1)                                               AS p90_days_to_close_fy2026
FROM by_dept cur
LEFT JOIN by_dept prev
       ON prev.department_short = cur.department_short AND prev.fiscal_year = 2025
WHERE cur.fiscal_year = 2026
ORDER BY cur.requests DESC;
