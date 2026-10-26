-- range types nanotstzrange / nanotsrange (added in 0.3.0)
SET timezone = 'Asia/Taipei';
SET extra_float_digits = 0;

-- types, subtypes and multirange types created by CREATE TYPE ... AS RANGE
SELECT r.rngtypid::regtype, r.rngsubtype::regtype, r.rngmultitypid::regtype,
       r.rngcanonical, r.rngsubdiff
FROM pg_range r WHERE r.rngsubtype::regtype::text LIKE 'nano%' ORDER BY 1::text;

-- text I/O keeps all 9 fractional digits; bounds and empty ranges
SELECT '[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange;
SELECT '(2026-10-26 09:00:00.123456789, 2026-10-26 09:00:01]'::nanotsrange;
SELECT '[2026-10-26 09:00:00.000000005+08, 2026-10-26 09:00:00.000000005+08)'::nanotstzrange AS empty_range;
SELECT '(,2026-10-26 09:00:00.000000001+08)'::nanotstzrange AS unbounded_lower;
SELECT nanotstzrange('2026-10-26 09:00:00.000000002+08', '2026-10-26 09:00:00.000000001+08');  -- error: lower > upper

-- constructors accept the 8-byte type and timestamptz through implicit casts
SELECT nanotstzrange('2026-10-26 09:00:00.000000001+08'::nanotimestamptz8,
                     '2026-10-26 09:00:00.000000009+08'::nanotimestamptz8) AS from_8byte;
SELECT nanotstzrange('2026-10-26 09:00:00+08'::timestamptz, '2026-10-26 10:00:00+08'::timestamptz, '[]') AS from_timestamptz;

-- lower / upper / isempty / bound flags
SELECT lower(r), upper(r), isempty(r), lower_inc(r), upper_inc(r), lower_inf(r), upper_inf(r)
FROM (VALUES ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange),
             ('(,2026-10-26 09:00:00+08]'::nanotstzrange),
             ('empty'::nanotstzrange)) v(r);

-- nanosecond boundary: [t, t+1ns) and [t+1ns, ...) touch but do not overlap
SELECT a && b AS overlaps, a -|- b AS adjacent, a << b AS strictly_left, b >> a AS strictly_right,
       a &< b AS not_extend_right, b &> a AS not_extend_left
