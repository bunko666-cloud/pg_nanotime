SET timezone = 'UTC';
-- timestamptz -> nanotimestamptz is exact
SELECT '2024-01-01 00:00:00.123456 UTC'::timestamptz::nanotimestamptz;
SELECT '1969-12-31 23:59:59.999999 UTC'::timestamptz::nanotimestamptz;
SELECT '4714-11-24 00:00:00 UTC BC'::timestamptz::nanotimestamptz;
SELECT 'infinity'::timestamptz::nanotimestamptz;
-- nanotimestamptz -> timestamptz rounds DOWN (floor), also before 1970
SELECT '2024-01-01 00:00:00.123456999 UTC'::nanotimestamptz::timestamptz;
SELECT '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz::timestamptz;
SELECT '1900-01-01 00:00:00.000000001 UTC'::nanotimestamptz::timestamptz;
SELECT '294276-12-31 23:59:59.999999999 UTC'::nanotimestamptz::timestamptz;
-- bigint (ns since 1970) both ways, explicit only
SELECT (-9223372036854775808)::bigint::nanotimestamptz, 9223372036854775807::bigint::nanotimestamptz;
SELECT (-1)::bigint::nanotimestamptz::bigint, 0::bigint::nanotimestamptz::bigint;
SELECT '1677-09-21 00:12:43.145224192 UTC'::nanotimestamptz::bigint AS int64_min, '2262-04-11 23:47:16.854775807 UTC'::nanotimestamptz::bigint AS int64_max;
SELECT '1677-09-21 00:12:43.145224191 UTC'::nanotimestamptz::bigint;
SELECT '2262-04-11 23:47:16.854775808 UTC'::nanotimestamptz::bigint;
SELECT castcontext FROM pg_cast WHERE castsource = 'bigint'::regtype AND casttarget = 'nanotimestamptz'::regtype;
CREATE TEMP TABLE c(t nanotimestamptz);
INSERT INTO c VALUES (5::bigint);
