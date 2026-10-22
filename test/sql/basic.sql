CREATE EXTENSION pg_nanotime;
SET timezone = 'UTC';
-- storage
SELECT typlen, typbyval, typalign FROM pg_type WHERE typname = 'nanotimestamptz';
-- range boundaries (same as timestamptz)
-- note: PostgreSQL documents "4713 BC" (Julian); in proleptic Gregorian output that is 4714-11-24 BC
SELECT '4714-11-24 00:00:00 UTC BC'::nanotimestamptz AS min_value, '4714-11-24 00:00:00 UTC BC'::timestamptz::text AS pg_min;
SELECT '294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz AS max_value;
SELECT '4714-11-23 23:59:59.999999999 UTC BC'::nanotimestamptz;
SELECT '294277-01-01 00:00:00 UTC'::nanotimestamptz;
-- beyond timestamp9 / int64-ns limits: fine here
SELECT '1677-09-21 00:12:43.145224191 UTC'::nanotimestamptz AS before_int64_min;
SELECT '2262-04-11 23:47:16.854775808 UTC'::nanotimestamptz AS after_int64_max;
SELECT '0001-01-01 00:00:00 UTC'::nanotimestamptz, '9999-12-31 23:59:59.999999999 UTC'::nanotimestamptz;
-- pre-1970 and the epoch
SELECT '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz AS minus_1ns;
SELECT '1970-01-01 00:00:00 UTC'::nanotimestamptz AS epoch;
SELECT '1900-01-01 00:00:00.000000001 UTC'::nanotimestamptz;
-- comparison
SELECT '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz < '1970-01-01 UTC'::nanotimestamptz AS lt,
       '2024-01-01 00:00:00.000000001 UTC'::nanotimestamptz > '2024-01-01 UTC'::nanotimestamptz AS gt,
       '2024-01-01 00:00:00.1 UTC'::nanotimestamptz = '2024-01-01 00:00:00.100000000 UTC'::nanotimestamptz AS eq,
       '2024-01-01 UTC'::nanotimestamptz <> '2024-01-01 00:00:00.000000001 UTC'::nanotimestamptz AS ne;
SELECT min(t), max(t) FROM (VALUES ('1960-01-01 00:00:00.5 UTC'::nanotimestamptz), ('2024-01-01 UTC'), ('1969-12-31 23:59:59.999999999 UTC')) v(t);
SELECT greatest('1960-01-01 UTC'::nanotimestamptz, '1959-12-31 23:59:59.999999999 UTC'), least('1960-01-01 UTC'::nanotimestamptz, '1959-12-31 23:59:59.999999999 UTC');
