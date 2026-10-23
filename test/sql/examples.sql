-- Examples from docs/EXAMPLES.md. Keep the two in sync: every block below
-- is pasted into the doc together with its expected output.
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pg_nanotime;
DROP SCHEMA IF EXISTS ex CASCADE;
RESET client_min_messages;
CREATE SCHEMA ex;
SET search_path = ex, public;
SET timezone = 'UTC';

-- ex1: trade ticks and latency
CREATE TABLE ticks (
  symbol    text              NOT NULL,
  price     numeric(12,4)     NOT NULL,
  exch_ts   nanotimestamptz8  NOT NULL,                  -- time stamped by the exchange
  recv_ts   nanotimestamptz8  NOT NULL DEFAULT clock_ns8() -- time we received it
);
INSERT INTO ticks VALUES
  ('2330', 1025.0000, '2026-10-23 01:30:00.000000100+00', '2026-10-23 01:30:00.000041350+00'),
  ('2330', 1025.5000, '2026-10-23 01:30:00.000250000+00', '2026-10-23 01:30:00.000289007+00'),
  ('2330', 1026.0000, '2026-10-23 01:30:00.001000000+00', '2026-10-23 01:30:00.001102500+00'),
  ('2317',  212.5000, '2026-10-23 01:30:00.000000500+00', '2026-10-23 01:30:00.000038900+00'),
  ('2317',  213.0000, '2026-10-23 01:30:00.000900000+00', '2026-10-23 01:30:00.000961234+00');
SELECT symbol, exch_ts, recv_ts - exch_ts AS latency FROM ticks ORDER BY exch_ts;
SELECT symbol,
       count(*)                                                AS n,
       min((recv_ts - exch_ts)::bigint)                        AS min_ns,
       round(avg((recv_ts - exch_ts)::bigint))                 AS avg_ns,
       percentile_disc(0.5) WITHIN GROUP (ORDER BY (recv_ts - exch_ts)::bigint) AS p50_ns,
       max((recv_ts - exch_ts)::bigint)                        AS max_ns
FROM ticks GROUP BY symbol ORDER BY symbol;
-- latency of anything slower than 50 microseconds
SELECT symbol, price, recv_ts - exch_ts AS latency
FROM ticks WHERE recv_ts - exch_ts > '50 microseconds'::nanointerval ORDER BY exch_ts;

-- ex2: order matching FIFO (needs shared_preload_libraries = 'pg_nanotime')
CREATE TABLE orders (
  seq_ts  nanotimestamptz8 NOT NULL DEFAULT clock_ns8_global() PRIMARY KEY,
  side    char(1)          NOT NULL,
  price   numeric(12,4)    NOT NULL,
  qty     int              NOT NULL
);
-- 10000 orders in one statement: every default is a distinct, increasing time
INSERT INTO orders(side, price, qty)
SELECT CASE WHEN g % 2 = 0 THEN 'B' ELSE 'S' END, 100 + g % 7, g % 10 + 1
FROM generate_series(1, 10000) g;
SELECT count(*) AS orders, count(DISTINCT seq_ts) AS distinct_ts FROM orders;
SELECT count(*) AS not_increasing
FROM (SELECT seq_ts, lag(seq_ts) OVER (ORDER BY ctid) AS prev FROM orders) s
WHERE seq_ts <= prev;
-- FIFO: the best-priced buy orders, oldest first
SELECT side, price, qty FROM orders
WHERE side = 'B' ORDER BY price DESC, seq_ts LIMIT 3;

-- ex3: network packets: import bigint ns from a capture tool
CREATE TABLE packets_raw (ts_ns bigint, src inet, len int);
INSERT INTO packets_raw VALUES
  (1792719000000000000, '10.0.0.1', 64),
  (1792719000000001250, '10.0.0.2', 1500),
  (1792719000000001300, '10.0.0.1', 64),
  (1792719000000250000, '10.0.0.3', 576);
CREATE TABLE packets AS
  SELECT ts_ns::nanotimestamptz8 AS ts, src, len FROM packets_raw;
SELECT ts, src, len, ts - lag(ts) OVER (ORDER BY ts) AS gap FROM packets ORDER BY ts;
-- and back to bigint for export
SELECT ts::bigint AS ts_ns FROM packets ORDER BY ts LIMIT 1;

-- ex4: IoT sensor readings, 1-second buckets
CREATE TABLE readings (sensor int, ts nanotimestamptz, value double precision);
INSERT INTO readings
SELECT s, '2026-10-23 00:00:00+00'::nanotimestamptz + (g * 250000000::bigint)::nanointerval,
       s * 10 + g % 4
FROM generate_series(1, 2) s, generate_series(0, 11) g;
SELECT sensor, time_bucket_ns('1 second'::nanointerval, ts) AS bucket,
       count(*) AS n, avg(value) AS avg_value
FROM readings GROUP BY 1, 2 ORDER BY 1, 2;

-- ex5: migrate a timestamp9 column. A domain over bigint stands in for
-- timestamp9 here; with the real extension the same calls work.
CREATE DOMAIN timestamp9 AS bigint;
CREATE TABLE events (id int PRIMARY KEY, t timestamp9 NOT NULL);
INSERT INTO events VALUES (1, 1792719000000000001), (2, -1), (3, 1792719000123456789);
CREATE INDEX events_t ON events(t);
CALL nanotime_migrate_column('events', 't', dry_run => true);
CALL nanotime_migrate_column('events', 't');
SELECT id, t FROM events ORDER BY t;
SELECT pg_typeof(t) FROM events LIMIT 1;

-- ex6: now_ns() is fixed for the transaction; the clock functions move
BEGIN;
SELECT now_ns() = now_ns() AS same_in_txn, clock_ns_monotonic() < clock_ns_monotonic() AS clock_moves;
COMMIT;

RESET search_path;
DROP SCHEMA ex CASCADE;
