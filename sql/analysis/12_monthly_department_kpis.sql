-- Feed for the dashboard's department filter (reads the materialized view, not the 1M-row table).
SELECT
    created_month,
    department_short AS department,
    requests,
    external_requests,
    sla_eligible_closed,
    closed_on_time,
    round(median_days_to_close::numeric, 2) AS median_days_to_close
FROM analytics.monthly_department_kpis
WHERE created_month >= DATE '2024-10-01'
ORDER BY created_month, department_short;
