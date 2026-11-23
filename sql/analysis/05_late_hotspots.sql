-- Where late requests come from (FY2026): request types ranked by how
-- many closed after their due date, with each type's share of ALL late closes citywide.
WITH late AS (
    SELECT
        request_type_name,
        department_short,
        mode() WITHIN GROUP (ORDER BY ert_text)                                      AS typical_target,
        count(*) FILTER (WHERE sla_eligible)                                         AS sla_eligible,
        count(*) FILTER (WHERE sla_eligible AND NOT closed_on_time)                  AS closed_late,
        avg(closed_on_time::int) FILTER (WHERE sla_eligible)                         AS on_time_rate,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM (closed_at - due_at)) / 86400.0)
            FILTER (WHERE sla_eligible AND NOT closed_on_time)                       AS median_days_late
    FROM analytics.service_requests
    WHERE fiscal_year = 2026
    GROUP BY request_type_name, department_short
)
SELECT
    request_type_name,
    department_short                                                           AS department,
    typical_target,
    sla_eligible,
    closed_late,
    round(100.0 * on_time_rate, 1)                                             AS pct_on_time,
    round(100.0 * closed_late / sum(closed_late) OVER (), 1)                   AS pct_of_all_late_closes,
    round(median_days_late::numeric, 1)                                        AS median_days_late
FROM late
WHERE sla_eligible > 0
ORDER BY closed_late DESC
LIMIT 15;
