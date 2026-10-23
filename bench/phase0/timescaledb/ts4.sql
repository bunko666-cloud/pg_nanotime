set timezone='UTC';
create materialized view ca3 with (timescaledb.continuous) as select time_bucket(86400000000000::bigint, t9_to_ns(t)) b, count(*) from h2 group by 1;
create materialized view ca4 with (timescaledb.continuous) as select time_bucket(86400000000000::bigint, t::bigint) b, count(*) from h2 group by 1;
-- 16B proxy: interval column (16 bytes, by-ref) with mapping function
create function iv_to_ns(interval) returns bigint language sql immutable as $$select (extract(epoch from $1)*1e9)::bigint$$;
create table h16(t interval not null, v int);
select create_hypertable('h16','t', chunk_time_interval => 86400000000000);
select create_hypertable('h16', by_range('t', 86400000000000, partition_func => 'iv_to_ns'));
insert into h16 values ('1 day 2 hours',1),('-3 days',2);
select chunk_name, range_start_integer from timescaledb_information.chunks where hypertable_name='h16' order by 2;
explain (costs off) select * from h16 where t > '1 day';
