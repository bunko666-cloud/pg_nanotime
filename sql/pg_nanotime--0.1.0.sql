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
