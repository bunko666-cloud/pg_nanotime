SET timezone = 'UTC';
SELECT typlen, typbyval, typalign FROM pg_type WHERE typname = 'nanotimestamptz8';
-- range = int64 ns, strict errors 1 ns outside
SELECT '1677-09-21 00:12:43.145224192 UTC'::nanotimestamptz8 AS min8, '2262-04-11 23:47:16.854775807 UTC'::nanotimestamptz8 AS max8;
SELECT '1677-09-21 00:12:43.145224191 UTC'::nanotimestamptz8;
SELECT '2262-04-11 23:47:16.854775808 UTC'::nanotimestamptz8;
SELECT '1500-01-01 UTC'::nanotimestamptz8;
SELECT '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz8, '1970-01-01 UTC'::nanotimestamptz8;
SET timezone = 'Asia/Taipei';
SELECT '2024-01-01 00:00:00.123456789 UTC'::nanotimestamptz8;
SET timezone = 'UTC';
-- bigint: binary-compatible, explicit only
SELECT castmethod, castcontext FROM pg_cast WHERE castsource = 'nanotimestamptz8'::regtype AND casttarget = 'bigint'::regtype
UNION ALL SELECT castmethod, castcontext FROM pg_cast WHERE castsource = 'bigint'::regtype AND casttarget = 'nanotimestamptz8'::regtype;
SELECT (-9223372036854775808)::bigint::nanotimestamptz8, 9223372036854775807::bigint::nanotimestamptz8, (-1)::bigint::nanotimestamptz8;
SELECT '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz8::bigint;
-- 16B <-> 8B
SELECT '2024-01-01 00:00:00.000000001 UTC'::nanotimestamptz8::nanotimestamptz;
SELECT '1677-09-21 00:12:43.145224192 UTC'::nanotimestamptz::nanotimestamptz8;
SELECT '1677-09-21 00:12:43.145224191 UTC'::nanotimestamptz::nanotimestamptz8;
SELECT '2262-04-11 23:47:16.854775808 UTC'::nanotimestamptz::nanotimestamptz8;
SELECT '2024-01-01 UTC'::nanotimestamptz8 = '2024-01-01 UTC'::nanotimestamptz AS mixed_eq;
-- timestamptz (floor)
SELECT '1969-12-31 23:59:59.999999999 UTC'::nanotimestamptz8::timestamptz, '2024-01-01 00:00:00.123456999 UTC'::nanotimestamptz8::timestamptz;
SELECT '2024-01-01 00:00:00.123456 UTC'::timestamptz::nanotimestamptz8;
SELECT '1600-01-01 UTC'::timestamptz::nanotimestamptz8;
-- binary I/O
SELECT nanotimestamptz8_send('1969-12-31 23:59:59.999999999 UTC');
CREATE TEMP TABLE b8(t nanotimestamptz8);
INSERT INTO b8 VALUES ('1677-09-21 00:12:43.145224192 UTC'), ('1969-12-31 23:59:59.999999999 UTC'), ('2262-04-11 23:47:16.854775807 UTC');
-- per-port file name so several servers (different OS users) can run the suite
SELECT '/tmp/pg_nanotime_regress8_' || current_setting('port') || '.bin' AS binfile \gset
COPY b8 TO :'binfile' WITH (FORMAT binary);
CREATE TEMP TABLE b8d(t nanotimestamptz8);
COPY b8d FROM :'binfile' WITH (FORMAT binary);
SELECT count(*) FROM b8 JOIN b8d USING (t);
-- clocks
SELECT provolatile, proname FROM pg_proc WHERE proname IN ('clock_ns8', 'now_ns8', 'statement_ns8') ORDER BY proname;
BEGIN;
SELECT now_ns8()::nanotimestamptz = now_ns() AS same_xact_reading, statement_ns8()::nanotimestamptz = statement_ns() AS same_stmt_reading;
SELECT clock_ns8() >= now_ns8() AS clock_after;
COMMIT;
CREATE TEMP TABLE ev8(id int, t nanotimestamptz8 DEFAULT clock_ns8(), tx nanotimestamptz8 DEFAULT now_ns8());
INSERT INTO ev8(id) SELECT g FROM generate_series(1, 1000) g;
SELECT count(DISTINCT t) > 1 AS clock_varies, count(DISTINCT tx) AS now_constant FROM ev8;
-- indexes
CREATE TEMP TABLE ix8(t nanotimestamptz8, v int);
INSERT INTO ix8 SELECT (g::bigint * 1000000007 - 5000000000000)::nanotimestamptz8, g FROM generate_series(1, 10000) g;
INSERT INTO ix8 VALUES ((-9223372036854775808)::bigint::nanotimestamptz8, -1), (9223372036854775807::bigint::nanotimestamptz8, -2);
ANALYZE ix8;
SET enable_seqscan = off;
SET enable_bitmapscan = off;
CREATE INDEX ix8_bt ON ix8(t);
EXPLAIN (COSTS OFF) SELECT v FROM ix8 WHERE t >= '1969-12-31 UTC' AND t < '1970-01-01 UTC';
SELECT t, v FROM ix8 ORDER BY t LIMIT 2;
SELECT t, v FROM ix8 ORDER BY t DESC LIMIT 2;
DROP INDEX ix8_bt;
CREATE INDEX ix8_h ON ix8 USING hash(t);
EXPLAIN (COSTS OFF) SELECT v FROM ix8 WHERE t = '1969-12-31 22:36:41.000000007 UTC';
SELECT v FROM ix8 WHERE t = '1969-12-31 22:36:41.000000007 UTC';
DROP INDEX ix8_h;
SET enable_bitmapscan = on;
CREATE INDEX ix8_brin ON ix8 USING brin(t);
EXPLAIN (COSTS OFF) SELECT v FROM ix8 WHERE t >= '1969-12-31 23:00:00 UTC' AND t < '1969-12-31 23:00:01 UTC';
SELECT v FROM ix8 WHERE t >= '1969-12-31 23:00:00 UTC' AND t < '1969-12-31 23:00:01 UTC';
RESET enable_seqscan;
SELECT min(t), max(t), count(DISTINCT t) FROM ix8;
