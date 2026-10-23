-- Phase 3: TimescaleDB helpers (optional suite: make installcheck WITH_TIMESCALEDB=1)
SET client_min_messages = error;
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS pg_nanotime;
RESET client_min_messages;
SET timezone = 'UTC';

-- partitioning map: monotonic, saturating at the int64 ends
SELECT t, nanotime_part(t::nanotimestamptz) FROM (VALUES
  ('4714-11-24 00:00:00+00 BC'), ('0001-01-01 00:00:00+00'),
  ('1677-09-21 00:12:43.145224191+00'), ('1677-09-21 00:12:43.145224192+00'),
  ('1969-12-31 23:59:59.999999999+00'), ('1970-01-01 00:00:00+00'),
  ('2262-04-11 23:47:16.854775807+00'), ('2262-04-11 23:47:16.854775808+00'),
  ('294276-12-31 23:59:59.999999999+00')) v(t);
SELECT nanotime_part_notz('2024-01-01 00:00:00.000000001'::nanotimestamp) AS notz,
       nanotime_part8('2024-01-01 00:00:00.000000001+00'::nanotimestamptz8) AS nt8;
SELECT ns('1 day') AS one_day, ns('7 days 00:00:00.000000001') AS week_plus_1ns;
SELECT provolatile FROM pg_proc WHERE proname = 'nanotime_now_int8';
BEGIN;
SELECT nanotime_now_int8() = now_ns8()::bigint AS equals_now_ns8,
       nanotime_now_int8() = nanotime_now_int8() AS stable_in_xact;
COMMIT;

-- 16B hypertable with clamping partition function
CREATE TABLE h16(t nanotimestamptz NOT NULL, v int);
SELECT create_hypertable('h16', by_range('t', ns('1 day'), partition_func => 'nanotime_part'));
INSERT INTO h16 VALUES ('0001-01-01 00:00:00+00', 1), ('1969-12-31 12:00:00+00', 2),
  ('2024-01-01 00:00:00.000000001+00', 3), ('2024-01-02 12:00:00+00', 4), ('9999-12-31 00:00:00+00', 5);
SELECT range_start_integer, range_end_integer FROM timescaledb_information.chunks
 WHERE hypertable_name = 'h16' ORDER BY 1;
EXPLAIN (costs off) SELECT * FROM h16 WHERE t >= '2024-01-02+00' AND t < '2024-01-03+00';
SELECT v FROM h16 WHERE t >= '2024-01-02+00' AND t < '2024-01-03+00';
SELECT set_integer_now_func('h16', 'nanotime_now_int8');
SELECT count(*) AS dropped FROM drop_chunks('h16', older_than => nanotime_part('2000-01-01+00'::nanotimestamptz));
SELECT v FROM h16 ORDER BY t;
SELECT add_retention_policy('h16', drop_after => ns('3650 days')) > 0 AS policy_added;
SELECT remove_retention_policy('h16');

-- 8B hypertable: native dimension; identity partition_func enables integer now
CREATE TABLE h8(t nanotimestamptz8 NOT NULL, v int);
SELECT create_hypertable('h8', by_range('t', ns('1 day')));
SELECT set_integer_now_func('h8', 'nanotime_now_int8');  -- not allowed without a partition function
DROP TABLE h8;
CREATE TABLE h8(t nanotimestamptz8 NOT NULL, v int);
SELECT create_hypertable('h8', by_range('t', ns('1 day'), partition_func => 'nanotime_part8'));
SELECT set_integer_now_func('h8', 'nanotime_now_int8');
INSERT INTO h8 SELECT '2024-01-01+00'::nanotimestamptz8 + g * '6 hours'::nanointerval, g FROM generate_series(0, 15) g;
-- bucketing: time_bucket_ns on the column (TimescaleDB's time_bucket does not accept the type)
SELECT time_bucket_ns('1 day', t) AS day, count(*) FROM h8 GROUP BY 1 ORDER BY 1;
EXPLAIN (costs off) SELECT * FROM h8 WHERE t >= '2024-01-02+00' AND t < '2024-01-03+00';
SELECT count(*) AS dropped FROM drop_chunks('h8', older_than => nanotime_part8('2024-01-03+00'));
SELECT min(t), count(*) FROM h8;
