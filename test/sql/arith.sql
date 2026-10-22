SET timezone = 'UTC';
-- ts - ts (both types), pre-1970 and across the epoch
SELECT '2024-01-01 00:00:00.000000001 UTC'::nanotimestamptz - '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz;
SELECT '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz - '1970-01-01 UTC'::nanotimestamptz;
SELECT '2262-04-11 23:47:16.854775807 UTC'::nanotimestamptz8 - '1677-09-21 00:12:43.145224192 UTC'::nanotimestamptz8 AS full8;
SELECT ('2262-04-11 23:47:16.854775807 UTC'::nanotimestamptz8 - '1677-09-21 00:12:43.145224192 UTC'::nanotimestamptz8)::bigint;
-- ts +/- nanointerval
SELECT '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz + '1 ns'::nanointerval, '1970-01-01 UTC'::nanotimestamptz - '1 ns'::nanointerval, '1 ns'::nanointerval + '2024-01-01 UTC'::nanotimestamptz;
SELECT '294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz + '1 ns'::nanointerval;
SELECT '4714-11-24 00:00:00 UTC BC'::nanotimestamptz - '1 ns'::nanointerval;
SELECT '2024-01-01 UTC'::nanotimestamptz8 + '1.000000001 s'::nanointerval, '1 ns'::nanointerval + '2024-01-01 UTC'::nanotimestamptz8;
SELECT '2262-04-11 23:47:16.854775807 UTC'::nanotimestamptz8 + '1 ns'::nanointerval;
SELECT '1677-09-21 00:12:43.145224192 UTC'::nanotimestamptz8 - '1 ns'::nanointerval;
SELECT pg_typeof('2024-01-01 UTC'::nanotimestamptz8 + '1 ns'::nanointerval);
-- ts +/- interval: calendar semantics in the session time zone, sub-us digits kept
SELECT '2024-01-31 12:00:00.000000005 UTC'::nanotimestamptz + interval '1 month', '2024-03-31 UTC'::nanotimestamptz - interval '1 month';
SELECT '2023-02-28 00:00:00.123456789 UTC'::nanotimestamptz8 + interval '1 year 1 day 1 hour';
SET timezone = 'Europe/Amsterdam';
-- DST: +1 day keeps wall clock, +24 hours does not (same as timestamptz)
SELECT '2024-03-30 12:00:00.000000001'::nanotimestamptz + interval '1 day' AS plus_1day,
       '2024-03-30 12:00:00.000000001'::nanotimestamptz + interval '24 hours' AS plus_24h,
       '2024-03-30 12:00:00.000000001'::nanotimestamptz + '1 day'::nanointerval AS plus_fixed_day;
SELECT ('2024-03-30 12:00:00'::timestamptz + interval '1 day')::nanotimestamptz = '2024-03-30 12:00:00'::nanotimestamptz + interval '1 day' AS same_as_timestamptz;
SET timezone = 'UTC';
-- untyped literal resolves to interval (calendar), typed nanointerval keeps ns
SELECT '2024-01-01 UTC'::nanotimestamptz + '1 month', '2024-01-01 UTC'::nanotimestamptz + '0.000000001 s'::nanointerval;
SELECT '294276-12-01 UTC'::nanotimestamptz + interval '1 month';
SELECT '2262-04-01 UTC'::nanotimestamptz8 + interval '1 month';
SELECT '2024-01-01 UTC'::nanotimestamptz + interval 'infinity';
-- ts - untyped literal is ts - ts
SELECT '2024-01-02 UTC'::nanotimestamptz - '2024-01-01';
