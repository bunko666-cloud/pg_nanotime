#!/bin/bash
# 多連線並行測試：clock_ns8_global() 是否零重複、各連線內嚴格遞增。
# 用法：bench/phase3/concurrency.sh <port> [clients] [seconds]
# 需要 shared_preload_libraries 含 pg_nanotime。
set -e
PORT=${1:?port}; C=${2:-64}; T=${3:-15}
P="psql -h /tmp -p $PORT -U postgres -XqAt"
$P -c "drop database if exists ntconc" -c "create database ntconc"
P="$P -d ntconc"
$P -c "create extension pg_nanotime; select nanotime_reset_stats(); create unlogged table gt(id bigint generated always as identity, cid int, g bigint, m bigint, c bigint)"
cat > /tmp/ntconc_$PORT.sql <<'Q'
INSERT INTO gt(cid, g, m, c) VALUES (:client_id, clock_ns8_global()::bigint, clock_ns8_monotonic()::bigint, clock_ns8()::bigint);
Q
pgbench -h /tmp -p $PORT -U postgres -n -c $C -j 8 -T $T -f /tmp/ntconc_$PORT.sql ntconc | grep -E "number of transactions actually|tps"
$P -F ' | ' <<'Q'
select 'rows', count(*) from gt;
select 'global duplicates', count(*) - count(distinct g) from gt;
select 'plain clock_ns8 duplicates (for comparison)', count(*) - count(distinct c) from gt;
select 'monotonic duplicates across clients (expected: may be >0)', count(*) - count(distinct m) from gt;
with d as (select g, lag(g) over (partition by cid order by id) p, m, lag(m) over (partition by cid order by id) pm from gt)
select 'per-client non-increasing global / monotonic', count(*) filter (where g <= p) || ' / ' || count(*) filter (where m <= pm) from d;
with d as (select g, lag(g) over (order by id) p from gt)
select 'cross-client inversions vs identity order (commit/order caveat)', count(*) filter (where g < p) from d;
select 'global bumps / calls', global_bumps || ' / ' || global_calls from nanotime_clock_status();
Q
