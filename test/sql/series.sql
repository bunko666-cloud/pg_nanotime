-- abs(nanointerval), nanointerval_from_ns(double precision / NaN), generate_series
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pg_nanotime;
RESET client_min_messages;
SET timezone = 'UTC';
-- abs
SELECT abs('-1.5 s'::nanointerval), abs('2 ns'::nanointerval), abs('0'::nanointerval);
-- the range is symmetric, so even the most negative value can be negated
SELECT abs(lo - hi) = hi - lo AS sym, -(lo - hi) = hi - lo AS neg
  FROM (SELECT '4714-11-24 00:00:00+00 BC'::nanotimestamptz AS lo, '294276-12-31 23:59:59.999999999+00'::nanotimestamptz AS hi) b;
SELECT (lo - hi) - '1 ns'::nanointerval FROM (SELECT '4714-11-24 00:00:00+00 BC'::nanotimestamptz AS lo, '294276-12-31 23:59:59.999999999+00'::nanotimestamptz AS hi) b;
SELECT abs(x) = greatest(x, -x) AS same FROM (VALUES ('-7 ns'::nanointerval), ('7 ns')) v(x);
-- nanointerval_from_ns(double precision)
SELECT nanointerval_from_ns(1500.0::float8), nanointerval_from_ns(2.5::float8), nanointerval_from_ns(-2.5::float8), nanointerval_from_ns(1.5e9::float8);
SELECT pg_typeof(nanointerval_from_ns(random() * 0 + 1));
SELECT nanointerval_from_ns(1e300::float8);
SELECT nanointerval_from_ns('NaN'::float8);
SELECT nanointerval_from_ns('Infinity'::float8);
SELECT nanointerval_from_ns('-Infinity'::float8);
-- beyond 2^53 a double cannot hold every integer
SELECT nanointerval_from_ns(9007199254740993::float8)::bigint AS f8,
       nanointerval_from_ns(9007199254740993::bigint)::bigint AS int8,
       nanointerval_from_ns(9007199254740993::numeric)::bigint AS num,
       pg_typeof(9007199254740993) AS literal_type;
-- a bigint literal resolves to the exact bigint overload, not float8
SELECT nanointerval_from_ns(9007199254740993)::bigint AS literal;
-- numeric NaN / infinity
SELECT nanointerval_from_ns('NaN'::numeric);
SELECT nanointerval_from_ns('Infinity'::numeric);
SELECT nanointerval_from_ns('-Infinity'::numeric);
-- generate_series: three timestamp types
SELECT * FROM generate_series('2026-10-23 07:00:00+00'::nanotimestamptz, '2026-10-23 07:00:00.000000003+00', '1 ns'::nanointerval);
SELECT * FROM generate_series('2026-10-23 07:00+00'::nanotimestamptz8, '2026-10-23 07:03+00', '1 min'::nanointerval);
SELECT * FROM generate_series('2026-10-23 07:00'::nanotimestamp, '2026-10-23 07:00:01', '400 ms'::nanointerval);
-- negative step counts down; wrong direction is empty; stop is inclusive
SELECT * FROM generate_series('2026-10-23 07:00:01+00'::nanotimestamptz, '2026-10-23 07:00:00+00', '-500 ms'::nanointerval);
SELECT count(*) FROM generate_series('2026-10-23 07:00:01+00'::nanotimestamptz, '2026-10-23 07:00:00+00', '1 s'::nanointerval);
SELECT count(*) FROM generate_series('2026-10-23 07:00+00'::nanotimestamptz, '2026-10-23 07:00+00', '1 s'::nanointerval);
-- step zero
SELECT * FROM generate_series('2026-10-23 07:00+00'::nanotimestamptz, '2026-10-23 08:00+00', '0'::nanointerval);
-- range edges: no wrap, no error
SELECT * FROM generate_series('2262-04-11 23:47:16.854775805+00'::nanotimestamptz8, '2262-04-11 23:47:16.854775807+00', '1 ns'::nanointerval);
SELECT * FROM generate_series('2262-04-11 23:47:16.854775806+00'::nanotimestamptz8, '2262-04-11 23:47:16.854775807+00', '1 day'::nanointerval);
SELECT * FROM generate_series('1677-09-21 00:12:43.145224193+00'::nanotimestamptz8, '1677-09-21 00:12:43.145224192+00', '-1 ns'::nanointerval);
SELECT count(*) FROM generate_series('1677-09-21 00:12:43.145224192+00'::nanotimestamptz8, '2262-04-11 23:47:16.854775807+00', '100000 days'::nanointerval);
-- NULL argument
SELECT count(*) FROM generate_series(NULL::nanotimestamptz, '2026-10-23 08:00+00', '1 s'::nanointerval);
-- planner row estimate from the support function
CREATE FUNCTION series_est(q text) RETURNS int LANGUAGE plpgsql AS $$
DECLARE j json; BEGIN EXECUTE 'EXPLAIN (FORMAT JSON) ' || q INTO j; RETURN (j -> 0 -> 'Plan' ->> 'Plan Rows')::int; END $$;
SELECT series_est($q$SELECT * FROM generate_series('2026-10-23 07:00+00'::nanotimestamptz, '2026-10-23 08:00+00', '1 min'::nanointerval)$q$) AS rows_tz,
       series_est($q$SELECT * FROM generate_series('2026-10-23 07:00+00'::nanotimestamptz8, '2026-10-23 07:00:01+00', '1 ms'::nanointerval)$q$) AS rows_tz8,
       series_est($q$SELECT * FROM generate_series('2026-10-23 08:00'::nanotimestamp, '2026-10-23 07:00', '-1 s'::nanointerval)$q$) AS rows_notz,
       series_est($q$SELECT * FROM generate_series('2026-10-23 08:00'::nanotimestamp, '2026-10-23 07:00', '1 s'::nanointerval)$q$) AS rows_empty;
DROP FUNCTION series_est(text);
-- gap detection with a LEFT JOIN against the expected grid
CREATE TABLE series_hr (ts nanotimestamptz8);
INSERT INTO series_hr SELECT g FROM generate_series('2026-10-23 07:00+00'::nanotimestamptz8, '2026-10-23 07:00:09+00', '1 s'::nanointerval) g
  WHERE g NOT IN ('2026-10-23 07:00:03+00', '2026-10-23 07:00:04+00');
SELECT g AS missing FROM generate_series('2026-10-23 07:00+00'::nanotimestamptz8, '2026-10-23 07:00:09+00', '1 s'::nanointerval) g
  LEFT JOIN series_hr h ON h.ts = g WHERE h.ts IS NULL ORDER BY g;
DROP TABLE series_hr;
RESET timezone;
