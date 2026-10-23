-- pg_nanotime 0.1.0 -> 0.2.0: sum/avg(nanointerval), abs(nanointerval), nanointerval_from_ns(double precision), generate_series
\echo Use "ALTER EXTENSION pg_nanotime UPDATE TO '0.2.0'" to load this file. \quit

-- sum / avg over nanointerval (added in 0.2.0)
CREATE FUNCTION nanointerval_accum(internal, nanointerval) RETURNS internal AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE PARALLEL SAFE;
CREATE FUNCTION nanointerval_accum_inv(internal, nanointerval) RETURNS internal AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE PARALLEL SAFE;
CREATE FUNCTION nanointerval_agg_combine(internal, internal) RETURNS internal AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE PARALLEL SAFE;
CREATE FUNCTION nanointerval_agg_serialize(internal) RETURNS bytea AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_agg_deserialize(bytea, internal) RETURNS internal AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_sum_final(internal) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE PARALLEL SAFE;
CREATE FUNCTION nanointerval_avg_final(internal) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE PARALLEL SAFE;
CREATE AGGREGATE sum(nanointerval) (
  SFUNC = nanointerval_accum, STYPE = internal, SSPACE = 24,
  FINALFUNC = nanointerval_sum_final,
  COMBINEFUNC = nanointerval_agg_combine,
  SERIALFUNC = nanointerval_agg_serialize, DESERIALFUNC = nanointerval_agg_deserialize,
  MSFUNC = nanointerval_accum, MINVFUNC = nanointerval_accum_inv, MSTYPE = internal, MSSPACE = 24,
  MFINALFUNC = nanointerval_sum_final,
  PARALLEL = SAFE);
COMMENT ON AGGREGATE sum(nanointerval) IS 'exact sum; errors with "nanointerval out of range" on overflow';
CREATE AGGREGATE avg(nanointerval) (
  SFUNC = nanointerval_accum, STYPE = internal, SSPACE = 24,
  FINALFUNC = nanointerval_avg_final,
  COMBINEFUNC = nanointerval_agg_combine,
  SERIALFUNC = nanointerval_agg_serialize, DESERIALFUNC = nanointerval_agg_deserialize,
  MSFUNC = nanointerval_accum, MINVFUNC = nanointerval_accum_inv, MSTYPE = internal, MSSPACE = 24,
  MFINALFUNC = nanointerval_avg_final,
  PARALLEL = SAFE);
COMMENT ON AGGREGATE avg(nanointerval) IS 'exact average, rounded to the nearest ns (half away from zero), like nanointerval / bigint';

-- abs, nanointerval_from_ns(double precision / bigint), generate_series (added in 0.2.0)
CREATE FUNCTION abs(nanointerval) RETURNS nanointerval AS 'MODULE_PATHNAME', 'nanointerval_abs' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_from_ns(double precision) RETURNS nanointerval AS 'MODULE_PATHNAME', 'nanointerval_from_ns_float8' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_from_ns(bigint) RETURNS nanointerval AS 'MODULE_PATHNAME', 'nanointerval_from_ns_int8' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION nanointerval_from_ns(double precision) IS 'nanoseconds (rounded half away from zero) to nanointerval; inexact beyond 2^53 ns';
CREATE FUNCTION nanotime_generate_series_support(internal) RETURNS internal AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION generate_series(nanotimestamptz, nanotimestamptz, nanointerval) RETURNS SETOF nanotimestamptz
  AS 'MODULE_PATHNAME', 'nanotimestamptz_generate_series' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE
  SUPPORT nanotime_generate_series_support;
CREATE FUNCTION generate_series(nanotimestamptz8, nanotimestamptz8, nanointerval) RETURNS SETOF nanotimestamptz8
  AS 'MODULE_PATHNAME', 'nanotimestamptz8_generate_series' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE
  SUPPORT nanotime_generate_series_support;
CREATE FUNCTION generate_series(nanotimestamp, nanotimestamp, nanointerval) RETURNS SETOF nanotimestamp
  AS 'MODULE_PATHNAME', 'nanotimestamp_generate_series' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE
  SUPPORT nanotime_generate_series_support;
