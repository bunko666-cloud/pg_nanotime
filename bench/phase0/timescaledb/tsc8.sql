\set ON_ERROR_STOP 0
SET timezone='UTC';
CREATE EXTENSION timescaledb; CREATE EXTENSION pg_nanotime;
CREATE TABLE h8(t nanotimestamptz8 NOT NULL, v int);
SELECT create_hypertable('h8', by_range('t', 86400000000000));
SELECT d.column_type, d.partitioning_func FROM timescaledb_information.dimensions d WHERE hypertable_name='h8';
INSERT INTO h8 SELECT ('2024-01-01 UTC'::nanotimestamptz8::bigint + g*3600000000007)::nanotimestamptz8, g FROM generate_series(0,71) g;
INSERT INTO h8 VALUES ('1969-12-31 23:59:59.999999999 UTC', -1), ('1677-09-21 00:12:43.145224192 UTC', -2), ('2262-04-11 23:47:16.854775807 UTC', -3);
SELECT count(*) AS chunks FROM show_chunks('h8');
EXPLAIN (COSTS OFF) SELECT * FROM h8 WHERE t >= '2024-01-02 UTC' AND t < '2024-01-03 UTC';
SELECT time_bucket(86400000000000, t) FROM h8 LIMIT 1;
SELECT time_bucket(86400000000000::bigint, t::bigint)::nanotimestamptz8 AS day, count(*) FROM h8 WHERE v >= 0 GROUP BY 1 ORDER BY 1;
CREATE FUNCTION h8_now() RETURNS bigint LANGUAGE sql STABLE AS $$ SELECT now_ns8()::bigint $$;
SELECT set_integer_now_func('h8', 'h8_now');
CREATE MATERIALIZED VIEW h8_daily WITH (timescaledb.continuous) AS
  SELECT time_bucket(86400000000000::bigint, t::bigint) AS day, count(*) n, max(v) FROM h8 GROUP BY 1 WITH NO DATA;
CREATE MATERIALIZED VIEW h8_daily2 WITH (timescaledb.continuous) AS
  SELECT time_bucket(86400000000000, t) AS day, count(*) n FROM h8 GROUP BY 1 WITH NO DATA;
CALL refresh_continuous_aggregate('h8_daily', NULL, NULL);
SELECT day::nanotimestamptz8, n FROM h8_daily ORDER BY 1;
SELECT add_continuous_aggregate_policy('h8_daily', start_offset => 86400000000000*7, end_offset => 3600000000000, schedule_interval => interval '1 hour') IS NOT NULL AS policy;
ALTER TABLE h8 SET (timescaledb.compress, timescaledb.compress_orderby='t DESC');
SELECT count(compress_chunk(c)) FROM show_chunks('h8') c;
EXPLAIN (COSTS OFF) SELECT * FROM h8 WHERE t >= '2024-01-02 UTC' AND t < '2024-01-03 UTC';
SELECT count(*) FROM h8 WHERE t >= '2024-01-02 UTC' AND t < '2024-01-03 UTC';
SELECT count(*) AS dropped FROM drop_chunks('h8', older_than => '2000-01-01 UTC'::nanotimestamptz8::bigint);
SELECT count(*) AS dropped_typed FROM drop_chunks('h8', older_than => '2000-01-01 UTC'::nanotimestamptz8);
