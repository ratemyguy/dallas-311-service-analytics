-- =============================================================================
-- 02_transform.sql — staging.sr_raw  ->  core.*
--
--   1. Clean text (trim, collapse whitespace incl. non-breaking spaces, blank -> NULL)
--   2. Parse types (timestamps, district, coordinates, ZIP) with regex guards, never casts that can fail
--   3. Reject rows that break a rule (kept in staging.sr_rejects with the reason)
--   4. De-duplicate on the service request number (keep the most recently updated version)
--   5. Build dimensions (department with alias mapping, request type, channel, status), then the fact table
-- =============================================================================

-- 1. helper functions ---------------------------------------------------------
CREATE OR REPLACE FUNCTION staging.clean_text(t text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT NULLIF(btrim(regexp_replace(replace(t, chr(160), ' '), '\s+', ' ', 'g')), '')
$$;

-- Socrata timestamps look like 2024-03-14T15:49:21.000; anything else becomes NULL.
CREATE OR REPLACE FUNCTION staging.parse_ts(t text) RETURNS timestamp
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
    SELECT CASE WHEN t ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$' THEN t::timestamp END
$$;

-- 2. typed, cleaned copy of staging -------------------------------------------
DROP TABLE IF EXISTS staging.sr_typed;
CREATE TABLE staging.sr_typed AS
SELECT
    r.*,
    staging.clean_text(r.service_request_number)            AS c_sr_number,
    staging.clean_text(r.department)                        AS c_department,
    staging.clean_text(r.service_request_type)              AS c_request_type,
    staging.clean_text(r.method_received_description)       AS c_channel,
    staging.clean_text(r.status)                            AS c_status,
    staging.clean_text(r.priority)                          AS c_priority,
    staging.clean_text(r.outcome)                           AS c_outcome,
    staging.clean_text(r.ert_estimated_response_time)       AS c_ert,
    staging.clean_text(r.address)                           AS c_address,
    staging.parse_ts(r.created_date)                        AS c_created_at,
    staging.parse_ts(r.overall_service_request_due_date)    AS c_due_at,
    staging.parse_ts(r.closed_date)                         AS c_closed_at,
    staging.parse_ts(r.update_date)                         AS c_updated_at,
    CASE WHEN btrim(r.city_council_district) ~ '^\d{1,2}$'
          AND btrim(r.city_council_district)::int BETWEEN 1 AND 14
         THEN btrim(r.city_council_district)::smallint END  AS c_district,
    (regexp_match(r.address, '(\d{5})(-\d{4})?\s*$'))[1]    AS c_zip,
    (regexp_match(r.lat_location, '^\(\s*(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)\s*\)$'))[1]::numeric AS c_lat_raw,
    (regexp_match(r.lat_location, '^\(\s*(-?\d+(\.\d+)?)\s*,\s*(-?\d+(\.\d+)?)\s*\)$'))[3]::numeric AS c_lon_raw
FROM staging.sr_raw r;

-- 3. rejects: one reason per row, checked in order ------------------------------
INSERT INTO staging.sr_rejects
SELECT service_request_number, address, city_council_district, department, service_request_type,
       ert_estimated_response_time, overall_service_request_due_date, status, created_date, update_date,
       closed_date, outcome, priority, method_received_description, lat_location, source_file,
       CASE
           WHEN c_sr_number IS NULL                        THEN 'missing service request number'
           WHEN c_created_at IS NULL                       THEN 'missing or invalid created date'
           WHEN c_department IS NULL OR c_request_type IS NULL THEN 'missing department or request type'
           WHEN c_status IS NULL                           THEN 'missing status'
           WHEN c_closed_at < c_created_at                 THEN 'closed before it was created'
       END
FROM staging.sr_typed
WHERE c_sr_number IS NULL OR c_created_at IS NULL OR c_department IS NULL OR c_request_type IS NULL
   OR c_status IS NULL OR c_closed_at < c_created_at;

DELETE FROM staging.sr_typed
WHERE c_sr_number IS NULL OR c_created_at IS NULL OR c_department IS NULL OR c_request_type IS NULL
   OR c_status IS NULL OR c_closed_at < c_created_at;

-- 4. de-duplicate: keep the latest version of each request number ---------------
WITH ranked AS (
    SELECT ctid AS row_ctid,
           ROW_NUMBER() OVER (PARTITION BY c_sr_number
                              ORDER BY c_updated_at DESC NULLS LAST, source_file) AS version_rank
    FROM staging.sr_typed
), older AS (
    DELETE FROM staging.sr_typed t
    USING ranked
    WHERE t.ctid = ranked.row_ctid AND ranked.version_rank > 1
    RETURNING t.*
)
INSERT INTO staging.sr_rejects
SELECT service_request_number, address, city_council_district, department, service_request_type,
       ert_estimated_response_time, overall_service_request_due_date, status, created_date, update_date,
       closed_date, outcome, priority, method_received_description, lat_location, source_file,
       'duplicate request number (older version)'
FROM older;

-- 5a. departments: canonical names + aliases for the raw spellings --------------
CREATE TEMP TABLE department_map (raw_name text PRIMARY KEY, canonical text NOT NULL, short_name text NOT NULL);
INSERT INTO department_map VALUES
    ('Code Compliance',                                    'Code Compliance',                                    'Code Compliance'),
    ('Transportation and Public Works Department',         'Transportation and Public Works Department',         'Transportation & Public Works'),
    ('Sanitation',                                         'Sanitation Services',                                'Sanitation'),
    ('Sanitation Services',                                'Sanitation Services',                                'Sanitation'),
    ('Dallas Animal Services',                             'Dallas Animal Services',                             'Animal Services'),
    ('311 Customer Service Center',                        '311 Customer Service Center',                        '311 Customer Service'),
    ('Police Department',                                  'Dallas Police Department',                           'Police'),
    ('Dallas Police',                                      'Dallas Police Department',                           'Police'),
    ('Office of Emergency Management and Crisis Response', 'Office of Emergency Management and Crisis Response', 'Emergency Mgmt & Crisis Response'),
    ('Water Utilities',                                    'Dallas Water Utilities',                             'Water Utilities'),
    ('Dallas Water Utilities',                             'Dallas Water Utilities',                             'Water Utilities'),
    ('Parks Department',                                   'Parks Department',                                   'Parks'),
    ('Planning & Development Department',                  'Planning & Development Department',                  'Planning & Development'),
    ('Dallas Fire Rescue',                                 'Dallas Fire Rescue',                                 'Fire-Rescue'),
    ('Office of Budget',                                   'Office of Budget',                                   'Budget'),
    ('Office of Housing and Community Empowerment',        'Office of Housing and Community Empowerment',        'Housing'),
    ('Environmental Quality',                              'Environmental Quality',                              'Environmental Quality'),
    ('City Attorney''s Office',                            'City Attorney''s Office',                            'City Attorney'),
    ('Municipal Court & Detention Services',               'Municipal Court & Detention Services',               'Municipal Court'),
    ('Library',                                            'Library',                                            'Library'),
    ('Facilities and Real Estate Management',              'Facilities and Real Estate Management',              'Facilities & Real Estate'),
    ('Risk Management',                                    'Risk Management',                                    'Risk Management'),
    ('Convention & Event Services',                        'Convention and Event Services',                      'Convention & Events'),
    ('Convention and Event Services',                      'Convention and Event Services',                      'Convention & Events'),
    ('Office Bond and Construction Management',            'Office Bond and Construction Management',            'Bond & Construction');

-- any spelling not in the map stands for itself
INSERT INTO department_map
SELECT DISTINCT c_department, c_department, c_department
FROM staging.sr_typed
WHERE c_department NOT IN (SELECT raw_name FROM department_map);

INSERT INTO core.department (department_name, department_short)
SELECT DISTINCT canonical, short_name FROM department_map
WHERE raw_name IN (SELECT DISTINCT c_department FROM staging.sr_typed)
ORDER BY canonical;

INSERT INTO core.department_alias (raw_name, department_id)
SELECT m.raw_name, d.department_id
FROM department_map m
JOIN core.department d ON d.department_name = m.canonical
WHERE m.raw_name IN (SELECT DISTINCT c_department FROM staging.sr_typed);

-- 5b. request types (unique per canonical department) ----------------------------
INSERT INTO core.request_type (request_type_name, department_id)
SELECT DISTINCT t.c_request_type, a.department_id
FROM staging.sr_typed t
JOIN core.department_alias a ON a.raw_name = t.c_department
ORDER BY 1;

-- 5c. channels, classified by who started the request ----------------------------
INSERT INTO core.channel (channel_name, initiated_by)
SELECT DISTINCT c_channel,
       CASE WHEN c_channel IN ('Proactive', 'Internal', 'System', 'AI Camera Detection') THEN 'City'
            ELSE 'External' END
FROM staging.sr_typed
WHERE c_channel IS NOT NULL
ORDER BY 1;

-- 5d. statuses, classified once -----------------------------------------------------
INSERT INTO core.status (status_name, is_open, is_duplicate, is_resolved)
SELECT DISTINCT c_status,
       c_status ~ '^(New|In Progress|Escalated|On Hold)',
       c_status LIKE '%(Duplicate)%',
       c_status = 'Closed'
FROM staging.sr_typed;

-- 5e. the fact table ------------------------------------------------------------------
INSERT INTO core.service_request (
    sr_number, request_type_id, channel_id, status_name, council_district, priority, outcome, ert_text,
    address, zip_code, latitude, longitude, created_at, due_at, closed_at, updated_at)
SELECT
    t.c_sr_number,
    rt.request_type_id,
    ch.channel_id,
    t.c_status,
    t.c_district,
    t.c_priority,
    t.c_outcome,
    t.c_ert,
    t.c_address,
    t.c_zip,
    -- coordinates outside the Dallas area are treated as missing (counted in the data-quality report)
    CASE WHEN t.c_lat_raw BETWEEN 32.4 AND 33.2 AND t.c_lon_raw BETWEEN -97.2 AND -96.3 THEN t.c_lat_raw END,
    CASE WHEN t.c_lat_raw BETWEEN 32.4 AND 33.2 AND t.c_lon_raw BETWEEN -97.2 AND -96.3 THEN t.c_lon_raw END,
    t.c_created_at,
    t.c_due_at,
    t.c_closed_at,
    t.c_updated_at
FROM staging.sr_typed t
JOIN core.department_alias a ON a.raw_name = t.c_department
JOIN core.request_type rt ON rt.request_type_name = t.c_request_type AND rt.department_id = a.department_id
LEFT JOIN core.channel ch ON ch.channel_name = t.c_channel;
