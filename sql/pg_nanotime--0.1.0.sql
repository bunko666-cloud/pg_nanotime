\echo Use "CREATE EXTENSION pg_nanotime" to load this file. \quit

CREATE TYPE nanotimestamptz;

CREATE FUNCTION nanotimestamptz_in(cstring) RETURNS nanotimestamptz
  AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz_out(nanotimestamptz) RETURNS cstring
  AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz_recv(internal) RETURNS nanotimestamptz
  AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz_send(nanotimestamptz) RETURNS bytea
  AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE TYPE nanotimestamptz (
  INPUT = nanotimestamptz_in, OUTPUT = nanotimestamptz_out,
  RECEIVE = nanotimestamptz_recv, SEND = nanotimestamptz_send,
  INTERNALLENGTH = 16, ALIGNMENT = double, STORAGE = plain
);
COMMENT ON TYPE nanotimestamptz IS 'timestamp with time zone, nanosecond precision, 16 bytes';

CREATE FUNCTION nanotimestamptz_lt(nanotimestamptz, nanotimestamptz) RETURNS bool AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz_le(nanotimestamptz, nanotimestamptz) RETURNS bool AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz_eq(nanotimestamptz, nanotimestamptz) RETURNS bool AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz_ne(nanotimestamptz, nanotimestamptz) RETURNS bool AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz_ge(nanotimestamptz, nanotimestamptz) RETURNS bool AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz_gt(nanotimestamptz, nanotimestamptz) RETURNS bool AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz_cmp(nanotimestamptz, nanotimestamptz) RETURNS int4 AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz_hash(nanotimestamptz) RETURNS int4 AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz_larger(nanotimestamptz, nanotimestamptz) RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz_smaller(nanotimestamptz, nanotimestamptz) RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OPERATOR <  (LEFTARG = nanotimestamptz, RIGHTARG = nanotimestamptz, PROCEDURE = nanotimestamptz_lt, COMMUTATOR = >,  NEGATOR = >=, RESTRICT = scalarltsel, JOIN = scalarltjoinsel);
CREATE OPERATOR <= (LEFTARG = nanotimestamptz, RIGHTARG = nanotimestamptz, PROCEDURE = nanotimestamptz_le, COMMUTATOR = >=, NEGATOR = >,  RESTRICT = scalarlesel, JOIN = scalarlejoinsel);
CREATE OPERATOR =  (LEFTARG = nanotimestamptz, RIGHTARG = nanotimestamptz, PROCEDURE = nanotimestamptz_eq, COMMUTATOR = =,  NEGATOR = <>, RESTRICT = eqsel, JOIN = eqjoinsel, HASHES, MERGES);
CREATE OPERATOR <> (LEFTARG = nanotimestamptz, RIGHTARG = nanotimestamptz, PROCEDURE = nanotimestamptz_ne, COMMUTATOR = <>, NEGATOR = =,  RESTRICT = neqsel, JOIN = neqjoinsel);
CREATE OPERATOR >= (LEFTARG = nanotimestamptz, RIGHTARG = nanotimestamptz, PROCEDURE = nanotimestamptz_ge, COMMUTATOR = <=, NEGATOR = <,  RESTRICT = scalargesel, JOIN = scalargejoinsel);
CREATE OPERATOR >  (LEFTARG = nanotimestamptz, RIGHTARG = nanotimestamptz, PROCEDURE = nanotimestamptz_gt, COMMUTATOR = <,  NEGATOR = <=, RESTRICT = scalargtsel, JOIN = scalargtjoinsel);

CREATE OPERATOR CLASS nanotimestamptz_btree_ops DEFAULT FOR TYPE nanotimestamptz USING btree AS
  OPERATOR 1 <, OPERATOR 2 <=, OPERATOR 3 =, OPERATOR 4 >=, OPERATOR 5 >,
  FUNCTION 1 nanotimestamptz_cmp(nanotimestamptz, nanotimestamptz);
CREATE OPERATOR CLASS nanotimestamptz_hash_ops DEFAULT FOR TYPE nanotimestamptz USING hash AS
  OPERATOR 1 =, FUNCTION 1 nanotimestamptz_hash(nanotimestamptz);

CREATE OPERATOR CLASS nanotimestamptz_minmax_ops DEFAULT FOR TYPE nanotimestamptz USING brin AS
  OPERATOR 1 <, OPERATOR 2 <=, OPERATOR 3 =, OPERATOR 4 >=, OPERATOR 5 >,
  FUNCTION 1 brin_minmax_opcinfo(internal), FUNCTION 2 brin_minmax_add_value(internal, internal, internal, internal),
  FUNCTION 3 brin_minmax_consistent(internal, internal, internal), FUNCTION 4 brin_minmax_union(internal, internal, internal);

CREATE AGGREGATE min(nanotimestamptz) (SFUNC = nanotimestamptz_smaller, STYPE = nanotimestamptz, SORTOP = <, COMBINEFUNC = nanotimestamptz_smaller, PARALLEL = SAFE);
CREATE AGGREGATE max(nanotimestamptz) (SFUNC = nanotimestamptz_larger, STYPE = nanotimestamptz, SORTOP = >, COMBINEFUNC = nanotimestamptz_larger, PARALLEL = SAFE);

-- casts
CREATE FUNCTION nanotimestamptz(timestamptz) RETURNS nanotimestamptz AS 'MODULE_PATHNAME', 'nanotimestamptz_from_timestamptz' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION timestamptz(nanotimestamptz) RETURNS timestamptz AS 'MODULE_PATHNAME', 'nanotimestamptz_to_timestamptz' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz(bigint) RETURNS nanotimestamptz AS 'MODULE_PATHNAME', 'nanotimestamptz_from_int8' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION int8(nanotimestamptz) RETURNS bigint AS 'MODULE_PATHNAME', 'nanotimestamptz_to_int8' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE CAST (timestamptz AS nanotimestamptz) WITH FUNCTION nanotimestamptz(timestamptz) AS IMPLICIT;
CREATE CAST (nanotimestamptz AS timestamptz) WITH FUNCTION timestamptz(nanotimestamptz) AS ASSIGNMENT;
CREATE CAST (bigint AS nanotimestamptz) WITH FUNCTION nanotimestamptz(bigint);
CREATE CAST (nanotimestamptz AS bigint) WITH FUNCTION int8(nanotimestamptz);

