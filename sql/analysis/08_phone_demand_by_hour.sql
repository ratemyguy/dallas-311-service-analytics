-- When residents call 311 (FY2026 phone requests by weekday and hour): a call-center staffing view.
SELECT
    EXTRACT(ISODOW FROM created_at)::int    AS iso_weekday,   -- 1 = Monday
    to_char(created_at, 'Dy')               AS weekday,
    EXTRACT(HOUR FROM created_at)::int      AS hour,
    count(*)                                AS phone_requests
FROM analytics.service_requests
WHERE fiscal_year = 2026 AND channel_name = 'Phone'
GROUP BY 1, 2, 3
ORDER BY 1, 3;
