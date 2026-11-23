-- =============================================================================
-- 04_analytics.sql — the layer analysts and the dashboard query
-- =============================================================================

-- One wide, readable row per request with every label joined in and the service-level flags defined once.
CREATE VIEW analytics.service_requests AS
SELECT
    sr.sr_number,
    sr.created_at,
    date_trunc('month', sr.created_at)::date             AS created_month,
    sr.fiscal_year,
    d.department_name,
    d.department_short,
    rt.request_type_name,
    ch.channel_name,
    COALESCE(ch.initiated_by, 'Unknown')                  AS initiated_by,
    sr.status_name,
    st.is_open,
    st.is_duplicate,
    st.is_resolved,
    sr.council_district,
    sr.priority,
    sr.outcome,
    sr.ert_text,
    sr.address,
    sr.zip_code,
    sr.latitude,
    sr.longitude,
    sr.due_at,
    sr.closed_at,
    sr.days_to_close,
    sr.closed_on_time,
    -- A request counts toward on-time performance when the department resolved it (not a duplicate,
    -- transfer or cancel) and the city published a due date that is not before the request itself.
    (st.is_resolved AND sr.due_at IS NOT NULL AND sr.due_at >= sr.created_at) AS sla_eligible
FROM core.service_request sr
JOIN core.request_type rt ON rt.request_type_id = sr.request_type_id
JOIN core.department d    ON d.department_id    = rt.department_id
JOIN core.status st       ON st.status_name     = sr.status_name
LEFT JOIN core.channel ch ON ch.channel_id      = sr.channel_id;

COMMENT ON VIEW analytics.service_requests IS
    'One row per 311 request with labels joined in. sla_eligible marks requests that count toward on-time performance.';

-- The open backlog, aged against the moment the extract was pulled.
CREATE VIEW analytics.open_backlog AS
SELECT
    v.*,
    e.pulled_at_local                                                AS as_of,
    EXTRACT(EPOCH FROM (e.pulled_at_local - v.created_at)) / 86400.0 AS age_days,
    (v.due_at IS NOT NULL AND v.due_at < e.pulled_at_local)          AS past_due
FROM analytics.service_requests v
CROSS JOIN core.extract_info e
WHERE v.is_open AND NOT v.is_duplicate;

-- Pre-aggregated monthly KPIs per department: the dashboard reads this instead of scanning ~1M rows.
CREATE MATERIALIZED VIEW analytics.monthly_department_kpis AS
SELECT
    created_month,
    department_short,
    count(*)                                                  AS requests,
    count(*) FILTER (WHERE initiated_by = 'External')         AS external_requests,
    count(*) FILTER (WHERE sla_eligible)                      AS sla_eligible_closed,
    count(*) FILTER (WHERE sla_eligible AND closed_on_time)   AS closed_on_time,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY days_to_close)
        FILTER (WHERE is_resolved)                            AS median_days_to_close
FROM analytics.service_requests
GROUP BY created_month, department_short
WITH DATA;

CREATE UNIQUE INDEX monthly_department_kpis_pk
    ON analytics.monthly_department_kpis (created_month, department_short);
-- (the unique index also allows REFRESH MATERIALIZED VIEW CONCURRENTLY after each new load)
