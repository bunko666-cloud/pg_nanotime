-- TimescaleDB helpers without the timescaledb extension (regular suite):
-- pg_nanotime does not depend on TimescaleDB; the helpers raise a clear error.
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pg_nanotime;
RESET client_min_messages;
SELECT count(*) AS timescaledb_installed FROM pg_extension WHERE extname = 'timescaledb';
CREATE TABLE tsm(t nanotimestamptz NOT NULL, v int);
\set VERBOSITY default
SELECT nanotime_timescale_setup('tsm', 't', '1 day');
SELECT * FROM nanotime_drop_chunks('tsm', older_than => '2024-01-01 00:00:00+00');
\set VERBOSITY terse
-- plain PL/pgSQL functions (VOLATILE, SECURITY INVOKER) with no dependency on another extension
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, p.provolatile, p.prosecdef
  FROM pg_proc p WHERE p.proname IN ('nanotime_timescale_setup', 'nanotime_drop_chunks') ORDER BY 1;
SELECT count(*) AS deps_on_other_extensions FROM pg_depend d JOIN pg_extension e ON d.refclassid = 'pg_extension'::regclass AND d.refobjid = e.oid
 WHERE e.extname <> 'pg_nanotime' AND d.objid IN (SELECT oid FROM pg_proc WHERE proname LIKE 'nanotime_%');
DROP TABLE tsm;
