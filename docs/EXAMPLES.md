# pg_nanotime 實例集

以下每段 SQL 與輸出都是在 PostgreSQL 17.11 與 18.6 上實際執行的結果（兩版輸出完全相同），直接取自回歸測試 [`test/sql/examples.sql`](../test/sql/examples.sql) 與 [`test/expected/examples.out`](../test/expected/examples.out)。每次 `make installcheck` 都會重跑，所以文件與實際行為保持一致。

共同設定：`SET timezone = 'UTC';`。與現在時間有關的值都改用固定字面值，或只顯示計數，不顯示時間本身。

## 1. 交易 tick 資料與延遲統計

交易所在 `exch_ts` 蓋上時間，我們收到時在 `recv_ts` 記下時間（正式環境用 `DEFAULT clock_ns8()` 自動填入；這裡為了輸出固定，直接寫入時間字面值）。兩者相減就是延遲，以奈秒精確計算。

```
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
 symbol |             exch_ts              |      latency       
--------+----------------------------------+--------------------
 2330   | 2026-10-23 01:30:00.000000100+00 | 00:00:00.000041250
 2317   | 2026-10-23 01:30:00.000000500+00 | 00:00:00.000038400
 2330   | 2026-10-23 01:30:00.000250000+00 | 00:00:00.000039007
 2317   | 2026-10-23 01:30:00.000900000+00 | 00:00:00.000061234
 2330   | 2026-10-23 01:30:00.001000000+00 | 00:00:00.000102500
(5 rows)

SELECT symbol,
       count(*)                                                AS n,
       min((recv_ts - exch_ts)::bigint)                        AS min_ns,
       round(avg((recv_ts - exch_ts)::bigint))                 AS avg_ns,
       percentile_disc(0.5) WITHIN GROUP (ORDER BY (recv_ts - exch_ts)::bigint) AS p50_ns,
       max((recv_ts - exch_ts)::bigint)                        AS max_ns
FROM ticks GROUP BY symbol ORDER BY symbol;
 symbol | n | min_ns | avg_ns | p50_ns | max_ns 
--------+---+--------+--------+--------+--------
 2317   | 2 |  38400 |  49817 |  38400 |  61234
 2330   | 3 |  39007 |  60919 |  41250 | 102500
(2 rows)

-- latency of anything slower than 50 microseconds
SELECT symbol, price, recv_ts - exch_ts AS latency
FROM ticks WHERE recv_ts - exch_ts > '50 microseconds'::nanointerval ORDER BY exch_ts;
 symbol |   price   |      latency       
--------+-----------+--------------------
 2317   |  213.0000 | 00:00:00.000061234
 2330   | 1026.0000 | 00:00:00.000102500
(2 rows)
```

## 2. 撮合引擎：先到先處理（FIFO）

`clock_ns8_global()` 在所有連線之間保證嚴格遞增、不重複，可以直接當主鍵與排隊順序。需要 `shared_preload_libraries = 'pg_nanotime'`。時間值每次執行都不同，所以這裡只顯示計數與排序結果，不顯示時間本身。

```
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
 orders | distinct_ts 
--------+-------------
  10000 |       10000
(1 row)

SELECT count(*) AS not_increasing
FROM (SELECT seq_ts, lag(seq_ts) OVER (ORDER BY ctid) AS prev FROM orders) s
WHERE seq_ts <= prev;
 not_increasing 
----------------
              0
(1 row)

-- FIFO: the best-priced buy orders, oldest first
SELECT side, price, qty FROM orders
WHERE side = 'B' ORDER BY price DESC, seq_ts LIMIT 3;
 side |  price   | qty 
------+----------+-----
 B    | 106.0000 |   7
 B    | 106.0000 |   1
 B    | 106.0000 |   5
(3 rows)
```

## 3. 網路封包：匯入 bigint 奈秒

pcap、PTP 等工具常輸出「1970 年起的奈秒整數」。`::nanotimestamptz8` 直接轉換（不需運算），也能轉回 bigint 匯出。

