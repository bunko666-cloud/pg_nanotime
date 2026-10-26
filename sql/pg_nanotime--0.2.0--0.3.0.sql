-- pg_nanotime 0.2.0 -> 0.3.0: range types nanotstzrange / nanotsrange (and their multiranges),
-- TimescaleDB helpers nanotime_timescale_setup / nanotime_drop_chunks
\echo Use "ALTER EXTENSION pg_nanotime UPDATE TO '0.3.0'" to load this file. \quit

-- ===================== range types (added in 0.3.0) =====================
-- Continuous ranges (no canonical function), like the built-in tstzrange/tsrange.
-- subtype_diff returns seconds as float8, the same unit as tstzrange_subdiff.
CREATE FUNCTION nanotimestamptz_subdiff(nanotimestamptz, nanotimestamptz) RETURNS double precision
  AS 'MODULE_PATHNAME', 'nanotimestamptz_subdiff' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION nanotimestamptz_subdiff(nanotimestamptz, nanotimestamptz) IS 'subtype_diff for nanotstzrange: a - b in seconds';
CREATE FUNCTION nanotimestamp_subdiff(nanotimestamp, nanotimestamp) RETURNS double precision
  AS 'MODULE_PATHNAME', 'nanotimestamptz_subdiff' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION nanotimestamp_subdiff(nanotimestamp, nanotimestamp) IS 'subtype_diff for nanotsrange: a - b in seconds';

CREATE TYPE nanotstzrange AS RANGE (
  SUBTYPE = nanotimestamptz,
  SUBTYPE_DIFF = nanotimestamptz_subdiff
);
COMMENT ON TYPE nanotstzrange IS 'range of nanotimestamptz (continuous, like tstzrange); multirange: nanotstzmultirange';
CREATE TYPE nanotsrange AS RANGE (
  SUBTYPE = nanotimestamp,
  SUBTYPE_DIFF = nanotimestamp_subdiff
);
COMMENT ON TYPE nanotsrange IS 'range of nanotimestamp (continuous, like tsrange); multirange: nanotsmultirange';
COMMENT ON TYPE nanotstzmultirange IS 'multirange of nanotstzrange (created automatically with nanotstzrange)';
COMMENT ON TYPE nanotsmultirange IS 'multirange of nanotsrange (created automatically with nanotsrange)';

-- ======================= TimescaleDB one-step helpers (added in 0.3.0) ===========
-- These call TimescaleDB through dynamic SQL, so pg_nanotime itself does not
-- depend on it; without the timescaledb extension they raise a clear error.
-- Requires the by_range() API (TimescaleDB 2.13+; every TimescaleDB release
-- that supports PostgreSQL 17/18 has it).
CREATE FUNCTION nanotime_timescale_setup(tbl regclass, col name,
    chunk nanointerval DEFAULT '1 day', migrate_data bool DEFAULT false)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE
  ts_schema name;
  ts_version text;
  nt_schema name;
  att int2;
  typ oid;
  pfunc text;
  idx regclass;
  created bool := false;
BEGIN
  SELECT n.nspname, e.extversion INTO ts_schema, ts_version
    FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'timescaledb';
  IF ts_schema IS NULL THEN
    RAISE EXCEPTION 'TimescaleDB is not installed in this database'
      USING ERRCODE = 'object_not_in_prerequisite_state',
            HINT = 'pg_nanotime works without TimescaleDB; to use this helper, add timescaledb to shared_preload_libraries and run CREATE EXTENSION timescaledb.';
  END IF;
  IF to_regprocedure(format('%I.by_range(name, anyelement, regproc)', ts_schema)) IS NULL THEN
    RAISE EXCEPTION 'TimescaleDB % has no by_range(); nanotime_timescale_setup needs TimescaleDB 2.13 or later', ts_version
      USING ERRCODE = 'feature_not_supported';
  END IF;
  SELECT n.nspname INTO nt_schema
    FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'pg_nanotime';
  SELECT a.attnum, a.atttypid INTO att, typ FROM pg_attribute a
   WHERE a.attrelid = tbl AND a.attname = col AND NOT a.attisdropped AND a.attnum > 0;
  IF att IS NULL THEN
    RAISE EXCEPTION 'column "%" of relation % does not exist', col, tbl USING ERRCODE = 'undefined_column';
  END IF;
  pfunc := CASE typ
    WHEN to_regtype(format('%I.nanotimestamptz', nt_schema)) THEN 'nanotime_part'
    WHEN to_regtype(format('%I.nanotimestamp', nt_schema)) THEN 'nanotime_part_notz'
    WHEN to_regtype(format('%I.nanotimestamptz8', nt_schema)) THEN 'nanotime_part8'
  END;
  IF pfunc IS NULL THEN
    RAISE EXCEPTION 'column "%" of relation % is %, not nanotimestamptz, nanotimestamp or nanotimestamptz8', col, tbl, format_type(typ, NULL)
      USING ERRCODE = 'datatype_mismatch';
  END IF;
  IF chunk IS NULL OR chunk::bigint <= 0 THEN
    RAISE EXCEPTION 'chunk interval must be positive' USING ERRCODE = 'invalid_parameter_value';
  END IF;
  -- no default indexes: TimescaleDB would index the partitioning expression
  -- (e.g. nanotime_part(ts) DESC), which queries on the column cannot use
  EXECUTE format('SELECT %I.create_hypertable($1, %I.by_range($2, $3, $4), create_default_indexes => false, migrate_data => $5)',
                 ts_schema, ts_schema)
    USING tbl, col, chunk::bigint, format('%I.%I', nt_schema, pfunc)::regproc, migrate_data;
  EXECUTE format('SELECT %I.set_integer_now_func($1, $2)', ts_schema)
    USING tbl, format('%I.nanotime_now_int8', nt_schema)::regproc;
  -- any valid, non-partial B-tree index whose first column is col serves
  -- WHERE col ... and ORDER BY col [DESC] LIMIT n; otherwise add (col DESC)
  SELECT i.indexrelid::regclass INTO idx
    FROM pg_index i JOIN pg_class c ON c.oid = i.indexrelid JOIN pg_am am ON am.oid = c.relam
   WHERE i.indrelid = tbl AND i.indkey[0] = att AND am.amname = 'btree' AND i.indpred IS NULL AND i.indisvalid
   ORDER BY i.indexrelid LIMIT 1;
  IF idx IS NULL THEN
    EXECUTE format('CREATE INDEX ON %s (%I DESC)', tbl, col);
    SELECT i.indexrelid::regclass INTO idx FROM pg_index i
     WHERE i.indrelid = tbl AND i.indkey[0] = att ORDER BY i.indexrelid DESC LIMIT 1;
    created := true;
  END IF;
  RETURN format('hypertable %s: column %I (%s), partition_func %s, chunk %s (%s ns), integer_now_func nanotime_now_int8, index %s %s',
                tbl, col, format_type(typ, NULL), pfunc, chunk::text, chunk::bigint, idx,
                CASE WHEN created THEN 'created' ELSE 'already exists (kept)' END);
