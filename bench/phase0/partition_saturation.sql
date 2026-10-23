drop table if exists b_ns16;
-- int64 min/max ns = -9223372036.854775808 / 9223372036.854775807 s
select v, ns16_part(v::ns16) from unnest(array[
 '-9223372036854775808','9223372036854775807','-1','0',
 '-9223372037.145224191','-9223372037.145224192','-9223372036.145224192',
 '9223372036.854775807','9223372036.854775808','9223372037.000000000',
 '-2208988800.000000000','-62135596800.000000000','-210866803200.000000000','253402300799.999999999','9223372036854775807.999999999','-9223372036854775808.000000000']) v;
select v, ns128_part(v::ns128) from unnest(array[
 '-9223372036854775808','-9223372036854775809','9223372036854775807','9223372036854775808','-1','0',
 '-62135596800000000000','253402300799999999999','170141183460469231731687303715884105727','-170141183460469231731687303715884105728']) v;
-- monotonic check: random sorted values spanning +-1e12 seconds
with x as (select ((random()*2-1)*1e12)::bigint s, (random()*999999999)::bigint n from generate_series(1,1000000)),
y as (select format('%s.%s',s,lpad(n::text,9,'0'))::ns16 t from x),
z as (select t, ns16_part(t) p, lag(ns16_part(t)) over (order by t) pp from y)
select count(*) filter (where p < pp) violations, count(*) filter (where p=9223372036854775807) sat_max, count(*) filter (where p=-9223372036854775808) sat_min, count(*) total from z;
with x as (select ((random()*2-1)*1e30)::numeric::text v from generate_series(1,1000000)),
y as (select split_part(v,'.',1)::ns128 t from x),
z as (select t, ns128_part(t) p, lag(ns128_part(t)) over (order by t) pp from y)
select count(*) filter (where p < pp) violations, count(*) filter (where p=9223372036854775807) sat_max, count(*) filter (where p=-9223372036854775808) sat_min, count(*) total from z;
