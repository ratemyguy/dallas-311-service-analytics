-- "Fixed, then reported again": for requests resolved in FY2026 at a street address, how often does a new
-- request of the SAME type at the SAME address arrive within 30 days after closure? (LEAD window function)
WITH seq AS (
    SELECT
        request_type_name,
        department_short,
        fiscal_year,
        is_resolved,
        closed_at,
        LEAD(created_at) OVER (PARTITION BY address, request_type_name ORDER BY created_at) AS next_created_at
    FROM analytics.service_requests
    WHERE address ~ '^[0-9]+ ' AND NOT is_duplicate        -- street addresses only (no intersections)
)
SELECT
    request_type_name,
    department_short                                                                   AS department,
    count(*)                                                                           AS resolved_requests,
    count(*) FILTER (WHERE next_created_at > closed_at
                       AND next_created_at <= closed_at + INTERVAL '30 days')          AS reported_again_within_30d,
    round(100.0 * count(*) FILTER (WHERE next_created_at > closed_at
                                     AND next_created_at <= closed_at + INTERVAL '30 days')
          / count(*), 1)                                                               AS pct_reported_again_within_30d
FROM seq
WHERE fiscal_year = 2026 AND is_resolved
GROUP BY request_type_name, department_short
HAVING count(*) >= 2000
ORDER BY pct_reported_again_within_30d DESC
LIMIT 15;
