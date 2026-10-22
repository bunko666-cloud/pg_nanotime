SET timezone = 'UTC';
-- fractional digits: 1..9 digits, trailing zeros beyond 9 allowed, nonzero 10th digit rejected
SELECT '2024-01-01 00:00:00.1 UTC'::nanotimestamptz, '2024-01-01 00:00:00.123456789 UTC'::nanotimestamptz;
SELECT '2024-01-01 00:00:00.1234567890 UTC'::nanotimestamptz;
SELECT '2024-01-01 00:00:00.1234567891 UTC'::nanotimestamptz;
-- ISO 8601 forms
SELECT '2024-06-30T12:00:00.000000001Z'::nanotimestamptz, '2024-06-30T12:00:00.5+05:30'::nanotimestamptz;
SELECT 'garbage'::nanotimestamptz;
SELECT 'infinity'::nanotimestamptz;
-- output follows the session time zone, like timestamptz
SET timezone = 'Asia/Taipei';
SELECT '2024-01-01 00:00:00.123456789 UTC'::nanotimestamptz;
SELECT '2024-01-01 00:00:00.123456789'::nanotimestamptz;
SET timezone = 'America/New_York';
SELECT '2024-07-01 12:00:00.000000001 UTC'::nanotimestamptz, '2024-07-01 12:00:00 UTC'::timestamptz;
SET timezone = 'Asia/Kolkata';
SELECT '2024-01-01 00:00:00.000000001 UTC'::nanotimestamptz, '2024-01-01 00:00:00 UTC'::timestamptz;
-- output equals timestamptz output when there are no sub-microsecond digits
SET timezone = 'Europe/Amsterdam';
SET DateStyle = 'ISO, YMD';
SELECT x::text = regexp_replace(x::timestamptz::text, '^(.* \d\d:\d\d:\d\d)([+-])', '\1.000000000\2')
  FROM (VALUES ('2024-03-31 02:30:00 UTC'::nanotimestamptz), ('1950-06-01 10:00:00 UTC'), ('2100-10-31 00:59:59 UTC')) v(x);
RESET DateStyle;
SET timezone = 'UTC';
-- negative values print unambiguously (prototype bug fixed)
SELECT (-1)::bigint::nanotimestamptz, (-1000000001)::bigint::nanotimestamptz;
-- text round trip
SELECT t::text::nanotimestamptz = t FROM (VALUES ('4714-11-24 00:00:00 UTC BC'::nanotimestamptz), ('1969-12-31 23:59:59.999999999 UTC'), ('294276-12-31 23:59:59.999999999 UTC')) v(t);
-- binary send/recv round trip through COPY
CREATE TEMP TABLE bin_src(t nanotimestamptz);
INSERT INTO bin_src VALUES ('4714-11-24 00:00:00 UTC BC'), ('1969-12-31 23:59:59.999999999 UTC'), ('2024-01-01 00:00:00.123456789 UTC'), ('294276-12-31 23:59:59.999999999 UTC');
SELECT nanotimestamptz_send(t) FROM bin_src;
COPY bin_src TO '/tmp/pg_nanotime_regress.bin' WITH (FORMAT binary);
CREATE TEMP TABLE bin_dst(t nanotimestamptz);
COPY bin_dst FROM '/tmp/pg_nanotime_regress.bin' WITH (FORMAT binary);
SELECT count(*) FROM bin_src s JOIN bin_dst d ON s.t = d.t;
