SET timezone = 'UTC';
SELECT typlen, typcategory FROM pg_type WHERE typname = 'nanointerval';
-- text input: own format, PostgreSQL-style units, ISO 8601
SELECT '1 day 02:03:04.123456789'::nanointerval, '-1 day -02:00:00'::nanointerval, '00:00:00.000000001'::nanointerval;
SELECT '1.5 hours 3 ns'::nanointerval, '2 weeks ago'::nanointerval, '@ 1 minute 30 seconds'::nanointerval, '90'::nanointerval;
SELECT '1 us 1 ms'::nanointerval, '1.000000001 s'::nanointerval, '-00:00:00.5'::nanointerval;
SELECT 'PT1H2M3.000000004S'::nanointerval, 'P1W2DT3H'::nanointerval, 'P-1D'::nanointerval;
-- errors: months/years, sub-ns precision, garbage, overflow
SELECT '1 month'::nanointerval;
SELECT '1 year 2 days'::nanointerval;
SELECT 'P1Y'::nanointerval;
SELECT 'P1M'::nanointerval;
SELECT '0.5 ns'::nanointerval;
SELECT '1.0000000001 s'::nanointerval;
SELECT 'abc'::nanointerval;
SELECT '1 fortnight'::nanointerval;
SELECT '01:60:00'::nanointerval;
SELECT '200000000000000000000000 ns'::nanointerval;
-- range: exactly max(nanotimestamptz) - min(nanotimestamptz)
SELECT '294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz - '4714-11-24 00:00:00 UTC BC'::nanotimestamptz AS max_span;
SELECT '4714-11-24 00:00:00 UTC BC'::nanotimestamptz - '294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz AS min_span;
SELECT ('294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz - '4714-11-24 00:00:00 UTC BC'::nanotimestamptz) + '1 ns'::nanointerval;
-- output round trip
SELECT v::text::nanointerval = v FROM (VALUES ('1 day 02:03:04.123456789'::nanointerval), ('-3 days -00:00:00.000000001'), ('-00:00:00.5'), ('0'), ('5 days')) t(v);
-- comparisons, aggregates, index
SELECT '1 day'::nanointerval = '24 hours'::nanointerval, '1 ns'::nanointerval > '0'::nanointerval, '-1 ns'::nanointerval < '0'::nanointerval;
SELECT min(v), max(v) FROM (VALUES ('1 s'::nanointerval), ('-1 ns'), ('1 day')) t(v);
CREATE TEMP TABLE iv(v nanointerval);
INSERT INTO iv SELECT (g::bigint * 1000003)::nanointerval FROM generate_series(-5000, 5000) g;
CREATE INDEX ON iv(v);
CREATE INDEX iv_h ON iv USING hash(v);
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT * FROM iv WHERE v < '-4 ms';
SELECT count(*) FROM iv WHERE v < '-4 ms';
SELECT count(*) FROM iv WHERE v = '1000003 ns';
RESET enable_seqscan;
-- arithmetic
SELECT -'1 ns'::nanointerval, '1 s'::nanointerval + '1 ns', '1 s'::nanointerval - '2 s';
SELECT '1 hour'::nanointerval * 3, 3 * '1 s'::nanointerval, '1 s'::nanointerval * 2::bigint, '1 hour'::nanointerval * 1.5, 0.5 * '3 ns'::nanointerval;
SELECT '1 hour'::nanointerval / 7, '10 ns'::nanointerval / 4, '-10 ns'::nanointerval / 4, '1 s'::nanointerval / 3.0;
SELECT '1 s'::nanointerval / 0;
SELECT '1 s'::nanointerval / 0.0;
SELECT ('294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz - '4714-11-24 00:00:00 UTC BC'::nanotimestamptz) * 2;
SELECT ('294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz - '4714-11-24 00:00:00 UTC BC'::nanotimestamptz) * 9223372036854775807;
-- casts with interval
SELECT interval '1 day 02:03:04.123456'::nanointerval, interval '-36 hours'::nanointerval;
SELECT interval '1 month'::nanointerval;
SELECT interval 'infinity'::nanointerval;
SELECT '1 day 00:00:00.000001999'::nanointerval::interval, '-00:00:00.000000001'::nanointerval::interval;
SELECT ('294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz - '4714-11-24 00:00:00 UTC BC'::nanotimestamptz)::interval;
-- casts with bigint (explicit only)
SELECT 1000::bigint::nanointerval, '1 s'::nanointerval::bigint, (-9223372036854775808)::bigint::nanointerval::bigint;
SELECT '300 years'::nanointerval;
SELECT ('1 day'::nanointerval * 200000)::bigint;
SELECT nanointerval_ns('1 day 00:00:00.000000001'), nanointerval_from_ns(1.5), nanointerval_from_ns(-1.5);
-- binary
SELECT nanointerval_send('-1 ns');
