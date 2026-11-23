-- Headline KPIs by City of Dallas fiscal year (Oct 1 - Sep 30). FY2027 is partial: Oct 1 to the extract date.
SELECT
    fiscal_year,
    min(created_at)::date                                                         AS first_day,
    max(created_at)::date                                                         AS last_day,
    count(*)                                                                      AS requests,
    count(*) FILTER (WHERE initiated_by = 'External')                             AS external_requests,
    round(100.0 * count(*) FILTER (WHERE initiated_by = 'City') / count(*), 1)    AS pct_city_initiated,
    round(100.0 * count(*) FILTER (WHERE is_duplicate) / count(*), 1)             AS pct_duplicates,
    count(*) FILTER (WHERE is_resolved)                                           AS resolved,
    count(*) FILTER (WHERE sla_eligible)                                          AS sla_eligible,
    round(100.0 * count(*) FILTER (WHERE sla_eligible)
          / NULLIF(count(*) FILTER (WHERE is_resolved), 0), 1)                    AS pct_resolved_with_due_date,
    round(100.0 * avg(closed_on_time::int) FILTER (WHERE sla_eligible), 1)        AS pct_on_time,
    round((percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_close)
           FILTER (WHERE is_resolved))::numeric, 2)                               AS median_days_to_close,
    round((percentile_cont(0.9) WITHIN GROUP (ORDER BY days_to_close)
           FILTER (WHERE is_resolved))::numeric, 1)                               AS p90_days_to_close
FROM analytics.service_requests
WHERE fiscal_year BETWEEN 2025 AND 2027
GROUP BY fiscal_year
ORDER BY fiscal_year;