```
CREATE TABLE packets_raw (ts_ns bigint, src inet, len int);
INSERT INTO packets_raw VALUES
  (1792719000000000000, '10.0.0.1', 64),
  (1792719000000001250, '10.0.0.2', 1500),
  (1792719000000001300, '10.0.0.1', 64),
  (1792719000000250000, '10.0.0.3', 576);
CREATE TABLE packets AS
  SELECT ts_ns::nanotimestamptz8 AS ts, src, len FROM packets_raw;
SELECT ts, src, len, ts - lag(ts) OVER (ORDER BY ts) AS gap FROM packets ORDER BY ts;
                ts                |   src    | len  |        gap         
----------------------------------+----------+------+--------------------
 2026-10-23 01:30:00.000000000+00 | 10.0.0.1 |   64 | 
 2026-10-23 01:30:00.000001250+00 | 10.0.0.2 | 1500 | 00:00:00.000001250
 2026-10-23 01:30:00.000001300+00 | 10.0.0.1 |   64 | 00:00:00.000000050
 2026-10-23 01:30:00.000250000+00 | 10.0.0.3 |  576 | 00:00:00.000248700
(4 rows)

-- and back to bigint for export
SELECT ts::bigint AS ts_ns FROM packets ORDER BY ts LIMIT 1;
        ts_ns        
---------------------
 1792719000000000000
(1 row)
```

## 4. IoT 感測器：每秒分桶統計

每 250 ms 一筆讀數，用 `time_bucket_ns` 依 1 秒分桶。

```
CREATE TABLE readings (sensor int, ts nanotimestamptz, value double precision);
INSERT INTO readings
SELECT s, '2026-10-23 00:00:00+00'::nanotimestamptz + (g * 250000000::bigint)::nanointerval,
       s * 10 + g % 4
FROM generate_series(1, 2) s, generate_series(0, 11) g;
SELECT sensor, time_bucket_ns('1 second'::nanointerval, ts) AS bucket,
       count(*) AS n, avg(value) AS avg_value
FROM readings GROUP BY 1, 2 ORDER BY 1, 2;
 sensor |              bucket              | n | avg_value 
--------+----------------------------------+---+-----------
      1 | 2026-10-23 00:00:00.000000000+00 | 4 |      11.5
      1 | 2026-10-23 00:00:01.000000000+00 | 4 |      11.5
      1 | 2026-10-23 00:00:02.000000000+00 | 4 |      11.5
      2 | 2026-10-23 00:00:00.000000000+00 | 4 |      21.5
      2 | 2026-10-23 00:00:01.000000000+00 | 4 |      21.5
      2 | 2026-10-23 00:00:02.000000000+00 | 4 |      21.5
(6 rows)
```

## 5. 從 timestamp9 遷移

這裡用 bigint domain 模擬 timestamp9（數值相同：1970 年起的奈秒），讓測試不依賴 timestamp9；真實 timestamp9 欄位的呼叫方式完全相同，實測紀錄見 [TESTING.md](TESTING.md)。先 `dry_run` 看要執行的 SQL，再正式執行。

```
-- timestamp9 here; with the real extension the same calls work.
CREATE DOMAIN timestamp9 AS bigint;
CREATE TABLE events (id int PRIMARY KEY, t timestamp9 NOT NULL);
INSERT INTO events VALUES (1, 1792719000000000001), (2, -1), (3, 1792719000123456789);
CREATE INDEX events_t ON events(t);
CALL nanotime_migrate_column('events', 't', dry_run => true);
NOTICE:  index events_t will be rebuilt
NOTICE:  ALTER TABLE events ALTER COLUMN t TYPE nanotimestamptz USING (t)::bigint::nanotimestamptz
CALL nanotime_migrate_column('events', 't');
NOTICE:  index events_t will be rebuilt
SELECT id, t FROM events ORDER BY t;
 id |                t                 
----+----------------------------------
  2 | 1969-12-31 23:59:59.999999999+00
  1 | 2026-10-23 01:30:00.000000001+00
  3 | 2026-10-23 01:30:00.123456789+00
(3 rows)

SELECT pg_typeof(t) FROM events LIMIT 1;
    pg_typeof    
-----------------
 nanotimestamptz
(1 row)
```

## 6. 交易內固定時間與即時時鐘

`now_ns()` 在同一交易內不變；`clock_ns_monotonic()` 每次呼叫都會前進。

```
BEGIN;
SELECT now_ns() = now_ns() AS same_in_txn, clock_ns_monotonic() < clock_ns_monotonic() AS clock_moves;
 same_in_txn | clock_moves 
-------------+-------------
 t           | t
(1 row)

COMMIT;
```
