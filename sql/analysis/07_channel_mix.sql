-- How requests arrive, FY2025 vs FY2026.
SELECT
    fiscal_year,
    COALESCE(channel_name, 'Unknown')                                              AS channel,
    initiated_by,
    count(*)                                                                       AS requests,
    round(100.0 * count(*) / sum(count(*)) OVER (PARTITION BY fiscal_year), 1)     AS pct_of_year
FROM analytics.service_requests
WHERE fiscal_year IN (2025, 2026)
GROUP BY fiscal_year, COALESCE(channel_name, 'Unknown'), initiated_by
ORDER BY fiscal_year, requests DESC;
