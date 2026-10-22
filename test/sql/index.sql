SET timezone = 'UTC';
CREATE TEMP TABLE ix(t nanotimestamptz, v int);
INSERT INTO ix SELECT (g::bigint * 1000000007 - 5000000000000)::nanotimestamptz, g FROM generate_series(1, 10000) g;
INSERT INTO ix VALUES ('4714-11-24 00:00:00 UTC BC', -1), ('294276-12-31 23:59:59.999999999 UTC', -2), ('1969-12-31 23:59:59.999999999 UTC', -3);
CREATE INDEX ix_bt ON ix(t);
CREATE INDEX ix_h ON ix USING hash(t);
ANALYZE ix;
SET enable_seqscan = off;
SET enable_bitmapscan = off;
EXPLAIN (COSTS OFF) SELECT * FROM ix WHERE t >= '1969-12-31 UTC' AND t < '1970-01-01 UTC';
SELECT v FROM ix WHERE t >= '1969-12-31 UTC' AND t < '1970-01-01 UTC' ORDER BY t LIMIT 3;
SELECT t, v FROM ix ORDER BY t LIMIT 3;
SELECT t, v FROM ix ORDER BY t DESC LIMIT 2;
SET enable_indexscan = on;
DROP INDEX ix_bt;
EXPLAIN (COSTS OFF) SELECT v FROM ix WHERE t = '1969-12-31 23:59:59.999999999 UTC';
SELECT v FROM ix WHERE t = '1969-12-31 23:59:59.999999999 UTC';
RESET enable_seqscan;
-- hash join / group by
SELECT count(*) FROM ix a JOIN ix b USING (t);
SELECT count(DISTINCT t) FROM ix;
-- BRIN (minmax) on the 16-byte type
CREATE INDEX ix_brin ON ix USING brin(t);
DROP INDEX ix_h;
SET enable_seqscan = off;
SET enable_bitmapscan = on;
EXPLAIN (COSTS OFF) SELECT v FROM ix WHERE t >= '1969-12-31 23:00:00 UTC' AND t < '1969-12-31 23:00:01 UTC';
SELECT v FROM ix WHERE t >= '1969-12-31 23:00:00 UTC' AND t < '1969-12-31 23:00:01 UTC';
RESET enable_seqscan;
