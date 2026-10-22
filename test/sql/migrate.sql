SET timezone = 'UTC';
-- A domain named timestamp9 over bigint stands in for the real timestamp9
-- type: its column cast to bigint is the same ns-since-1970 value that
-- timestamp9's binary bigint cast returns. (The real extension was tested
-- separately; see README.)
CREATE DOMAIN timestamp9 AS bigint;
SELECT nanotime_migration_expr('timestamp9', 'nanotimestamptz', 't');
SELECT nanotime_migration_expr('timestamp9', 'nanotimestamptz8', 't');
SELECT nanotime_migration_expr('bigint', 'nanotimestamptz8', 'T x');
SELECT nanotime_migration_expr('timestamptz', 'nanotimestamp', 't');
SELECT nanotime_migration_expr('timestamp', 'nanotimestamptz', 't');
SELECT nanotime_migration_expr('text', 'nanotimestamptz', 't');
SELECT nanotime_migration_expr('bigint', 'timestamptz', 't');

CREATE TABLE m9(id int PRIMARY KEY, t timestamp9 NOT NULL DEFAULT 1704067200000000000, v int);
INSERT INTO m9 SELECT g, 1704067200000000000 + g::bigint * 1000000007, g FROM generate_series(1, 1000) g;
-- values a wrapped timestamp9 can contain: '1500-01-01' stored as 2084-07-20..., plus range ends and pre-1970
INSERT INTO m9 VALUES (-1, 3614974473709551616, -1), (-2, -1, -2), (-3, -9223372036854775808, -3), (-4, 9223372036854775807, -4);
CREATE INDEX m9_t ON m9(t);
CREATE UNIQUE INDEX m9_tid ON m9(t, id);
CREATE INDEX m9_h ON m9 USING hash(t);
CREATE TABLE m9_snap AS SELECT id, t::bigint AS ns FROM m9;
SELECT nanotime_suspect_count('m9', 't');
SELECT nanotime_suspect_count('m9', 't', '2024-01-01+00', '2024-01-02+00');
CALL nanotime_migrate_column('m9', 't', dry_run => true);
-- default 1704067200000000000::timestamp9 cannot be cast: clear error and hint
CALL nanotime_migrate_column('m9', 't');
CALL nanotime_migrate_column('m9', 't', new_default => 'clock_ns()');
\d m9
SELECT count(*) FILTER (WHERE m.t = s.ns::nanotimestamptz AND m.t::bigint = s.ns) AS exact, count(*) FROM m9 m JOIN m9_snap s USING (id);
SELECT id, t FROM m9 WHERE id < 0 ORDER BY t;
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT id FROM m9 WHERE t = '2024-01-01 00:00:01.000000007+00';
SELECT id FROM m9 WHERE t = '2024-01-01 00:00:01.000000007+00';
RESET enable_seqscan;
-- nanotimestamptz -> nanotimestamptz8 keeps the indexes and the default
CALL nanotime_migrate_column('m9', 't', 'nanotimestamptz8');
\d m9
SELECT count(*) FILTER (WHERE m.t::bigint = s.ns) AS exact, count(*) FROM m9 m JOIN m9_snap s USING (id);

-- bigint ns -> nanotimestamptz8 (binary-compatible) and -> nanotimestamptz
CREATE TABLE mb(id int, ns bigint, ns2 bigint);
INSERT INTO mb VALUES (1, -1, -1), (2, 0, 0), (3, 1704067200123456789, 1704067200123456789), (4, -9223372036854775808, 9223372036854775807);
CREATE INDEX ON mb USING brin(ns);
CALL nanotime_migrate_column('mb', 'ns', 'nanotimestamptz8');
CALL nanotime_migrate_column('mb', 'ns2');
SELECT id, ns, ns2, ns::bigint FROM mb ORDER BY id;

-- timestamptz (microseconds) -> nanotimestamptz, nanotimestamptz8; timestamp -> nanotimestamp
CREATE TABLE mt(id int, a timestamptz DEFAULT now(), b timestamptz, c timestamp);
INSERT INTO mt VALUES (1, '1969-12-31 23:59:59.999999+00', '2024-01-01 00:00:00.000001+00', '2024-01-01 12:00:00.5'),
                      (2, '0001-01-01 00:00:00+00 BC', '1677-09-21 00:12:43.145225+00', '4714-11-24 00:00:00 BC');
CREATE INDEX ON mt(a);
CALL nanotime_migrate_column('mt', 'a');
CALL nanotime_migrate_column('mt', 'b', 'nanotimestamptz8');
CALL nanotime_migrate_column('mt', 'c', 'nanotimestamp');
\d mt
SELECT * FROM mt ORDER BY id;
-- out of range for the compact type: the ALTER fails, the table is unchanged
INSERT INTO mt VALUES (3, now(), '2024-01-01+00', '2024-01-01');
CALL nanotime_migrate_column('mt', 'a', 'nanotimestamptz8');
SELECT format_type(atttypid, NULL) FROM pg_attribute WHERE attrelid = 'mt'::regclass AND attname = 'a';
-- missing column
CALL nanotime_migrate_column('mt', 'zz');
