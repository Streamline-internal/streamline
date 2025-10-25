-- portal_ro schema & RO user setup (idempotent)
BEGIN;

CREATE SCHEMA IF NOT EXISTS portal_ro;

DO $$
DECLARE _user text := :'ro_user'; _pass text := :'ro_pass';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = _user) THEN
    EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', _user, _pass);
  END IF;
END$$;

CREATE MATERIALIZED VIEW IF NOT EXISTS portal_ro.kpi_daily AS
  SELECT * FROM public.kpi_daily WITH NO DATA;
CREATE MATERIALIZED VIEW IF NOT EXISTS portal_ro.pacing AS
  SELECT * FROM public.pacing WITH NO DATA;
CREATE MATERIALIZED VIEW IF NOT EXISTS portal_ro.creatives AS
  SELECT * FROM public.ads WITH NO DATA;
CREATE MATERIALIZED VIEW IF NOT EXISTS portal_ro.anomalies AS
  SELECT * FROM public.anomalies WITH NO DATA;
CREATE MATERIALIZED VIEW IF NOT EXISTS portal_ro.ops_log AS
  SELECT * FROM public.actions_log WITH NO DATA;

-- Refresh views (safe even if empty sources)
REFRESH MATERIALIZED VIEW CONCURRENTLY portal_ro.kpi_daily;
REFRESH MATERIALIZED VIEW CONCURRENTLY portal_ro.pacing;
REFRESH MATERIALIZED VIEW CONCURRENTLY portal_ro.creatives;
REFRESH MATERIALIZED VIEW CONCURRENTLY portal_ro.anomalies;
REFRESH MATERIALIZED VIEW CONCURRENTLY portal_ro.ops_log;

GRANT USAGE ON SCHEMA portal_ro TO :ro_user;
GRANT SELECT ON ALL TABLES IN SCHEMA portal_ro TO :ro_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA portal_ro GRANT SELECT ON TABLES TO :ro_user;

COMMIT;
