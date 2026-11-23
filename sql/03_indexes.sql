-- =============================================================================
-- 03_indexes.sql — created after the bulk load (faster than maintaining them during COPY/INSERT)
-- =============================================================================

-- BRIN suits an append-mostly table ordered by time: tiny index, fast date-range scans.
CREATE INDEX service_request_created_brin ON core.service_request USING brin (created_at);

-- Common filter/group paths: by request type over time, by district, by channel.
CREATE INDEX service_request_type_created_idx ON core.service_request (request_type_id, created_at);
CREATE INDEX service_request_district_idx     ON core.service_request (council_district);
CREATE INDEX service_request_channel_idx      ON core.service_request (channel_id);

-- Partial index: the open backlog is a small slice of the table that dashboards read constantly.
CREATE INDEX service_request_open_idx ON core.service_request (created_at)
    WHERE closed_at IS NULL;

-- Repeat-request analysis looks up earlier requests at the same address and type.
CREATE INDEX service_request_address_type_idx ON core.service_request (address, request_type_id, created_at)
    WHERE address IS NOT NULL;

-- Fresh planner statistics after the load.
ANALYZE core.department;
ANALYZE core.department_alias;
ANALYZE core.request_type;
ANALYZE core.channel;
ANALYZE core.status;
ANALYZE core.service_request;
