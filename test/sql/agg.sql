-- sum(nanointerval) / avg(nanointerval)
SET client_min_messages = warning;
CREATE EXTENSION IF NOT EXISTS pg_nanotime;
RESET client_min_messages;
CREATE TABLE agg_t (g int, d nanointerval);
INSERT INTO agg_t VALUES
  (1, '1.000000001'), (1, '2.5'), (1, NULL),
  (2, '-3 ms'), (2, '1 ns'), (2, '2 ns'),
  (3, NULL);
SELECT g, sum(d), avg(d), count(d) FROM agg_t GROUP BY g ORDER BY g;
-- empty input and all-NULL input give NULL
SELECT sum(d), avg(d) FROM agg_t WHERE false;
SELECT sum(d) IS NULL AS s_null, avg(d) IS NULL AS a_null FROM agg_t WHERE g = 3;
-- avg rounds half away from zero, same as nanointerval / bigint
SELECT avg(d) FROM (VALUES ('1 ns'::nanointerval), ('2 ns')) v(d);
SELECT avg(d) FROM (VALUES ('-1 ns'::nanointerval), ('-2 ns')) v(d);
SELECT avg(d) FROM (VALUES ('1 ns'::nanointerval), ('1 ns'), ('2 ns')) v(d);
SELECT '3 ns'::nanointerval / 2 AS div_pos, '-3 ns'::nanointerval / 2 AS div_neg;
-- exact: matches nanointerval_ns(numeric) arithmetic
SELECT nanointerval_ns(sum(d)) = sum(nanointerval_ns(d)) AS exact FROM agg_t;
-- overflow is an error, never a silent wrap
SELECT sum(d) FROM (VALUES (nanointerval_from_ns(9000000000000000000000)),
                           (nanointerval_from_ns(9000000000000000000000))) v(d);
-- intermediate overflow that comes back into range is fine (exact state)
SELECT sum(d) FROM (VALUES (nanointerval_from_ns(9000000000000000000000)),
                           (nanointerval_from_ns(9000000000000000000000)),
                           (nanointerval_from_ns(-9000000000000000000000))) v(d);
-- window functions (moving aggregate with inverse transition)
SELECT i, sum(d) OVER w, avg(d) OVER w
FROM (SELECT i, (i || ' ms')::nanointerval AS d FROM generate_series(1, 5) i) s
WINDOW w AS (ORDER BY i ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING)
ORDER BY i;
SELECT i, sum(d) OVER (ORDER BY i ROWS BETWEEN 1 PRECEDING AND CURRENT ROW)
FROM (VALUES (1, '1 s'::nanointerval), (2, NULL), (3, NULL), (4, '2 s')) v(i, d) ORDER BY i;
-- parallel plan: partial aggregate + combine + serialize/deserialize
CREATE TABLE agg_big AS
  SELECT nanointerval_from_ns(i * 1000 + (i % 7)) AS d FROM generate_series(1, 200000) i;
ANALYZE agg_big;
SET parallel_setup_cost = 0;
SET parallel_tuple_cost = 0;
SET min_parallel_table_scan_size = 0;
SET max_parallel_workers_per_gather = 2;
EXPLAIN (COSTS OFF) SELECT sum(d), avg(d) FROM agg_big;
SELECT sum(d), avg(d) FROM agg_big;
RESET max_parallel_workers_per_gather;
SELECT sum(d), avg(d) FROM agg_big;
RESET parallel_setup_cost;
RESET parallel_tuple_cost;
RESET min_parallel_table_scan_size;
DROP TABLE agg_t, agg_big;
