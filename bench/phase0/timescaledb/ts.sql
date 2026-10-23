set timezone='UTC';
create extension if not exists timestamp9; create extension if not exists timescaledb;
-- 1a plain
create table h1(t timestamp9 not null, v int);
select create_hypertable('h1','t', chunk_time_interval => 86400000000000);
-- 1b new API
create table h1b(t timestamp9 not null, v int);
select create_hypertable('h1b', by_range('t', 86400000000000));
-- 1c with partitioning func
create function t9_to_ns(timestamp9) returns bigint language sql immutable as 'select $1::bigint';
create table h2(t timestamp9 not null, v int);
select create_hypertable('h2','t', chunk_time_interval => 86400000000000, time_partitioning_func => 't9_to_ns');
create table h2b(t timestamp9 not null, v int);
select create_hypertable('h2b', by_range('t', 86400000000000, partition_func => 't9_to_ns'));
select hypertable_name, column_name, column_type, time_interval, integer_interval, integer_now_func from timescaledb_information.dimensions;