-- clocks
CREATE FUNCTION clock_ns() RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C VOLATILE PARALLEL SAFE;
CREATE FUNCTION now_ns() RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C STABLE PARALLEL RESTRICTED;
CREATE FUNCTION statement_ns() RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C STABLE PARALLEL RESTRICTED;

-- ===================== nanotimestamptz8: 8-byte compact type =====================
-- int64 nanoseconds since 1970-01-01 UTC, pass by value, binary-compatible with bigint.
CREATE TYPE nanotimestamptz8;
CREATE FUNCTION nanotimestamptz8_in(cstring) RETURNS nanotimestamptz8
  AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz8_out(nanotimestamptz8) RETURNS cstring
  AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;
-- binary format = int8 (every int64 is a valid value)
CREATE FUNCTION nanotimestamptz8_recv(internal) RETURNS nanotimestamptz8 AS 'int8recv' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz8_send(nanotimestamptz8) RETURNS bytea AS 'int8send' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;

CREATE TYPE nanotimestamptz8 (
  INPUT = nanotimestamptz8_in, OUTPUT = nanotimestamptz8_out,
  RECEIVE = nanotimestamptz8_recv, SEND = nanotimestamptz8_send,
  INTERNALLENGTH = 8, PASSEDBYVALUE, ALIGNMENT = double, STORAGE = plain
);
COMMENT ON TYPE nanotimestamptz8 IS 'timestamp with time zone, nanosecond precision, 8 bytes (1677-09-21 .. 2262-04-11)';

-- comparisons reuse PostgreSQL's int8 functions (same representation)
CREATE FUNCTION nanotimestamptz8_lt(nanotimestamptz8, nanotimestamptz8) RETURNS bool AS 'int8lt' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz8_le(nanotimestamptz8, nanotimestamptz8) RETURNS bool AS 'int8le' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz8_eq(nanotimestamptz8, nanotimestamptz8) RETURNS bool AS 'int8eq' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz8_ne(nanotimestamptz8, nanotimestamptz8) RETURNS bool AS 'int8ne' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz8_ge(nanotimestamptz8, nanotimestamptz8) RETURNS bool AS 'int8ge' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz8_gt(nanotimestamptz8, nanotimestamptz8) RETURNS bool AS 'int8gt' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz8_cmp(nanotimestamptz8, nanotimestamptz8) RETURNS int4 AS 'btint8cmp' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz8_hash(nanotimestamptz8) RETURNS int4 AS 'hashint8' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamptz8_larger(nanotimestamptz8, nanotimestamptz8) RETURNS nanotimestamptz8 AS 'int8larger' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz8_smaller(nanotimestamptz8, nanotimestamptz8) RETURNS nanotimestamptz8 AS 'int8smaller' LANGUAGE internal IMMUTABLE STRICT PARALLEL SAFE;

CREATE OPERATOR <  (LEFTARG = nanotimestamptz8, RIGHTARG = nanotimestamptz8, PROCEDURE = nanotimestamptz8_lt, COMMUTATOR = >,  NEGATOR = >=, RESTRICT = scalarltsel, JOIN = scalarltjoinsel);
CREATE OPERATOR <= (LEFTARG = nanotimestamptz8, RIGHTARG = nanotimestamptz8, PROCEDURE = nanotimestamptz8_le, COMMUTATOR = >=, NEGATOR = >,  RESTRICT = scalarlesel, JOIN = scalarlejoinsel);
CREATE OPERATOR =  (LEFTARG = nanotimestamptz8, RIGHTARG = nanotimestamptz8, PROCEDURE = nanotimestamptz8_eq, COMMUTATOR = =,  NEGATOR = <>, RESTRICT = eqsel, JOIN = eqjoinsel, HASHES, MERGES);
CREATE OPERATOR <> (LEFTARG = nanotimestamptz8, RIGHTARG = nanotimestamptz8, PROCEDURE = nanotimestamptz8_ne, COMMUTATOR = <>, NEGATOR = =,  RESTRICT = neqsel, JOIN = neqjoinsel);
CREATE OPERATOR >= (LEFTARG = nanotimestamptz8, RIGHTARG = nanotimestamptz8, PROCEDURE = nanotimestamptz8_ge, COMMUTATOR = <=, NEGATOR = <,  RESTRICT = scalargesel, JOIN = scalargejoinsel);
CREATE OPERATOR >  (LEFTARG = nanotimestamptz8, RIGHTARG = nanotimestamptz8, PROCEDURE = nanotimestamptz8_gt, COMMUTATOR = <,  NEGATOR = <=, RESTRICT = scalargtsel, JOIN = scalargtjoinsel);

CREATE OPERATOR CLASS nanotimestamptz8_btree_ops DEFAULT FOR TYPE nanotimestamptz8 USING btree AS
  OPERATOR 1 <, OPERATOR 2 <=, OPERATOR 3 =, OPERATOR 4 >=, OPERATOR 5 >,
  FUNCTION 1 nanotimestamptz8_cmp(nanotimestamptz8, nanotimestamptz8);
CREATE OPERATOR CLASS nanotimestamptz8_hash_ops DEFAULT FOR TYPE nanotimestamptz8 USING hash AS
  OPERATOR 1 =, FUNCTION 1 nanotimestamptz8_hash(nanotimestamptz8);
CREATE OPERATOR CLASS nanotimestamptz8_minmax_ops DEFAULT FOR TYPE nanotimestamptz8 USING brin AS
  OPERATOR 1 <, OPERATOR 2 <=, OPERATOR 3 =, OPERATOR 4 >=, OPERATOR 5 >,
  FUNCTION 1 brin_minmax_opcinfo(internal), FUNCTION 2 brin_minmax_add_value(internal, internal, internal, internal),
  FUNCTION 3 brin_minmax_consistent(internal, internal, internal), FUNCTION 4 brin_minmax_union(internal, internal, internal);

