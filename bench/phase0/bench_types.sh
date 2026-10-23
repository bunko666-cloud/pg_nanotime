#!/bin/bash
# usage: bench.sh N RUN
N=$1; R=$2
P="psql -h /tmp -p 5499 -U postgres -d bench -qAtX"
declare -A EXPR=( [bigint]="ns" [timestamptz]="to_timestamp(ns/1e9)" [timestamp9]="ns::timestamp9" [ns16]="ns::ns16" [uuid]="(lpad(to_hex(ns),16,'0')||'0000000000000000')::uuid" )
declare -A LIT=( [bigint]="%s" [timestamptz]="to_timestamp(%s/1e9)" [timestamp9]="%s::bigint::timestamp9" [ns16]="%s::bigint::ns16" [uuid]="(lpad(to_hex(%s::bigint),16,'0')||'0000000000000000')::uuid" )
BASE=1700000000000000000
for T in bigint timestamptz timestamp9 ns16 uuid; do
  $P -c "drop table if exists b_$T"
  $P -c "create unlogged table b_$T(t $T not null, v int)"
  ms(){ local s=$(date +%s%N); $P -c "$1" >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )); }
  ins=$(ms "insert into b_$T select ${EXPR[$T]}, i from (select i, $BASE + i::bigint*1000 + (random()*999)::bigint ns from generate_series(1,$N) i) s")
  $P -c "vacuum analyze b_$T"
  bt=$(ms "create index b_${T}_bt on b_$T(t)")
  if [ $T = timestamp9 ]; then br=NA; else br=$(ms "create index b_${T}_br on b_$T using brin(t)"); fi
  $P -c "vacuum analyze b_$T"
  tsz=$($P -c "select pg_relation_size('b_$T')"); btsz=$($P -c "select pg_relation_size('b_${T}_bt')"); brsz=$($P -c "select coalesce(pg_relation_size(to_regclass('b_${T}_br')),0)")
  srt=$(ms "select count(*) from (select t from b_$T order by t desc offset 0) x")
  # point lookups: 200 random, median latency via EXPLAIN ANALYZE
  pt=$(for k in $(seq 1 200); do i=$((RANDOM*RANDOM % N + 1)); v=$(printf "${LIT[$T]}" $((BASE + i*1000))); $P -c "explain (analyze, format json) select * from b_$T where t >= $v order by t limit 1" | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['Execution Time'])"; done | sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}')
  # range scan 1% of rows, btree and brin
  lo=$((BASE + N/2*1000)); hi=$((lo + N/100*1000))
  rq="select count(*) from b_$T where t >= $(printf "${LIT[$T]}" $lo) and t < $(printf "${LIT[$T]}" $hi)"
  rbt=$(for k in 1 2 3 4 5; do $P -c "set enable_bitmapscan=off; set enable_seqscan=off; explain (analyze, format json) $rq" | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['Execution Time'])"; done | sort -n | sed -n 3p)
  [ $T = timestamp9 ] && rbr=NA || rbr=$(for k in 1 2 3 4 5; do $P -c "set enable_indexscan=off; set enable_indexonlyscan=off; set enable_seqscan=off; explain (analyze, format json) $rq" | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['Execution Time'])"; done | sort -n | sed -n 3p)
  echo "$N,$R,$T,$ins,$bt,$br,$tsz,$btsz,$brsz,$srt,$pt,$rbt,$rbr"
done
