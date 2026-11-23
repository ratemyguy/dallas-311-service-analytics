-- =============================================================================
-- 06_data_quality.sql — one row per check: what was found, how many rows, what the pipeline did
-- =============================================================================
WITH raw AS (SELECT count(*)::numeric AS n FROM staging.sr_raw),
checks AS (
    SELECT 1 AS ord, 'Rows downloaded (both extracts)' AS check_name,
           (SELECT count(*) FROM staging.sr_raw) AS row_count, 'loaded into staging.sr_raw' AS action
    UNION ALL
    SELECT 2, 'Rejected: ' || reject_reason, count(*), 'kept in staging.sr_rejects, excluded from core'
    FROM staging.sr_rejects GROUP BY reject_reason
    UNION ALL
    SELECT 3, 'Rows in core.service_request', (SELECT count(*) FROM core.service_request), 'analysis base'
    UNION ALL
    SELECT 4, 'Department spelled two ways (rows relabeled to one canonical name)',
           (SELECT count(*) FROM staging.sr_raw r
              JOIN core.department_alias a ON a.raw_name = staging.clean_text(r.department)
              JOIN core.department d ON d.department_id = a.department_id
             WHERE d.department_name <> staging.clean_text(r.department)),
           'mapped through core.department_alias'
    UNION ALL
    SELECT 5, 'Text with non-breaking spaces or extra whitespace (any column)',
           (SELECT count(*) FROM staging.sr_raw
             WHERE concat_ws('|', outcome, service_request_type, department, address) ~ ('(' || chr(160) || '|\s{2,}|^\s|\s$)')),
           'normalized by staging.clean_text()'
    UNION ALL
    SELECT 6, 'Resolved requests with no published due date',
           (SELECT count(*) FROM analytics.service_requests WHERE is_resolved AND due_at IS NULL),
           'kept; excluded from on-time rates, included in days-to-close'
    UNION ALL
    SELECT 7, 'Due date earlier than the request itself',
           (SELECT count(*) FROM core.service_request WHERE due_at < created_at),
           'kept; excluded from on-time rates'
    UNION ALL
    SELECT 8, 'Coordinates missing or outside the Dallas area',
           (SELECT count(*) FROM core.service_request WHERE latitude IS NULL),
           'set to NULL (no map point)'
    UNION ALL
    SELECT 9, 'No council district (blank or outside 1-14)',
           (SELECT count(*) FROM core.service_request WHERE council_district IS NULL),
           'kept; excluded from district comparisons'
    UNION ALL
    SELECT 10, 'No ZIP code in the address',
           (SELECT count(*) FROM core.service_request WHERE zip_code IS NULL),
           'kept'
    UNION ALL
    SELECT 11, 'No intake channel recorded',
           (SELECT count(*) FROM core.service_request WHERE channel_id IS NULL),
           'kept as Unknown'
)
SELECT check_name, row_count, round(100.0 * row_count / raw.n, 2) AS pct_of_downloaded_rows, action
FROM checks CROSS JOIN raw
ORDER BY ord, row_count DESC
