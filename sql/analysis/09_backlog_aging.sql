-- Open backlog by department and age, measured at the moment the extract was pulled.
SELECT
    department_short                                                       AS department,
    count(*)                                                               AS open_requests,
    count(*) FILTER (WHERE age_days <= 7)                                  AS age_0_7_days,
    count(*) FILTER (WHERE age_days > 7   AND age_days <= 30)              AS age_8_30_days,
    count(*) FILTER (WHERE age_days > 30  AND age_days <= 90)              AS age_31_90_days,
    count(*) FILTER (WHERE age_days > 90  AND age_days <= 365)             AS age_91_365_days,
    count(*) FILTER (WHERE age_days > 365)                                 AS age_over_365_days,
    count(*) FILTER (WHERE past_due)                                       AS past_due,
    round(100.0 * count(*) FILTER (WHERE past_due) / count(*), 1)          AS pct_past_due,
    round((percentile_cont(0.5) WITHIN GROUP (ORDER BY age_days))::numeric, 1) AS median_age_days,
    max(as_of)                                                             AS as_of
FROM analytics.open_backlog
GROUP BY department_short
ORDER BY open_requests DESC;
