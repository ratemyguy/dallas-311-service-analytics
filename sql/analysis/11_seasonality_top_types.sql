-- Monthly volume of the six most common request types (FY2025-FY2026): seasonality for planning crews.
WITH top_types AS (
    SELECT request_type_name
    FROM analytics.service_requests
    WHERE fiscal_year IN (2025, 2026)
    GROUP BY request_type_name
    ORDER BY count(*) DESC
    LIMIT 6
)
SELECT created_month, request_type_name, count(*) AS requests
FROM analytics.service_requests
WHERE fiscal_year IN (2025, 2026)
  AND request_type_name IN (SELECT request_type_name FROM top_types)
GROUP BY created_month, request_type_name
ORDER BY created_month, request_type_name;