CREATE AGGREGATE min(nanotimestamptz8) (SFUNC = nanotimestamptz8_smaller, STYPE = nanotimestamptz8, SORTOP = <, COMBINEFUNC = nanotimestamptz8_smaller, PARALLEL = SAFE);
CREATE AGGREGATE max(nanotimestamptz8) (SFUNC = nanotimestamptz8_larger, STYPE = nanotimestamptz8, SORTOP = >, COMBINEFUNC = nanotimestamptz8_larger, PARALLEL = SAFE);

-- casts
CREATE FUNCTION nanotimestamptz(nanotimestamptz8) RETURNS nanotimestamptz AS 'MODULE_PATHNAME', 'nanotimestamptz8_to_nanotimestamptz' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz8(nanotimestamptz) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME', 'nanotimestamptz8_from_nanotimestamptz' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION timestamptz(nanotimestamptz8) RETURNS timestamptz AS 'MODULE_PATHNAME', 'nanotimestamptz8_to_timestamptz' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz8(timestamptz) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME', 'nanotimestamptz8_from_timestamptz' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE CAST (nanotimestamptz8 AS nanotimestamptz) WITH FUNCTION nanotimestamptz(nanotimestamptz8) AS IMPLICIT;
CREATE CAST (nanotimestamptz AS nanotimestamptz8) WITH FUNCTION nanotimestamptz8(nanotimestamptz) AS ASSIGNMENT;
CREATE CAST (nanotimestamptz8 AS timestamptz) WITH FUNCTION timestamptz(nanotimestamptz8) AS ASSIGNMENT;
CREATE CAST (timestamptz AS nanotimestamptz8) WITH FUNCTION nanotimestamptz8(timestamptz) AS ASSIGNMENT;
-- binary-compatible, explicit only: every bigint is a valid nanotimestamptz8 and vice versa
CREATE CAST (bigint AS nanotimestamptz8) WITHOUT FUNCTION;
CREATE CAST (nanotimestamptz8 AS bigint) WITHOUT FUNCTION;

-- clocks returning the compact type
CREATE FUNCTION clock_ns8() RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME' LANGUAGE C VOLATILE PARALLEL SAFE;
CREATE FUNCTION now_ns8() RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME' LANGUAGE C STABLE PARALLEL RESTRICTED;
CREATE FUNCTION statement_ns8() RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME' LANGUAGE C STABLE PARALLEL RESTRICTED;

-- ============================ nanointerval ============================
-- Fixed nanoseconds only (no months/days). 16 bytes {int64 sec, int64 nsec},
-- range +/- (max - min of nanotimestamptz), so every ts - ts difference fits.
CREATE TYPE nanointerval;
CREATE FUNCTION nanointerval_in(cstring) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_out(nanointerval) RETURNS cstring AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_recv(internal) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_send(nanointerval) RETURNS bytea AS 'MODULE_PATHNAME', 'nanotimestamptz_send' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
-- CATEGORY 'T' (timespan): for an untyped literal such as ts + '1 day',
-- PostgreSQL prefers the built-in interval (calendar semantics).
CREATE TYPE nanointerval (
  INPUT = nanointerval_in, OUTPUT = nanointerval_out,
  RECEIVE = nanointerval_recv, SEND = nanointerval_send,
  INTERNALLENGTH = 16, ALIGNMENT = double, STORAGE = plain, CATEGORY = 'T'
);
COMMENT ON TYPE nanointerval IS 'fixed-length time span in nanoseconds (no months or days)';

CREATE FUNCTION nanointerval_lt(nanointerval, nanointerval) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_lt' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanointerval_le(nanointerval, nanointerval) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_le' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanointerval_eq(nanointerval, nanointerval) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_eq' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanointerval_ne(nanointerval, nanointerval) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_ne' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanointerval_ge(nanointerval, nanointerval) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_ge' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanointerval_gt(nanointerval, nanointerval) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_gt' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanointerval_cmp(nanointerval, nanointerval) RETURNS int4 AS 'MODULE_PATHNAME', 'nanotimestamptz_cmp' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanointerval_hash(nanointerval) RETURNS int4 AS 'MODULE_PATHNAME', 'nanotimestamptz_hash' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanointerval_larger(nanointerval, nanointerval) RETURNS nanointerval AS 'MODULE_PATHNAME', 'nanotimestamptz_larger' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_smaller(nanointerval, nanointerval) RETURNS nanointerval AS 'MODULE_PATHNAME', 'nanotimestamptz_smaller' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OPERATOR <  (LEFTARG = nanointerval, RIGHTARG = nanointerval, PROCEDURE = nanointerval_lt, COMMUTATOR = >,  NEGATOR = >=, RESTRICT = scalarltsel, JOIN = scalarltjoinsel);
CREATE OPERATOR <= (LEFTARG = nanointerval, RIGHTARG = nanointerval, PROCEDURE = nanointerval_le, COMMUTATOR = >=, NEGATOR = >,  RESTRICT = scalarlesel, JOIN = scalarlejoinsel);
CREATE OPERATOR =  (LEFTARG = nanointerval, RIGHTARG = nanointerval, PROCEDURE = nanointerval_eq, COMMUTATOR = =,  NEGATOR = <>, RESTRICT = eqsel, JOIN = eqjoinsel, HASHES, MERGES);
CREATE OPERATOR <> (LEFTARG = nanointerval, RIGHTARG = nanointerval, PROCEDURE = nanointerval_ne, COMMUTATOR = <>, NEGATOR = =,  RESTRICT = neqsel, JOIN = neqjoinsel);
CREATE OPERATOR >= (LEFTARG = nanointerval, RIGHTARG = nanointerval, PROCEDURE = nanointerval_ge, COMMUTATOR = <=, NEGATOR = <,  RESTRICT = scalargesel, JOIN = scalargejoinsel);
CREATE OPERATOR >  (LEFTARG = nanointerval, RIGHTARG = nanointerval, PROCEDURE = nanointerval_gt, COMMUTATOR = <,  NEGATOR = <=, RESTRICT = scalargtsel, JOIN = scalargtjoinsel);
CREATE OPERATOR CLASS nanointerval_btree_ops DEFAULT FOR TYPE nanointerval USING btree AS
  OPERATOR 1 <, OPERATOR 2 <=, OPERATOR 3 =, OPERATOR 4 >=, OPERATOR 5 >,
  FUNCTION 1 nanointerval_cmp(nanointerval, nanointerval);
