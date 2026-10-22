SET timezone = 'UTC';
-- floor semantics including pre-1970
SELECT time_bucket_ns('1 s', '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz), time_bucket_ns('1 s', '1970-01-01 00:00:00.000000001 UTC'::nanotimestamptz);
SELECT time_bucket_ns('15 min', '2024-01-01 10:14:59.999999999 UTC'::nanotimestamptz), time_bucket_ns('15 min', '2024-01-01 10:15:00 UTC'::nanotimestamptz);
SELECT time_bucket_ns('1 day', '1900-06-15 12:00:00.5 UTC'::nanotimestamptz8), time_bucket_ns('100 ns', '1969-12-31 23:59:59.99999995 UTC'::nanotimestamptz8);
SELECT pg_typeof(time_bucket_ns('1 day', '2024-01-01'::nanotimestamptz8));
-- origin
SELECT time_bucket_ns('1 day', '2024-01-01 05:00 UTC'::nanotimestamptz, '2000-01-01 06:00 UTC'), time_bucket_ns('7 days', '2024-01-10 UTC'::nanotimestamptz, '2000-01-03 UTC');
SELECT time_bucket_ns('1 hour', '2024-01-01 05:30 UTC'::nanotimestamptz8, '2030-01-01 00:10 UTC');
-- range limits: bucket start before the minimum is clamped to the minimum
SELECT time_bucket_ns('1 day', '1677-09-21 00:12:43.145224192 UTC'::nanotimestamptz8) AS clamped8;
SELECT time_bucket_ns('1 day', '1677-09-21 12:00 UTC'::nanotimestamptz8) AS clamped8b, time_bucket_ns('1 day', '1677-09-22 12:00 UTC'::nanotimestamptz8) AS normal8;
SELECT time_bucket_ns('1 day', '2262-04-11 23:47:16.854775807 UTC'::nanotimestamptz8) AS top8;
SELECT time_bucket_ns('7 days', '4714-11-24 00:00:00 UTC BC'::nanotimestamptz) AS clamped16, time_bucket_ns('1 day', '294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz) AS top16;
SELECT time_bucket_ns('100000 years'::nanointerval, '2024-01-01'::nanotimestamptz);
SELECT time_bucket_ns('0', '2024-01-01'::nanotimestamptz);
SELECT time_bucket_ns('-1 s', '2024-01-01'::nanotimestamptz);
-- grouping
SELECT time_bucket_ns('1 s', t) b, count(*) FROM (SELECT ('1969-12-31 23:59:58 UTC'::nanotimestamptz + (g::bigint * 250000000)::nanointerval) t FROM generate_series(0, 11) g) s GROUP BY 1 ORDER BY 1;
-- date_trunc
SELECT date_trunc('second', '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz), date_trunc('microsecond', '2024-01-01 00:00:00.123456789 UTC'::nanotimestamptz), date_trunc('nanosecond', '2024-01-01 00:00:00.123456789 UTC'::nanotimestamptz);
SELECT date_trunc('day', '2024-06-15 23:30:00.000000001 UTC'::nanotimestamptz8), date_trunc('month', '2024-06-15 UTC'::nanotimestamptz8), pg_typeof(date_trunc('day', '2024-06-15'::nanotimestamptz8));
SET timezone = 'Asia/Taipei';
SELECT date_trunc('day', '2024-06-15 20:00:00.5 UTC'::nanotimestamptz), date_trunc('day', '2024-06-15 20:00:00.5 UTC'::nanotimestamptz, 'UTC');
SET timezone = 'UTC';
SELECT date_trunc('fortnight', '2024-01-01'::nanotimestamptz);
-- extract_ns
SELECT extract_ns('epoch', '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz), extract_ns('epoch', '2024-01-01 00:00:00.000000001 UTC'::nanotimestamptz8);
SELECT extract_ns('nanosecond', '2024-01-01 00:00:12.345678901 UTC'::nanotimestamptz), extract_ns('microsecond', '2024-01-01 00:00:12.345678901 UTC'::nanotimestamptz),
       extract_ns('millisecond', '2024-01-01 00:00:12.345678901 UTC'::nanotimestamptz), extract_ns('second', '2024-01-01 00:00:12.345678901 UTC'::nanotimestamptz);
SELECT extract_ns('year', '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz), extract_ns('hour', '2024-01-01 05:00 UTC'::nanotimestamptz), extract_ns('dow', '2024-01-01'::nanotimestamptz);
SELECT extract_ns('epoch', '4714-11-24 00:00:00 UTC BC'::nanotimestamptz);
SELECT extract_ns('epoch', '-1 day -00:00:00.000000001'::nanointerval), extract_ns('day', '-1 day -02:03:04.5'::nanointerval), extract_ns('hour', '-1 day -02:03:04.5'::nanointerval),
       extract_ns('nanosecond', '00:01:02.000000003'::nanointerval), extract_ns('second', '-00:00:04.5'::nanointerval);
SELECT extract_ns('month', '1 day'::nanointerval);
