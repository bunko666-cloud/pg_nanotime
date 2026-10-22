SET timezone = 'Asia/Taipei';
SELECT typlen, typbyval FROM pg_type WHERE typname = 'nanotimestamp';
-- text I/O ignores any zone, like timestamp
SELECT '2024-03-10 02:30:00.123456789+05'::nanotimestamp, '2024-01-01T12:00:00.000000001Z'::nanotimestamp, '1969-12-31 23:59:59.999999999'::nanotimestamp;
SELECT '4714-11-24 00:00:00 BC'::nanotimestamp AS min, '294276-12-31 23:59:59.999999999'::nanotimestamp AS max;
SELECT '294277-01-01'::nanotimestamp;
SELECT 'infinity'::nanotimestamp;
SELECT '2024-01-01 00:00:00.1234567891'::nanotimestamp;
SELECT v::text::nanotimestamp = v FROM (VALUES ('2024-01-01 00:00:00.000000001'::nanotimestamp), ('1900-06-15 12:34:56.987654321'), ('0044-03-15 00:00:00 BC')) t(v);
SET timezone = 'America/New_York';
SELECT '2024-03-10 02:30:00.5'::nanotimestamp;  -- nonexistent local time is fine without a zone
SET timezone = 'Asia/Taipei';
-- binary round trip
SELECT nanotimestamp_send('1969-12-31 23:59:59.999999999');
-- comparisons, aggregates, B-tree, hash, BRIN
SELECT '2024-01-01'::nanotimestamp < '2024-01-01 00:00:00.000000001'::nanotimestamp, '2024-01-01'::nanotimestamp = '2024-01-01'::nanotimestamp;
CREATE TEMP TABLE l(t nanotimestamp);
INSERT INTO l SELECT '1969-12-31 23:59:00'::nanotimestamp + (g::bigint * 1000000007)::nanointerval FROM generate_series(0, 9999) g;
SELECT min(t), max(t), count(DISTINCT t) FROM l;
CREATE INDEX l_b ON l(t);
CREATE INDEX l_h ON l USING hash(t);
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT count(*) FROM l WHERE t < '1970-01-01';
SELECT count(*) FROM l WHERE t < '1970-01-01';
EXPLAIN (COSTS OFF) SELECT count(*) FROM l WHERE t = '1969-12-31 23:59:01.000000007';
SELECT count(*) FROM l WHERE t = '1969-12-31 23:59:01.000000007';
DROP INDEX l_b; DROP INDEX l_h;
CREATE INDEX l_brin ON l USING brin(t);
EXPLAIN (COSTS OFF) SELECT count(*) FROM l WHERE t < '1970-01-01';
SELECT count(*) FROM l WHERE t < '1970-01-01';
RESET enable_seqscan;
-- casts: timestamp (floor), date, nanotimestamptz via session zone, bigint (explicit)
SELECT '1969-12-31 23:59:59.999999999'::nanotimestamp::timestamp, timestamp '2024-01-01 00:00:00.5'::nanotimestamp;
SELECT '1969-12-31 23:59:59.999999999'::nanotimestamp::date, '0001-01-01 BC'::date::nanotimestamp, '2024-02-29'::date::nanotimestamp;
SELECT '2024-01-01 12:00:00.123456789'::nanotimestamp::nanotimestamptz, '2024-01-01 12:00:00.123456789+00'::nanotimestamptz::nanotimestamp;
SELECT ('2024-01-01 12:00:00.123456789'::nanotimestamp::timestamp::timestamptz)::nanotimestamptz = date_trunc('microsecond', '2024-01-01 12:00:00.123456789'::nanotimestamp::nanotimestamptz) AS matches_core;
SET timezone = 'Europe/Amsterdam';
SELECT '2024-03-31 02:30:00.000000001'::nanotimestamp::nanotimestamptz AS gap, '2024-10-27 02:30:00.000000001'::nanotimestamp::nanotimestamptz AS overlap;
SELECT timestamp '2024-03-31 02:30:00'::timestamptz AS core_gap, timestamp '2024-10-27 02:30:00'::timestamptz AS core_overlap;
SET timezone = 'Asia/Taipei';
SELECT '2024-01-01'::date::nanotimestamptz, '2024-01-01 23:59:59.999999999+08'::nanotimestamptz::date, '2024-01-01 23:59:59.999999999+00'::nanotimestamptz::date;
SELECT (-1)::bigint::nanotimestamp, '1970-01-01 00:00:00.000000001'::nanotimestamp::bigint, (-9223372036854775808)::bigint::nanotimestamp;
SELECT '2262-04-11 23:47:16.854775808'::nanotimestamp::bigint;
SELECT castcontext, castsource::regtype, casttarget::regtype FROM pg_cast
 WHERE castsource = 'nanotimestamp'::regtype OR casttarget = 'nanotimestamp'::regtype ORDER BY 2::text, 3::text;