CREATE OPERATOR CLASS nanointerval_hash_ops DEFAULT FOR TYPE nanointerval USING hash AS
  OPERATOR 1 =, FUNCTION 1 nanointerval_hash(nanointerval);
CREATE AGGREGATE min(nanointerval) (SFUNC = nanointerval_smaller, STYPE = nanointerval, SORTOP = <, COMBINEFUNC = nanointerval_smaller, PARALLEL = SAFE);
CREATE AGGREGATE max(nanointerval) (SFUNC = nanointerval_larger, STYPE = nanointerval, SORTOP = >, COMBINEFUNC = nanointerval_larger, PARALLEL = SAFE);

-- arithmetic
CREATE FUNCTION nanointerval_um(nanointerval) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_pl(nanointerval, nanointerval) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_mi(nanointerval, nanointerval) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_mul_int8(nanointerval, bigint) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION int8_mul_nanointerval(bigint, nanointerval) RETURNS nanointerval AS 'SELECT nanointerval_mul_int8($2, $1)' LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_div_int8(nanointerval, bigint) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_ns(nanointerval) RETURNS numeric AS 'MODULE_PATHNAME', 'nanointerval_to_ns_numeric' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION nanointerval_ns(nanointerval) IS 'total nanoseconds as numeric (exact)';
CREATE FUNCTION nanointerval_from_ns(numeric) RETURNS nanointerval AS 'MODULE_PATHNAME', 'nanointerval_from_ns_numeric' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
COMMENT ON FUNCTION nanointerval_from_ns(numeric) IS 'nanoseconds (rounded half away from zero) to nanointerval';
CREATE FUNCTION nanointerval_mul_numeric(nanointerval, numeric) RETURNS nanointerval
  AS 'SELECT nanointerval_from_ns(nanointerval_ns($1) * $2)' LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION numeric_mul_nanointerval(numeric, nanointerval) RETURNS nanointerval
  AS 'SELECT nanointerval_from_ns(nanointerval_ns($2) * $1)' LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_div_numeric(nanointerval, numeric) RETURNS nanointerval
  AS 'SELECT nanointerval_from_ns(nanointerval_ns($1) / $2)' LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;

CREATE OPERATOR - (RIGHTARG = nanointerval, PROCEDURE = nanointerval_um);
CREATE OPERATOR + (LEFTARG = nanointerval, RIGHTARG = nanointerval, PROCEDURE = nanointerval_pl, COMMUTATOR = +);
CREATE OPERATOR - (LEFTARG = nanointerval, RIGHTARG = nanointerval, PROCEDURE = nanointerval_mi);
CREATE OPERATOR * (LEFTARG = nanointerval, RIGHTARG = bigint, PROCEDURE = nanointerval_mul_int8, COMMUTATOR = *);
CREATE OPERATOR * (LEFTARG = bigint, RIGHTARG = nanointerval, PROCEDURE = int8_mul_nanointerval, COMMUTATOR = *);
CREATE OPERATOR / (LEFTARG = nanointerval, RIGHTARG = bigint, PROCEDURE = nanointerval_div_int8);
-- int4 variants avoid "operator is not unique" between bigint and numeric for integer literals
CREATE FUNCTION nanointerval_mul_int4(nanointerval, integer) RETURNS nanointerval AS 'SELECT nanointerval_mul_int8($1, $2)' LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION int4_mul_nanointerval(integer, nanointerval) RETURNS nanointerval AS 'SELECT nanointerval_mul_int8($2, $1)' LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_div_int4(nanointerval, integer) RETURNS nanointerval AS 'SELECT nanointerval_div_int8($1, $2)' LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE;
CREATE OPERATOR * (LEFTARG = nanointerval, RIGHTARG = integer, PROCEDURE = nanointerval_mul_int4, COMMUTATOR = *);
CREATE OPERATOR * (LEFTARG = integer, RIGHTARG = nanointerval, PROCEDURE = int4_mul_nanointerval, COMMUTATOR = *);
CREATE OPERATOR / (LEFTARG = nanointerval, RIGHTARG = integer, PROCEDURE = nanointerval_div_int4);
CREATE OPERATOR * (LEFTARG = nanointerval, RIGHTARG = numeric, PROCEDURE = nanointerval_mul_numeric, COMMUTATOR = *);
CREATE OPERATOR * (LEFTARG = numeric, RIGHTARG = nanointerval, PROCEDURE = numeric_mul_nanointerval, COMMUTATOR = *);
CREATE OPERATOR / (LEFTARG = nanointerval, RIGHTARG = numeric, PROCEDURE = nanointerval_div_numeric);

-- casts
CREATE FUNCTION nanointerval(interval) RETURNS nanointerval AS 'MODULE_PATHNAME', 'nanointerval_from_interval' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION "interval"(nanointerval) RETURNS interval AS 'MODULE_PATHNAME', 'nanointerval_to_interval' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval(bigint) RETURNS nanointerval AS 'MODULE_PATHNAME', 'nanointerval_from_int8' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION int8(nanointerval) RETURNS bigint AS 'MODULE_PATHNAME', 'nanointerval_to_int8' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE CAST (interval AS nanointerval) WITH FUNCTION nanointerval(interval) AS ASSIGNMENT;
CREATE CAST (nanointerval AS interval) WITH FUNCTION "interval"(nanointerval) AS ASSIGNMENT;
CREATE CAST (bigint AS nanointerval) WITH FUNCTION nanointerval(bigint);
CREATE CAST (nanointerval AS bigint) WITH FUNCTION int8(nanointerval);

