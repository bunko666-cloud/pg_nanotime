#!/bin/bash
N=10000000
P="psql -h /tmp -p 5499 -U postgres -d bench -qAtX"
ms(){ local s=$(date +%s%N); $P -c "$1" >/dev/null; echo $(( ($(date +%s%N)-s)/1000000 )); }
med(){ sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'; }
ea(){ $P -c "$1 explain (analyze, format json) $2" | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['Execution Time'])"; }
declare -A EXPR=( [bigint]="ns" [timestamptz]="to_timestamp(ns/1e9)" [timestamp9]="ns::timestamp9" [ns16]="ns::ns16" [ns128]="ns::ns128" )
declare -A LIT=( [bigint]="%s" [timestamptz]="to_timestamp(%s/1e9)" [timestamp9]="%s::bigint::timestamp9" [ns16]="%s::bigint::ns16" [ns128]="%s::bigint::ns128" )
BASE=1700000000000000000
mkdir -p /tmp/cp; chmod 777 /tmp/cp
for T in bigint timestamptz timestamp9 ns16 ns128; do
  $P -c "drop table if exists c_$T; create unlogged table c_$T(t $T not null, v int)"
  $P -c "insert into c_$T select ${EXPR[$T]}, i from (select i, $BASE + i::bigint*1000 + (random()*999)::bigint ns from generate_series(1,$N) i) s"
  $P -c "copy c_$T to '/tmp/cp/$T.txt'; copy c_$T to '/tmp/cp/$T.bin' with (format binary)"
  ct=$(for r in 1 2 3; do $P -c "truncate c_$T; checkpoint"; ms "copy c_$T from '/tmp/cp/$T.txt'"; done | med)
  cb=$(for r in 1 2 3; do $P -c "truncate c_$T; checkpoint"; ms "copy c_$T from '/tmp/cp/$T.bin' with (format binary)"; done | med)
  $P -c "vacuum analyze c_$T"
  extra=""
  if [ $T = ns16 ] || [ $T = ns128 ]; then
    bt=$(for r in 1 2 3; do $P -c "drop index if exists c_${T}_bt"; ms "create index c_${T}_bt on c_$T(t)"; done | med)
    br=$(for r in 1 2 3; do $P -c "drop index if exists c_${T}_br"; ms "create index c_${T}_br on c_$T using brin(t)"; done | med)
    $P -c "vacuum analyze c_$T"
    srt=$(for r in 1 2 3; do ms "select count(*) from (select t from c_$T order by t desc offset 0) x"; done | med)
    lo=$((BASE + N/2*1000)); hi=$((lo + N/100*1000))
    rq="select count(*) from c_$T where t >= $(printf "${LIT[$T]}" $lo) and t < $(printf "${LIT[$T]}" $hi)"
    rbt=$(for k in 1 2 3 4 5; do ea "set enable_bitmapscan=off; set enable_seqscan=off;" "$rq"; done | med)
    rbr=$(for k in 1 2 3 4 5; do ea "set enable_indexscan=off; set enable_indexonlyscan=off; set enable_seqscan=off;" "$rq"; done | med)
    seqf=$(for k in 1 2 3 4 5; do ea "set enable_indexscan=off; set enable_indexonlyscan=off; set enable_bitmapscan=off;" "$rq"; done | med)
    extra="$bt,$br,$srt,$rbt,$rbr,$seqf,$($P -c "select pg_relation_size('c_$T')"),$($P -c "select pg_relation_size('c_${T}_bt')"),$($P -c "select pg_relation_size('c_${T}_br')")"
  fi
  echo "$T,$ct,$cb,$(stat -c %s /tmp/cp/$T.txt),$(stat -c %s /tmp/cp/$T.bin),$extra"
done