-- AT TIME ZONE equivalents
SELECT timezone('UTC', '2024-01-01 12:00:00.000000001'::nanotimestamp), timezone('America/New_York', '2024-01-01 12:00:00.000000001+00'::nanotimestamptz);
SELECT timezone('-05:00', '2024-06-01 00:00:00.5'::nanotimestamp)::text = (timestamp '2024-06-01 00:00:00.5' AT TIME ZONE '-05:00')::nanotimestamptz::text AS same_as_core;
SELECT '2024-01-01'::nanotimestamp AT TIME ZONE 'UTC';
-- arithmetic
SELECT '2024-01-02'::nanotimestamp - '2024-01-01 00:00:00.000000001'::nanotimestamp, '1969-12-31 23:59:59.999999999'::nanotimestamp - '1970-01-01'::nanotimestamp;
SELECT '2024-01-01'::nanotimestamp + '1 ns'::nanointerval, '1 ns'::nanointerval + '2024-01-01'::nanotimestamp, '2024-01-01'::nanotimestamp - '1 ns'::nanointerval;
SELECT '2024-01-31 00:00:00.000000005'::nanotimestamp + interval '1 month', interval '1 day' + '2024-02-28 23:00:00.000000001'::nanotimestamp, '2024-03-31'::nanotimestamp - interval '1 month';
SET timezone = 'Europe/Amsterdam';
SELECT '2024-03-30 12:00:00.000000001'::nanotimestamp + interval '24 hours' AS no_dst_effect;
SET timezone = 'Asia/Taipei';
SELECT '2024-01-01'::nanotimestamp + '1 day', pg_typeof('2024-01-01'::nanotimestamp + '1 day'), '2024-01-02'::nanotimestamp - '2024-01-01';
SELECT '294276-12-31 23:59:59.999999999'::nanotimestamp + '1 ns'::nanointerval;
SELECT '4714-11-24 00:00:00 BC'::nanotimestamp - '1 ns'::nanointerval;
SELECT '294276-12-01'::nanotimestamp + interval '1 month';
-- bucket, trunc, extract
SELECT time_bucket_ns('1 hour', '1969-12-31 23:30:00.1'::nanotimestamp), time_bucket_ns('15 min', '2024-01-01 10:14:59.999999999'::nanotimestamp), time_bucket_ns('1 day', '2024-01-01 05:00'::nanotimestamp, '2000-01-01 06:00');
SELECT time_bucket_ns('7 days', '4714-11-24 00:00:00 BC'::nanotimestamp) AS clamped, pg_typeof(time_bucket_ns('1 s', '2024-01-01'::nanotimestamp));
SELECT date_trunc('day', '2024-06-15 23:59:59.999999999'::nanotimestamp), date_trunc('microsecond', '2024-06-15 00:00:00.123456789'::nanotimestamp), date_trunc('nanosecond', '2024-06-15 00:00:00.123456789'::nanotimestamp);
SELECT extract_ns('epoch', '1970-01-01 00:00:01.000000001'::nanotimestamp), extract_ns('epoch', '1969-12-31 23:59:59.999999999'::nanotimestamp), extract_ns('nanosecond', '2024-01-01 00:00:05.000000007'::nanotimestamp), extract_ns('hour', '2024-01-01 05:00'::nanotimestamp);
SELECT extract_ns('timezone', '2024-01-01'::nanotimestamp);
