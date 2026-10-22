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
