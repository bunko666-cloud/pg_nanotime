#!/bin/bash
# 單一連線呼叫成本：每個函式 5M 次，取 5 次中位數，扣除 count(1) 基準。
# 用法：bench/phase3/cost.sh <port>
PORT=${1:?port}; N=5000000
P="psql -h /tmp -p $PORT -U postgres -XqAt -d ntconc"
ms(){ $P -c "explain (analyze, format json, timing off) $1" | python3 -c "import json,sys;print(json.load(sys.stdin)[0]['Execution Time'])"; }
med(){ sort -n | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}'; }
base=$(for i in 1 2 3 4 5; do ms "select count(1) from generate_series(1,$N)"; done | med)
echo "baseline count(1): $base ms"
for f in "clock_timestamp()" "clock_ns8()" "clock_ns8_monotonic()" "clock_ns8_global()" "clock_ns()" "clock_ns_monotonic()" "clock_ns_global()"; do
  m=$(for i in 1 2 3 4 5; do ms "select count($f) from generate_series(1,$N)"; done | med)
  python3 -c "print(f'$f: {($m-$base)*1e6/$N:.1f} ns/call (total $m ms)')"
done