FROM (SELECT '[2026-10-26 09:00:00.000000000+08, 2026-10-26 09:00:00.000000001+08)'::nanotstzrange AS a,
             '[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange AS b) s;
-- including the upper bound makes them share exactly one nanosecond
SELECT a && b AS overlaps, a -|- b AS adjacent, a * b AS intersection
FROM (SELECT '[2026-10-26 09:00:00.000000000+08, 2026-10-26 09:00:00.000000001+08]'::nanotstzrange AS a,
             '[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange AS b) s;
-- ranges differing only at the nanosecond level are different values
SELECT '[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange
     = '[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000003+08)'::nanotstzrange AS same,
       '[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange
     < '[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000003+08)'::nanotstzrange AS sorts_first;

-- containment of ranges and of elements (element given as nanotimestamptz)
SELECT r @> '2026-10-26 09:00:00.000000001'::nanotimestamptz AS has_1ns,
       r @> '2026-10-26 09:00:00.000000002'::nanotimestamptz AS has_2ns,
       '(2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange <@ r AS sub,
       r @> 'empty'::nanotstzrange AS has_empty
FROM (SELECT '[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange AS r) s;

-- union, intersection, difference
SELECT a + b AS union_, a * b AS intersection, a - b AS difference
FROM (SELECT '[2026-10-26 09:00:00.000000000+08, 2026-10-26 09:00:00.000000005+08)'::nanotstzrange AS a,
             '[2026-10-26 09:00:00.000000003+08, 2026-10-26 09:00:00.000000009+08)'::nanotstzrange AS b) s;
SELECT '[2026-10-26 09:00:00.000000000+08, 2026-10-26 09:00:00.000000001+08)'::nanotstzrange
     + '[2026-10-26 09:00:00.000000002+08, 2026-10-26 09:00:00.000000003+08)'::nanotstzrange;  -- error: not contiguous
SELECT range_merge('[2026-10-26 09:00:00.000000000+08, 2026-10-26 09:00:00.000000001+08)'::nanotstzrange,
                   '[2026-10-26 09:00:00.000000002+08, 2026-10-26 09:00:00.000000003+08)'::nanotstzrange);

-- the length of a range is upper - lower, a nanointerval (no canonical function: continuous like tstzrange)
SELECT upper(r) - lower(r) AS length
FROM (SELECT '[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange AS r) s;

-- subtype_diff: seconds as float8, same unit as tstzrange_subdiff
SELECT nanotimestamptz_subdiff('2026-10-26 09:00:00.000000003+08', '2026-10-26 09:00:00+08') AS three_ns,
       nanotimestamptz_subdiff('2026-10-26 09:00:00+08', '2026-10-26 10:00:00.5+08') AS minus_3600_5_s,
       nanotimestamp_subdiff('2026-10-26 09:00:01', '2026-10-26 09:00:00.999999999') AS one_ns_notz,
       tstzrange_subdiff('2026-10-26 10:00:00+08', '2026-10-26 09:00:00+08') AS builtin_tstz;

-- multiranges and range_agg
SELECT range_agg(r) FROM (VALUES
  ('[2026-10-26 09:00:00.000000000+08, 2026-10-26 09:00:00.000000003+08)'::nanotstzrange),
  ('[2026-10-26 09:00:00.000000003+08, 2026-10-26 09:00:00.000000005+08)'),
  ('[2026-10-26 09:00:00.000000007+08, 2026-10-26 09:00:00.000000009+08)')) v(r);
SELECT range_intersect_agg(r) FROM (VALUES
  ('[2026-10-26 09:00:00.000000000+08, 2026-10-26 09:00:00.000000005+08)'::nanotstzrange),
  ('[2026-10-26 09:00:00.000000003+08, 2026-10-26 09:00:00.000000009+08)')) v(r);
SELECT m, m @> '2026-10-26 09:00:00.000000004+08'::nanotimestamptz AS has_4ns,
       m @> '2026-10-26 09:00:00.000000006+08'::nanotimestamptz AS has_6ns,
       m - nanotstzmultirange('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000008+08)'::nanotstzrange) AS minus,
       range_merge(m) AS merged
FROM (SELECT nanotstzmultirange('[2026-10-26 09:00:00.000000000+08, 2026-10-26 09:00:00.000000005+08)',
                                '[2026-10-26 09:00:00.000000007+08, 2026-10-26 09:00:00.000000009+08)') AS m) s;
SELECT '{[2026-10-26 09:00:00.1, 2026-10-26 09:00:00.2), [2026-10-26 09:00:00.2, 2026-10-26 09:00:00.3)}'::nanotsmultirange;
SELECT pg_typeof(range_agg(r)) FROM (VALUES (nanotsrange('2026-10-26 09:00:00', '2026-10-26 09:00:01'))) v(r);
SELECT u FROM unnest('{[2026-10-26 09:00:00.000000001+08,2026-10-26 09:00:00.000000002+08),[2026-10-26 09:00:00.000000003+08,)}'::nanotstzmultirange) u;

-- binary I/O round trip
CREATE TEMP TABLE rng_bin (r nanotstzrange, m nanotstzmultirange, n nanotsrange);
INSERT INTO rng_bin VALUES ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)',
  '{[2026-10-26 09:00:00.000000001+08,2026-10-26 09:00:00.000000002+08),[2026-10-26 09:00:00.000000003+08,)}',
  '(2026-10-26 09:00:00.123456789, 2026-10-26 09:00:01]');
SELECT '/tmp/pg_nanotime_regress_range_' || current_setting('port') || '.bin' AS binfile \gset
COPY rng_bin TO :'binfile' WITH (FORMAT binary);
CREATE TEMP TABLE rng_bin2 (LIKE rng_bin);
COPY rng_bin2 FROM :'binfile' WITH (FORMAT binary);
SELECT a.r = b.r AND a.m = b.m AND a.n = b.n AS copy_binary_round_trip FROM rng_bin a, rng_bin2 b;

-- booking: no double booking of the same room/instrument, enforced with EXCLUDE USING gist
CREATE EXTENSION btree_gist;
CREATE TEMP TABLE booking (
  room   text,
  during nanotstzrange,
  EXCLUDE USING gist (room WITH =, during WITH &&)
);
INSERT INTO booking VALUES
  ('A', '[2026-10-26 09:00:00+08, 2026-10-26 10:00:00+08)'),
  ('A', '[2026-10-26 10:00:00+08, 2026-10-26 11:00:00+08)'),   -- back to back: allowed
  ('B', '[2026-10-26 09:30:00+08, 2026-10-26 10:30:00+08)');   -- other room: allowed
INSERT INTO booking VALUES ('A', '[2026-10-26 09:59:59.999999999+08, 2026-10-26 10:30:00+08)');  -- overlaps by 1 ns: rejected
INSERT INTO booking VALUES ('A', '[2026-10-26 11:00:00+08, 2026-10-26 11:00:00.000000001+08)'); -- 1 ns slot right after: allowed
SELECT room, during, upper(during) - lower(during) AS length FROM booking ORDER BY room, during;

-- GiST index is used for && and @> on a larger table; ANALYZE uses subtype_diff for range statistics
CREATE TEMP TABLE windows AS
SELECT i, nanotstzrange(t, t + '500 ns'::nanointerval) AS w
FROM generate_series('2026-10-26 09:00:00+08'::nanotimestamptz, '2026-10-26 09:00:00.000099999+08', '1 us'::nanointerval)
     WITH ORDINALITY AS g(t, i);
CREATE INDEX ON windows USING gist (w);
ANALYZE windows;
SET enable_seqscan = off;
EXPLAIN (COSTS OFF)
SELECT i FROM windows WHERE w && '[2026-10-26 09:00:00.000010400+08, 2026-10-26 09:00:00.000010600+08)'::nanotstzrange;
SELECT i, w FROM windows WHERE w && '[2026-10-26 09:00:00.000010400+08, 2026-10-26 09:00:00.000010600+08)'::nanotstzrange ORDER BY i;
EXPLAIN (COSTS OFF)
SELECT i FROM windows WHERE w @> '2026-10-26 09:00:00.000020499+08'::nanotimestamptz;
SELECT i FROM windows WHERE w @> '2026-10-26 09:00:00.000020499+08'::nanotimestamptz;  -- inside
SELECT i FROM windows WHERE w @> '2026-10-26 09:00:00.000020500+08'::nanotimestamptz;  -- upper bound excluded: none
RESET enable_seqscan;
SELECT count(*) AS stats_rows FROM pg_stats
WHERE tablename = 'windows' AND attname = 'w' AND range_length_histogram IS NOT NULL;

-- B-tree ordering, hash grouping and DISTINCT on ranges
SELECT r FROM (VALUES
  ('[2026-10-26 09:00:00.000000002+08,)'::nanotstzrange),
  ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000003+08)'),
  ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'),
  ('empty')) v(r) ORDER BY r;
SET enable_sort = off;
SELECT count(DISTINCT r) AS distinct_ranges, count(*) AS rows_ FROM (VALUES
  ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange),
  ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'),
  ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000003+08)')) v(r);
SELECT r, count(*) FROM (VALUES
  ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange),
  ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'),
  ('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000003+08)')) v(r) GROUP BY r ORDER BY r;
RESET enable_sort;
SELECT hash_range('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange)
     = hash_range('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange) AS hash_stable,
       hash_range('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000002+08)'::nanotstzrange)
     = hash_range('[2026-10-26 09:00:00.000000001+08, 2026-10-26 09:00:00.000000003+08)'::nanotstzrange) AS hash_equal_if_ns_differs;

DROP TABLE booking, windows, rng_bin, rng_bin2;
DROP EXTENSION btree_gist;
