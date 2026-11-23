-- =============================================================================
-- 05_roles.sql — least-privilege access for people who only analyze
--
-- analyst_readonly can read the analytics layer and nothing else. Views run with their owner's
-- rights, so analysts get clean, documented data without access to staging or the core tables.
-- =============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'analyst_readonly') THEN
        CREATE ROLE analyst_readonly NOLOGIN;
    END IF;
END
$$;

REVOKE ALL ON SCHEMA staging, core FROM analyst_readonly;
GRANT USAGE ON SCHEMA analytics TO analyst_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO analyst_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA analytics GRANT SELECT ON TABLES TO analyst_readonly;

-- Example: give a person a login that inherits the read-only role
--   CREATE ROLE jane LOGIN PASSWORD '...' IN ROLE analyst_readonly;