-- ======================= timestamp arithmetic =======================
CREATE FUNCTION nanotimestamptz_mi(nanotimestamptz, nanotimestamptz) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz_pl_nanointerval(nanotimestamptz, nanointerval) RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz_mi_nanointerval(nanotimestamptz, nanointerval) RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_pl_nanotimestamptz(nanointerval, nanotimestamptz) RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
-- with PostgreSQL interval: STABLE, because months/days follow the session TimeZone
CREATE FUNCTION nanotimestamptz_pl_interval(nanotimestamptz, interval) RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz_mi_interval(nanotimestamptz, interval) RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION interval_pl_nanotimestamptz(interval, nanotimestamptz) RETURNS nanotimestamptz AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;

CREATE OPERATOR - (LEFTARG = nanotimestamptz, RIGHTARG = nanotimestamptz, PROCEDURE = nanotimestamptz_mi);
CREATE OPERATOR + (LEFTARG = nanotimestamptz, RIGHTARG = nanointerval, PROCEDURE = nanotimestamptz_pl_nanointerval, COMMUTATOR = +);
CREATE OPERATOR + (LEFTARG = nanointerval, RIGHTARG = nanotimestamptz, PROCEDURE = nanointerval_pl_nanotimestamptz, COMMUTATOR = +);
CREATE OPERATOR - (LEFTARG = nanotimestamptz, RIGHTARG = nanointerval, PROCEDURE = nanotimestamptz_mi_nanointerval);
CREATE OPERATOR + (LEFTARG = nanotimestamptz, RIGHTARG = interval, PROCEDURE = nanotimestamptz_pl_interval, COMMUTATOR = +);
CREATE OPERATOR + (LEFTARG = interval, RIGHTARG = nanotimestamptz, PROCEDURE = interval_pl_nanotimestamptz, COMMUTATOR = +);
CREATE OPERATOR - (LEFTARG = nanotimestamptz, RIGHTARG = interval, PROCEDURE = nanotimestamptz_mi_interval);

CREATE FUNCTION nanotimestamptz8_mi(nanotimestamptz8, nanotimestamptz8) RETURNS nanointerval AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz8_pl_nanointerval(nanotimestamptz8, nanointerval) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz8_mi_nanointerval(nanotimestamptz8, nanointerval) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_pl_nanotimestamptz8(nanointerval, nanotimestamptz8) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz8_pl_interval(nanotimestamptz8, interval) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz8_mi_interval(nanotimestamptz8, interval) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION interval_pl_nanotimestamptz8(interval, nanotimestamptz8) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME' LANGUAGE C STABLE STRICT PARALLEL SAFE;

CREATE OPERATOR - (LEFTARG = nanotimestamptz8, RIGHTARG = nanotimestamptz8, PROCEDURE = nanotimestamptz8_mi);
CREATE OPERATOR + (LEFTARG = nanotimestamptz8, RIGHTARG = nanointerval, PROCEDURE = nanotimestamptz8_pl_nanointerval, COMMUTATOR = +);
CREATE OPERATOR + (LEFTARG = nanointerval, RIGHTARG = nanotimestamptz8, PROCEDURE = nanointerval_pl_nanotimestamptz8, COMMUTATOR = +);
CREATE OPERATOR - (LEFTARG = nanotimestamptz8, RIGHTARG = nanointerval, PROCEDURE = nanotimestamptz8_mi_nanointerval);
CREATE OPERATOR + (LEFTARG = nanotimestamptz8, RIGHTARG = interval, PROCEDURE = nanotimestamptz8_pl_interval, COMMUTATOR = +);
CREATE OPERATOR + (LEFTARG = interval, RIGHTARG = nanotimestamptz8, PROCEDURE = interval_pl_nanotimestamptz8, COMMUTATOR = +);
CREATE OPERATOR - (LEFTARG = nanotimestamptz8, RIGHTARG = interval, PROCEDURE = nanotimestamptz8_mi_interval);

-- ======================= bucketing / truncation / extract =======================
CREATE FUNCTION time_bucket_ns(nanointerval, nanotimestamptz, nanotimestamptz DEFAULT '1970-01-01 00:00:00+00')
  RETURNS nanotimestamptz AS 'MODULE_PATHNAME', 'time_bucket_ns' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION time_bucket_ns(nanointerval, nanotimestamptz8, nanotimestamptz8 DEFAULT '1970-01-01 00:00:00+00')
  RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME', 'time_bucket_ns8' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE FUNCTION date_trunc(text, nanotimestamptz) RETURNS nanotimestamptz AS 'MODULE_PATHNAME', 'nanotimestamptz_trunc' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION date_trunc(text, nanotimestamptz, text) RETURNS nanotimestamptz AS 'MODULE_PATHNAME', 'nanotimestamptz_trunc' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION date_trunc(text, nanotimestamptz8) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME', 'nanotimestamptz8_trunc' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION date_trunc(text, nanotimestamptz8, text) RETURNS nanotimestamptz8 AS 'MODULE_PATHNAME', 'nanotimestamptz8_trunc' LANGUAGE C STABLE STRICT PARALLEL SAFE;

-- EXTRACT(... FROM ...) syntax is hard-wired to pg_catalog.extract, so these are named extract_ns
CREATE FUNCTION extract_ns(text, nanotimestamptz) RETURNS numeric AS 'MODULE_PATHNAME', 'nanotimestamptz_extract' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION extract_ns(text, nanointerval) RETURNS numeric AS 'MODULE_PATHNAME', 'nanointerval_extract' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- ===================== nanotimestamp: without time zone =====================
-- Same 16-byte layout as nanotimestamptz; sec = wall-clock seconds from
-- 1970-01-01 00:00:00 with no zone (like PostgreSQL timestamp). Comparison,
-- hashing, binary send and ts - ts reuse the nanotimestamptz C functions.
CREATE TYPE nanotimestamp;
CREATE FUNCTION nanotimestamp_in(cstring) RETURNS nanotimestamp AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp_out(nanotimestamp) RETURNS cstring AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp_recv(internal) RETURNS nanotimestamp AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp_send(nanotimestamp) RETURNS bytea AS 'MODULE_PATHNAME', 'nanotimestamptz_send' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE TYPE nanotimestamp (
  INPUT = nanotimestamp_in, OUTPUT = nanotimestamp_out,
  RECEIVE = nanotimestamp_recv, SEND = nanotimestamp_send,
  INTERNALLENGTH = 16, ALIGNMENT = double, STORAGE = plain
);
COMMENT ON TYPE nanotimestamp IS 'timestamp without time zone, nanosecond precision, 16 bytes';

