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

-- 0.3.0: one-step setup nanotime_timescale_setup / nanotime_drop_chunks
CREATE FUNCTION pg_temp.plan_check(q text, idx text,
    OUT ordered bool, OUT uses_index bool, OUT sorts_or_seqscans bool) LANGUAGE plpgsql AS $$
DECLARE line text;
BEGIN
  ordered := false; uses_index := false; sorts_or_seqscans := false;
  FOR line IN EXECUTE 'EXPLAIN (analyze, costs off, timing off, summary off, buffers off) ' || q LOOP
    ordered := ordered OR line ~ 'Order: t DESC';
    uses_index := uses_index OR line ~ ('Index Scan using _hyper_\d+_\d+_chunk_' || idx);
    sorts_or_seqscans := sorts_or_seqscans OR line ~ '(Sort|Seq Scan)';
  END LOOP;
END $$;
-- 16 B with time zone
CREATE TABLE s16(t nanotimestamptz NOT NULL, v int);
SELECT nanotime_timescale_setup('s16', 't', '1 day');
SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename = 's16';
SELECT h.table_name, d.column_name, d.partitioning_func, d.interval_length, d.integer_now_func
  FROM _timescaledb_catalog.dimension d JOIN _timescaledb_catalog.hypertable h ON h.id = d.hypertable_id
 WHERE h.table_name = 's16';
INSERT INTO s16 SELECT '2024-01-01 00:00:00.000000001+00'::nanotimestamptz + g * '1 min'::nanointerval, g
  FROM generate_series(0, 4319) g;
SELECT count(*) AS chunks FROM show_chunks('s16');
SELECT count(*) AS chunk_t_desc_indexes FROM show_chunks('s16') c
  JOIN pg_index i ON i.indrelid = c JOIN pg_attribute a ON a.attrelid = c AND a.attnum = i.indkey[0]
 WHERE a.attname = 't' AND i.indoption[0] & 1 = 1;
ANALYZE s16;
SELECT * FROM pg_temp.plan_check('SELECT * FROM s16 ORDER BY t DESC LIMIT 3', 's16_t_idx');
SELECT * FROM s16 ORDER BY t DESC LIMIT 3;
SELECT * FROM pg_temp.plan_check('SELECT * FROM s16 WHERE t >= ''2024-01-02 10:00+00'' AND t < ''2024-01-02 10:05+00''', 's16_t_idx');
SELECT count(*) AS dropped FROM nanotime_drop_chunks('s16', older_than => '2024-01-02 00:00:00+00');
SELECT min(t), count(*) FROM s16;
SELECT count(*) AS dropped FROM nanotime_drop_chunks('s16', newer_than => '2024-01-03 00:00:00+00');
SELECT min(t), max(t), count(*) FROM s16;
-- integer now is set, so a retention policy runs
SELECT add_retention_policy('s16', drop_after => ns('1 day')) AS job \gset
CALL run_job(:job);
SELECT count(*) AS after_retention FROM s16;
SELECT remove_retention_policy('s16');
-- without time zone
CREATE TABLE snz(t nanotimestamp NOT NULL, v int);
SELECT nanotime_timescale_setup('snz', 't', '1 hour');
INSERT INTO snz SELECT '2024-01-01'::nanotimestamp + g * '30 min'::nanointerval, g FROM generate_series(0, 15) g;
SELECT count(*) AS chunks FROM show_chunks('snz');
SELECT count(*) AS dropped FROM nanotime_drop_chunks('snz', older_than => '2024-01-01 04:00:00+00');
SELECT min(t), count(*) FROM snz;
-- 8 B with an existing index on the column: kept, not duplicated
CREATE TABLE s8(t nanotimestamptz8 NOT NULL, v int);
CREATE INDEX s8_t ON s8 (t);
SELECT nanotime_timescale_setup('s8', 't', '6 hours');
SELECT indexdef FROM pg_indexes WHERE schemaname = 'public' AND tablename = 's8';
INSERT INTO s8 SELECT '2024-01-01+00'::nanotimestamptz8 + g * '6 hours'::nanointerval, g FROM generate_series(0, 15) g;
SELECT count(*) AS chunks FROM show_chunks('s8');
SELECT count(*) AS dropped FROM nanotime_drop_chunks('s8', older_than => '1000-01-01 00:00:00+00');  -- nothing older: no error
SELECT count(*) AS dropped FROM nanotime_drop_chunks('s8', older_than => '2024-01-02 00:00:00+00');
SELECT min(t), count(*) FROM s8;
-- 8 B partitioned natively (no partition function): the wrapper passes nanotimestamptz8
CREATE TABLE n8(t nanotimestamptz8 NOT NULL, v int);
SELECT create_hypertable('n8', by_range('t', ns('1 day')));
INSERT INTO n8 SELECT '2024-01-01+00'::nanotimestamptz8 + g * '6 hours'::nanointerval, g FROM generate_series(0, 15) g;
SELECT count(*) AS dropped FROM nanotime_drop_chunks('n8', older_than => '2024-01-02 00:00:00+00');
SELECT min(t), count(*) FROM n8;
-- errors
SELECT nanotime_timescale_setup('s16', 't');
CREATE TABLE sbad(t timestamptz NOT NULL, u nanotimestamptz NOT NULL);
SELECT nanotime_timescale_setup('sbad', 't');
SELECT nanotime_timescale_setup('sbad', 'nope');
SELECT nanotime_timescale_setup('sbad', 'u', '0');
SELECT * FROM nanotime_drop_chunks('sbad', older_than => '2024-01-01 00:00:00+00');
INSERT INTO sbad VALUES ('2024-01-01+00', '2024-01-01 00:00:00.5+00');
SELECT nanotime_timescale_setup('sbad', 'u');
SET client_min_messages = warning;
SELECT nanotime_timescale_setup('sbad', 'u', migrate_data => true);
RESET client_min_messages;
SELECT count(*) AS chunks FROM show_chunks('sbad');
DROP TABLE s16, snz, s8, n8, sbad;
