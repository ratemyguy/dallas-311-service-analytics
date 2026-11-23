-- Monthly request volume with a 3-month moving average and year-over-year change (window functions).
WITH monthly AS (
    SELECT
        created_month,
        count(*)                                                AS requests,
        count(*) FILTER (WHERE initiated_by = 'External')       AS external_requests,
        count(*) FILTER (WHERE initiated_by = 'City')           AS city_initiated,
        count(*) FILTER (WHERE sla_eligible)                    AS sla_eligible,
        avg(closed_on_time::int) FILTER (WHERE sla_eligible)    AS on_time_rate
    FROM analytics.service_requests
    WHERE created_at >= DATE '2024-10-01'
    GROUP BY created_month
)
SELECT
    created_month,
    requests,
    external_requests,
    city_initiated,
    round(avg(requests) OVER (ORDER BY created_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) AS requests_3mo_avg,
    LAG(requests, 12) OVER (ORDER BY created_month)                                             AS requests_12mo_earlier,
    round(100.0 * (requests - LAG(requests, 12) OVER (ORDER BY created_month))
          / NULLIF(LAG(requests, 12) OVER (ORDER BY created_month), 0), 1)                     AS yoy_change_pct,
    round(100.0 * on_time_rate, 1)                                                              AS pct_on_time,
    created_month = date_trunc('month', (SELECT pulled_at_local FROM core.extract_info))::date  AS is_partial_month
FROM monthly
ORDER BY created_month;