CREATE FUNCTION nanotimestamp_lt(nanotimestamp, nanotimestamp) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_lt' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamp_le(nanotimestamp, nanotimestamp) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_le' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamp_eq(nanotimestamp, nanotimestamp) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_eq' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamp_ne(nanotimestamp, nanotimestamp) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_ne' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamp_ge(nanotimestamp, nanotimestamp) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_ge' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamp_gt(nanotimestamp, nanotimestamp) RETURNS bool AS 'MODULE_PATHNAME', 'nanotimestamptz_gt' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamp_cmp(nanotimestamp, nanotimestamp) RETURNS int4 AS 'MODULE_PATHNAME', 'nanotimestamptz_cmp' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamp_hash(nanotimestamp) RETURNS int4 AS 'MODULE_PATHNAME', 'nanotimestamptz_hash' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE LEAKPROOF;
CREATE FUNCTION nanotimestamp_larger(nanotimestamp, nanotimestamp) RETURNS nanotimestamp AS 'MODULE_PATHNAME', 'nanotimestamptz_larger' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp_smaller(nanotimestamp, nanotimestamp) RETURNS nanotimestamp AS 'MODULE_PATHNAME', 'nanotimestamptz_smaller' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE OPERATOR <  (LEFTARG = nanotimestamp, RIGHTARG = nanotimestamp, PROCEDURE = nanotimestamp_lt, COMMUTATOR = >,  NEGATOR = >=, RESTRICT = scalarltsel, JOIN = scalarltjoinsel);
CREATE OPERATOR <= (LEFTARG = nanotimestamp, RIGHTARG = nanotimestamp, PROCEDURE = nanotimestamp_le, COMMUTATOR = >=, NEGATOR = >,  RESTRICT = scalarlesel, JOIN = scalarlejoinsel);
CREATE OPERATOR =  (LEFTARG = nanotimestamp, RIGHTARG = nanotimestamp, PROCEDURE = nanotimestamp_eq, COMMUTATOR = =,  NEGATOR = <>, RESTRICT = eqsel, JOIN = eqjoinsel, HASHES, MERGES);
CREATE OPERATOR <> (LEFTARG = nanotimestamp, RIGHTARG = nanotimestamp, PROCEDURE = nanotimestamp_ne, COMMUTATOR = <>, NEGATOR = =,  RESTRICT = neqsel, JOIN = neqjoinsel);
CREATE OPERATOR >= (LEFTARG = nanotimestamp, RIGHTARG = nanotimestamp, PROCEDURE = nanotimestamp_ge, COMMUTATOR = <=, NEGATOR = <,  RESTRICT = scalargesel, JOIN = scalargejoinsel);
CREATE OPERATOR >  (LEFTARG = nanotimestamp, RIGHTARG = nanotimestamp, PROCEDURE = nanotimestamp_gt, COMMUTATOR = <,  NEGATOR = <=, RESTRICT = scalargtsel, JOIN = scalargtjoinsel);

CREATE OPERATOR CLASS nanotimestamp_btree_ops DEFAULT FOR TYPE nanotimestamp USING btree AS
  OPERATOR 1 <, OPERATOR 2 <=, OPERATOR 3 =, OPERATOR 4 >=, OPERATOR 5 >,
  FUNCTION 1 nanotimestamp_cmp(nanotimestamp, nanotimestamp);
CREATE OPERATOR CLASS nanotimestamp_hash_ops DEFAULT FOR TYPE nanotimestamp USING hash AS
  OPERATOR 1 =, FUNCTION 1 nanotimestamp_hash(nanotimestamp);
CREATE OPERATOR CLASS nanotimestamp_minmax_ops DEFAULT FOR TYPE nanotimestamp USING brin AS
  OPERATOR 1 <, OPERATOR 2 <=, OPERATOR 3 =, OPERATOR 4 >=, OPERATOR 5 >,
  FUNCTION 1 brin_minmax_opcinfo(internal), FUNCTION 2 brin_minmax_add_value(internal, internal, internal, internal),
  FUNCTION 3 brin_minmax_consistent(internal, internal, internal), FUNCTION 4 brin_minmax_union(internal, internal, internal);

CREATE AGGREGATE min(nanotimestamp) (SFUNC = nanotimestamp_smaller, STYPE = nanotimestamp, SORTOP = <, COMBINEFUNC = nanotimestamp_smaller, PARALLEL = SAFE);
CREATE AGGREGATE max(nanotimestamp) (SFUNC = nanotimestamp_larger, STYPE = nanotimestamp, SORTOP = >, COMBINEFUNC = nanotimestamp_larger, PARALLEL = SAFE);

