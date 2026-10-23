-- Gaps listed in docs/COVERAGE.md section 9 (operators/aggregates not
-- exercised elsewhere).
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pg_nanotime;
RESET client_min_messages;
SET TimeZone = 'Asia/Taipei';
SET extra_float_digits = 0;

-- interval + ts (commutator of ts + interval)
SELECT interval '1 day 2 hours' + '2026-03-01 00:00:00.123456789+08'::nanotimestamptz AS tz16;
SELECT interval '1 day 2 hours' + '2026-03-01 00:00:00.123456789+08'::nanotimestamptz
     = '2026-03-01 00:00:00.123456789+08'::nanotimestamptz + interval '1 day 2 hours' AS tz16_commutes;
SELECT interval '1 month' + '2026-01-31 12:00:00.000000001+08'::nanotimestamptz8 AS tz8;
SELECT interval '1 day' + '2026-03-01 00:00:00.5+08'::nanotimestamptz8
     = '2026-03-01 00:00:00.5+08'::nanotimestamptz8 + interval '1 day' AS tz8_commutes;
SELECT pg_typeof(interval '1 day' + '2026-03-01'::nanotimestamptz8) AS tz8_type;

-- nanotimestamptz8 - interval
SELECT '2026-03-01 00:00:00.000000007+08'::nanotimestamptz8 - interval '1 month' AS tz8_minus_month;
SELECT '2026-03-01 00:00:00.000000007+08'::nanotimestamptz8 - interval '1.5 seconds' AS tz8_minus_sec;
SELECT pg_typeof('2026-03-01'::nanotimestamptz8 - interval '1 day') AS tz8_minus_type;
SELECT ('2026-03-01'::nanotimestamptz8 - interval '-1 day') = ('2026-03-01'::nanotimestamptz8 + interval '1 day') AS neg_ok;
-- out of range for the 8 B type
SELECT '1677-09-22 00:00:00+00'::nanotimestamptz8 - interval '2 days';

-- bigint * nanointerval
SELECT 3::bigint * '1.000000001 s'::nanointerval AS bigint_mul;
SELECT (3::bigint * '1.000000001 s'::nanointerval) = ('1.000000001 s'::nanointerval * 3::bigint) AS mul_commutes;
SELECT (-2)::bigint * '5 ns'::nanointerval AS bigint_mul_neg;
SELECT 9223372036854775807::bigint * '2 s'::nanointerval;

-- nanointerval / bigint (direct, not through int4)
SELECT '10 ns'::nanointerval / 3::bigint AS div3;
SELECT '11 ns'::nanointerval / 2::bigint AS div_round_up;
SELECT '-11 ns'::nanointerval / 2::bigint AS div_round_away;
SELECT '1 s'::nanointerval / 4000000000::bigint AS div_big;
SELECT '1 s'::nanointerval / 0::bigint;

-- <> on the remaining types
SELECT '2026-03-01 00:00:00.000000001+08'::nanotimestamptz8 <> '2026-03-01 00:00:00.000000002+08'::nanotimestamptz8 AS tz8_ne,
       '2026-03-01 00:00:00.000000001+08'::nanotimestamptz8 <> '2026-03-01 00:00:00.000000001+08'::nanotimestamptz8 AS tz8_ne_same;
SELECT '2026-03-01 00:00:00.000000001'::nanotimestamp <> '2026-03-01 00:00:00.000000002'::nanotimestamp AS notz_ne,
       '2026-03-01 00:00:00.000000001'::nanotimestamp <> '2026-03-01 00:00:00.000000001'::nanotimestamp AS notz_ne_same;
SELECT '1 ns'::nanointerval <> '2 ns'::nanointerval AS ni_ne,
       '1 s'::nanointerval <> '1000000000 ns'::nanointerval AS ni_ne_same;
SELECT count(*) FILTER (WHERE a <> b) AS ne, count(*) FILTER (WHERE NOT a = b) AS not_eq
FROM (VALUES ('1 ns'::nanointerval, '1 ns'::nanointerval), ('1 ns', '2 ns'), ('-1 ns', '1 ns')) v(a, b);

-- percentile_disc directly on nanointerval
CREATE TEMP TABLE lat (d nanointerval);
INSERT INTO lat SELECT nanointerval_from_ns(g * 1000 + 7) FROM generate_series(1, 100) g;
INSERT INTO lat VALUES (NULL);
SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY d) AS p50,
       percentile_disc(0.99) WITHIN GROUP (ORDER BY d) AS p99,
       percentile_disc(ARRAY[0, 0.9, 1]) WITHIN GROUP (ORDER BY d) AS ps
FROM lat;
SELECT pg_typeof(percentile_disc(0.5) WITHIN GROUP (ORDER BY d)) FROM lat;
SELECT percentile_disc(0.5) WITHIN GROUP (ORDER BY d)::bigint
     = percentile_disc(0.5) WITHIN GROUP (ORDER BY d::bigint) AS matches_bigint
FROM lat;
-- percentile_cont needs interpolation: not supported
SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY d) FROM lat;
DROP TABLE lat;
