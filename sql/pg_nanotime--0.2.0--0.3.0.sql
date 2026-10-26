-- pg_nanotime 0.2.0 -> 0.3.0: range types nanotstzrange / nanotsrange (and their multiranges)
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
