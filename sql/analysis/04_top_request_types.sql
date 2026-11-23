-- The 25 most common request types in FY2026, their published target and how often it was met.
WITH by_type AS (
    SELECT
        request_type_name,
        department_short,
        count(*)                                                   AS requests,
        count(*) FILTER (WHERE sla_eligible)                       AS sla_eligible,
        avg(closed_on_time::int) FILTER (WHERE sla_eligible)       AS on_time_rate,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_close) FILTER (WHERE is_resolved) AS median_days,
        mode() WITHIN GROUP (ORDER BY ert_text)                    AS typical_target
    FROM analytics.service_requests
    WHERE fiscal_year = 2026
    GROUP BY request_type_name, department_short
)
SELECT
    request_type_name,
    department_short                                                              AS department,
    requests,
    round(100.0 * requests / sum(requests) OVER (), 1)                            AS pct_of_fy2026_requests,
    DENSE_RANK() OVER (PARTITION BY department_short ORDER BY requests DESC)      AS rank_in_department,
    typical_target,
    sla_eligible,
    round(100.0 * on_time_rate, 1)                                                AS pct_on_time,
    round(median_days::numeric, 2)                                                AS median_days_to_close
FROM by_type
ORDER BY requests DESC
LIMIT 25;
