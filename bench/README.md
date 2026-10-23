# bench/：測試與基準測試腳本

這裡的腳本就是 [docs/TESTING.md](../docs/TESTING.md) 中各項數字所用的腳本，從開發時的暫存目錄原樣保存下來。內容沒有為了好看而修改，所以路徑和連線參數都寫死（`-h /tmp -p 5499 -U postgres`），使用前請自行調整。

| 路徑 | 用途 | 前置條件 |
|---|---|---|
| `phase0/timestamp9_boundaries.sql` | timestamp9 邊界與轉型行為 | timestamp9 1.4.0 |
| `phase0/bench_types.sh N RUN` | 五種型別的寫入、索引、排序、查詢基準（10M 列與 50M 列） | 資料庫 `bench`、timestamp9、`phase0/ns16` 原型 |
| `phase0/bench_copy_layout.sh` | COPY text/binary 與兩種 16 B 佈局的比較 | 同上 |
| `phase0/partition_saturation.sql` | 分區函數的飽和與單調性 | ns16 原型 |
| `phase0/timescaledb/*.sql` | TimescaleDB 相容性（timestamp9、ns16/ns128、nanotimestamptz8） | TimescaleDB 2.31.0 |
| `phase0/ns16/` | 原型擴充（PGXS，只用於基準測試），內含 `ns16`（16 B `{sec, nsec}`）與 `ns128`（單一 `__int128`）兩種型別 | — |
| `phase3/concurrency.sh <port> [clients] [sec]` | pgbench 多連線並行，檢查 `clock_ns8_global()` 是否有重複、是否遞增 | 需要 preload |
| `phase3/cost.sh <port>` | 單一連線的每次呼叫成本 | 要先跑過 concurrency.sh（會建立 `ntconc` 資料庫） |
| `phase3/contended.sh <port> [clients] [sec]` | 多連線同時呼叫的總呼叫速率 | 同上 |