-- casts (contexts mirror timestamp / timestamptz in core)
CREATE FUNCTION nanotimestamp(timestamp) RETURNS nanotimestamp AS 'MODULE_PATHNAME', 'nanotimestamp_from_timestamp' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION "timestamp"(nanotimestamp) RETURNS timestamp AS 'MODULE_PATHNAME', 'nanotimestamp_to_timestamp' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp(date) RETURNS nanotimestamp AS 'MODULE_PATHNAME', 'nanotimestamp_from_date' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION date(nanotimestamp) RETURNS date AS 'MODULE_PATHNAME', 'nanotimestamp_to_date' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz(date) RETURNS nanotimestamptz AS 'MODULE_PATHNAME', 'nanotimestamptz_from_date' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION date(nanotimestamptz) RETURNS date AS 'MODULE_PATHNAME', 'nanotimestamptz_to_date' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamptz(nanotimestamp) RETURNS nanotimestamptz AS 'MODULE_PATHNAME', 'nanotimestamp_to_nanotimestamptz' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp(nanotimestamptz) RETURNS nanotimestamp AS 'MODULE_PATHNAME', 'nanotimestamptz_to_nanotimestamp' LANGUAGE C STABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp(bigint) RETURNS nanotimestamp AS 'MODULE_PATHNAME', 'nanotimestamp_from_int8' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION int8(nanotimestamp) RETURNS bigint AS 'MODULE_PATHNAME', 'nanotimestamp_to_int8' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

CREATE CAST (timestamp AS nanotimestamp) WITH FUNCTION nanotimestamp(timestamp) AS IMPLICIT;
CREATE CAST (nanotimestamp AS timestamp) WITH FUNCTION "timestamp"(nanotimestamp) AS ASSIGNMENT;
CREATE CAST (date AS nanotimestamp) WITH FUNCTION nanotimestamp(date) AS IMPLICIT;
CREATE CAST (nanotimestamp AS date) WITH FUNCTION date(nanotimestamp) AS ASSIGNMENT;
CREATE CAST (date AS nanotimestamptz) WITH FUNCTION nanotimestamptz(date) AS ASSIGNMENT;
CREATE CAST (nanotimestamptz AS date) WITH FUNCTION date(nanotimestamptz) AS ASSIGNMENT;
CREATE CAST (nanotimestamp AS nanotimestamptz) WITH FUNCTION nanotimestamptz(nanotimestamp) AS IMPLICIT;
CREATE CAST (nanotimestamptz AS nanotimestamp) WITH FUNCTION nanotimestamp(nanotimestamptz) AS ASSIGNMENT;
CREATE CAST (bigint AS nanotimestamp) WITH FUNCTION nanotimestamp(bigint);
CREATE CAST (nanotimestamp AS bigint) WITH FUNCTION int8(nanotimestamp);

-- AT TIME ZONE equivalents (the AT TIME ZONE syntax itself is bound to pg_catalog.timezone)
CREATE FUNCTION timezone(text, nanotimestamp) RETURNS nanotimestamptz AS 'MODULE_PATHNAME', 'nanotimestamp_zone' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION timezone(text, nanotimestamptz) RETURNS nanotimestamp AS 'MODULE_PATHNAME', 'nanotimestamptz_zone' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- arithmetic
CREATE FUNCTION nanotimestamp_mi(nanotimestamp, nanotimestamp) RETURNS nanointerval AS 'MODULE_PATHNAME', 'nanotimestamptz_mi' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp_pl_nanointerval(nanotimestamp, nanointerval) RETURNS nanotimestamp AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp_mi_nanointerval(nanotimestamp, nanointerval) RETURNS nanotimestamp AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanointerval_pl_nanotimestamp(nanointerval, nanotimestamp) RETURNS nanotimestamp AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp_pl_interval(nanotimestamp, interval) RETURNS nanotimestamp AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION nanotimestamp_mi_interval(nanotimestamp, interval) RETURNS nanotimestamp AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION interval_pl_nanotimestamp(interval, nanotimestamp) RETURNS nanotimestamp AS 'MODULE_PATHNAME' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE OPERATOR - (LEFTARG = nanotimestamp, RIGHTARG = nanotimestamp, PROCEDURE = nanotimestamp_mi);
CREATE OPERATOR + (LEFTARG = nanotimestamp, RIGHTARG = nanointerval, PROCEDURE = nanotimestamp_pl_nanointerval, COMMUTATOR = +);
CREATE OPERATOR + (LEFTARG = nanointerval, RIGHTARG = nanotimestamp, PROCEDURE = nanointerval_pl_nanotimestamp, COMMUTATOR = +);
CREATE OPERATOR - (LEFTARG = nanotimestamp, RIGHTARG = nanointerval, PROCEDURE = nanotimestamp_mi_nanointerval);
CREATE OPERATOR + (LEFTARG = nanotimestamp, RIGHTARG = interval, PROCEDURE = nanotimestamp_pl_interval, COMMUTATOR = +);
CREATE OPERATOR + (LEFTARG = interval, RIGHTARG = nanotimestamp, PROCEDURE = interval_pl_nanotimestamp, COMMUTATOR = +);
CREATE OPERATOR - (LEFTARG = nanotimestamp, RIGHTARG = interval, PROCEDURE = nanotimestamp_mi_interval);

CREATE FUNCTION time_bucket_ns(nanointerval, nanotimestamp, nanotimestamp DEFAULT '1970-01-01 00:00:00')
  RETURNS nanotimestamp AS 'MODULE_PATHNAME', 'time_bucket_ns_notz' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION date_trunc(text, nanotimestamp) RETURNS nanotimestamp AS 'MODULE_PATHNAME', 'nanotimestamp_trunc' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;
CREATE FUNCTION extract_ns(text, nanotimestamp) RETURNS numeric AS 'MODULE_PATHNAME', 'nanotimestamp_extract' LANGUAGE C IMMUTABLE STRICT PARALLEL SAFE;

-- ============================ migration helpers ============================
-- Expression that converts column "col" of type src to type target.
--   timestamp9 : via its own binary bigint cast (ns since 1970 UTC); the
--                timestamp9 extension is only needed because the column exists.
--   bigint     : nanoseconds since 1970-01-01 UTC.
--   timestamptz/timestamp/date: exact (x 1000), session time zone where PG would use it.
CREATE FUNCTION nanotime_migration_expr(src regtype, target regtype, col name) RETURNS text
LANGUAGE plpgsql STABLE AS $$
DECLARE
  s text := format_type(src, NULL);
  t text := format_type(target, NULL);
  c text := quote_ident(col);
  base text;
  base_tz bool;  -- base expression is nanotimestamptz (true) or nanotimestamp (false)
