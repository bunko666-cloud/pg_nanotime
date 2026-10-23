#!/bin/bash
# 多連線同時呼叫：每個交易呼叫 100000 次，比較 clock_ns8() 與 clock_ns8_global() 的總呼叫速率。
# 用法：bench/phase3/contended.sh <port> [clients] [seconds]
PORT=${1:?port}; C=${2:-8}; T=${3:-10}
for f in clock_ns8 clock_ns8_monotonic clock_ns8_global; do
  echo "select count($f()) from generate_series(1,100000);" > /tmp/ntc_$f.sql
  tps=$(pgbench -h /tmp -p $PORT -U postgres -n -c $C -j $C -T $T -f /tmp/ntc_$f.sql ntconc | awk '/^tps/{print $3}')
  python3 -c "print(f'$f x $C clients: {float($tps)*100000/1e6:.2f} M calls/s total')"
done