END $$;
COMMENT ON FUNCTION nanotime_timescale_setup(regclass, name, nanointerval, bool) IS
  'TimescaleDB: create_hypertable with the matching nanotime_part* function and chunk in ns, set_integer_now_func, and a (col DESC) index';

-- drop_chunks with a nanotimestamptz bound: converts it to the dimension's
-- bigint value (nanotime_part / nanotime_part_notz / nanotime_part8, saturating),
-- or to nanotimestamptz8 for an 8-byte column partitioned without a function.
CREATE FUNCTION nanotime_drop_chunks(tbl regclass,
    older_than nanotimestamptz DEFAULT NULL, newer_than nanotimestamptz DEFAULT NULL)
RETURNS SETOF text LANGUAGE plpgsql AS $$
DECLARE
  ts_schema name;
  nt_schema name;
  pfunc name;
  typ oid;
  o bigint;
  n bigint;
BEGIN
  SELECT n.nspname INTO ts_schema
    FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'timescaledb';
  IF ts_schema IS NULL THEN
    RAISE EXCEPTION 'TimescaleDB is not installed in this database'
      USING ERRCODE = 'object_not_in_prerequisite_state',
            HINT = 'pg_nanotime works without TimescaleDB; to use this helper, add timescaledb to shared_preload_libraries and run CREATE EXTENSION timescaledb.';
  END IF;
  SELECT n.nspname INTO nt_schema
    FROM pg_extension e JOIN pg_namespace n ON n.oid = e.extnamespace WHERE e.extname = 'pg_nanotime';
  SELECT d.partitioning_func, a.atttypid INTO pfunc, typ
    FROM _timescaledb_catalog.hypertable h
    JOIN _timescaledb_catalog.dimension d ON d.hypertable_id = h.id AND d.interval_length IS NOT NULL
    JOIN pg_class c ON c.oid = tbl JOIN pg_namespace cn ON cn.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = tbl AND a.attname = d.column_name
   WHERE h.schema_name = cn.nspname AND h.table_name = c.relname;
  IF typ IS NULL THEN
    RAISE EXCEPTION '% is not a hypertable', tbl USING ERRCODE = 'invalid_parameter_value';
  END IF;
  IF pfunc IN ('nanotime_part', 'nanotime_part8', 'nanotime_part_notz') THEN
    -- bigint dimension: the same (saturating) mapping the partition function uses
    EXECUTE format(CASE pfunc WHEN 'nanotime_part_notz'
                     THEN 'SELECT %1$I.nanotime_part_notz($1::%1$I.nanotimestamp), %1$I.nanotime_part_notz($2::%1$I.nanotimestamp)'
                     ELSE 'SELECT %1$I.nanotime_part($1), %1$I.nanotime_part($2)' END, nt_schema)
      INTO o, n USING older_than, newer_than;
    IF o = -9223372036854775808 THEN
      RETURN;  -- nothing can be older than the smallest value (TimescaleDB would reject the range)
    END IF;
    RETURN QUERY EXECUTE format('SELECT %I.drop_chunks($1, older_than => $2, newer_than => $3)', ts_schema)
      USING tbl, o, n;
  ELSIF pfunc IS NULL AND typ = to_regtype(format('%I.nanotimestamptz8', nt_schema)) THEN
    -- 8-byte column partitioned without a function: TimescaleDB takes the type itself
    RETURN QUERY EXECUTE format('SELECT %1$I.drop_chunks($1, older_than => $2::%2$I.nanotimestamptz8, newer_than => $3::%2$I.nanotimestamptz8)',
                                ts_schema, nt_schema)
      USING tbl, older_than, newer_than;
  ELSE
    RAISE EXCEPTION 'the time dimension of % is not a pg_nanotime column (partition_func %)', tbl, coalesce(pfunc::text, 'none')
      USING ERRCODE = 'invalid_parameter_value';
  END IF;
END $$;
COMMENT ON FUNCTION nanotime_drop_chunks(regclass, nanotimestamptz, nanotimestamptz) IS
  'TimescaleDB drop_chunks taking nanotimestamptz bounds (converted to the hypertable''s bigint/nanotimestamptz8 time value)';