BEGIN
  IF t NOT IN ('nanotimestamptz', 'nanotimestamptz8', 'nanotimestamp') THEN
    RAISE EXCEPTION 'target type must be nanotimestamptz, nanotimestamptz8 or nanotimestamp, not %', t;
  END IF;
  CASE
    WHEN s = 'timestamp9' THEN base := format('(%s)::bigint::nanotimestamptz', c); base_tz := true;
    WHEN s = 'bigint' THEN base := format('(%s)::nanotimestamptz', c); base_tz := true;
    WHEN s = 'timestamp with time zone' THEN base := format('(%s)::nanotimestamptz', c); base_tz := true;
    WHEN s IN ('timestamp without time zone', 'date') THEN base := format('(%s)::nanotimestamp', c); base_tz := false;
    WHEN s IN ('nanotimestamptz', 'nanotimestamptz8') THEN base := format('(%s)::nanotimestamptz', c); base_tz := true;
    WHEN s = 'nanotimestamp' THEN base := c; base_tz := false;
    ELSE RAISE EXCEPTION 'cannot migrate a column of type % with pg_nanotime', s;
  END CASE;
  IF s = 'bigint' AND t = 'nanotimestamptz8' THEN
    RETURN format('(%s)::nanotimestamptz8', c);   -- binary-compatible, no conversion
  ELSIF s = 'timestamp9' AND t = 'nanotimestamptz8' THEN
    RETURN format('(%s)::bigint::nanotimestamptz8', c);
  ELSIF base_tz AND t = 'nanotimestamp' THEN
    RETURN base || '::nanotimestamp';          -- session time zone, like timestamptz::timestamp
  ELSIF NOT base_tz AND t = 'nanotimestamptz' THEN
    RETURN base || '::nanotimestamptz';         -- session time zone, like timestamp::timestamptz
  ELSIF NOT base_tz AND t = 'nanotimestamptz8' THEN
    RETURN base || '::nanotimestamptz::nanotimestamptz8';  -- session time zone, like timestamp::timestamptz
  ELSIF t = 'nanotimestamptz' OR t = 'nanotimestamp' THEN
    RETURN base;
  ELSE
    RETURN base || '::' || t;
  END IF;
END $$;

-- Count values outside [lo, hi) after conversion. timestamp9 silently wrapped
-- out-of-range input around 1677/2262, so a corrupted value is just another
-- valid instant: this only finds implausible ones, it cannot prove a value is
-- correct. Pick lo/hi to match the data's real time span.
CREATE FUNCTION nanotime_suspect_count(tbl regclass, col name,
    lo nanotimestamptz DEFAULT '1990-01-01 00:00:00+00', hi nanotimestamptz DEFAULT '2100-01-01 00:00:00+00')
RETURNS bigint LANGUAGE plpgsql STABLE AS $$
DECLARE
  src regtype;
  n bigint;
BEGIN
  SELECT atttypid INTO src FROM pg_attribute WHERE attrelid = tbl AND attname = col AND NOT attisdropped;
  IF src IS NULL THEN RAISE EXCEPTION 'column "%" of relation % does not exist', col, tbl; END IF;
  EXECUTE format('SELECT count(*) FROM %s WHERE %s NOT BETWEEN $1 AND $2 - ''1 ns''::nanointerval',
                 tbl, nanotime_migration_expr(src, 'nanotimestamptz', col))
    INTO n USING lo, hi;
  RETURN n;
END $$;

-- Migrate one column in place with ALTER TABLE ... TYPE ... USING. PostgreSQL
-- rebuilds the column's indexes (B-tree, hash, BRIN, unique, primary key)
-- with the new type's default operator classes in the same statement. An
-- existing default is kept if PostgreSQL can cast it (assignment cast);
-- otherwise pass new_default, which replaces it. Views or rules
-- that use the column make the ALTER fail (PostgreSQL restriction).
CREATE PROCEDURE nanotime_migrate_column(tbl regclass, col name,
    target regtype DEFAULT 'nanotimestamptz', new_default text DEFAULT NULL, dry_run bool DEFAULT false)
LANGUAGE plpgsql AS $$
DECLARE
  src regtype;
  has_default bool;
  expr text;
  stmt text;
  idx record;
BEGIN
  SELECT atttypid, atthasdef INTO src, has_default FROM pg_attribute
   WHERE attrelid = tbl AND attname = col AND NOT attisdropped AND attnum > 0;
  IF src IS NULL THEN RAISE EXCEPTION 'column "%" of relation % does not exist', col, tbl; END IF;
  expr := nanotime_migration_expr(src, target, col);
  stmt := format('ALTER TABLE %s ALTER COLUMN %I TYPE %s USING %s', tbl, col, format_type(target, NULL), expr);
  IF new_default IS NOT NULL THEN
    stmt := format('ALTER TABLE %s ALTER COLUMN %I DROP DEFAULT, ', tbl, col) || substr(stmt, length(format('ALTER TABLE %s ', tbl)) + 1);
  END IF;
  IF new_default IS NOT NULL THEN
    stmt := stmt || format(', ALTER COLUMN %I SET DEFAULT %s', col, new_default);
  END IF;
  FOR idx IN SELECT i.indexrelid::regclass AS name FROM pg_index i
              WHERE i.indrelid = tbl AND (SELECT attnum FROM pg_attribute WHERE attrelid = tbl AND attname = col) = ANY (i.indkey::int2[])
  LOOP
    RAISE NOTICE 'index % will be rebuilt', idx.name;
  END LOOP;
  IF dry_run THEN
    RAISE NOTICE '%', stmt;
    RETURN;
  END IF;
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN datatype_mismatch OR undefined_function THEN
    IF has_default AND new_default IS NULL THEN
      RAISE EXCEPTION '%', SQLERRM
        USING ERRCODE = SQLSTATE, HINT = 'The column default cannot be converted; pass new_default => ''clock_ns()'' (or another expression, or ''NULL'').';
    END IF;
    RAISE;
  END;
END $$;
