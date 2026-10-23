set timezone='UTC';
insert into h1 values ('1969-12-31 12:00:00.000000001 +0000',1),('1960-05-01 00:00:00 +0000',2),('1970-01-01 00:00:00 +0000',3),('2024-01-01 00:00:00.123456789 +0000',4),('2024-01-02 06:00:00 +0000',5),('2024-01-03 06:00:00 +0000',6);
insert into h2 select * from h1;
select hypertable_name, chunk_name, range_start_integer, range_end_integer from timescaledb_information.chunks where hypertable_name in ('h1','h2') order by 1,3;
explain (costs off) select * from h1 where t >= '2024-01-02 00:00:00 +0000' and t < '2024-01-03 00:00:00 +0000';
explain (costs off) select * from h2 where t >= '2024-01-02 00:00:00 +0000' and t < '2024-01-03 00:00:00 +0000';
explain (costs off) select * from h1 where t < '1970-01-01 00:00:00 +0000';
select * from h1 where t < '1970-01-01 00:00:00 +0000' order by t;
-- 3 time_bucket
select time_bucket(86400000000000, t) from h1 limit 1;
select time_bucket(interval '1 day', t) from h1 limit 1;
select time_bucket(86400000000000::bigint, t::bigint)::timestamp9 b, count(*) from h1 group by 1 order by 1;
