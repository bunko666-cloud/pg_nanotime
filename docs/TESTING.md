# pg_nanotime 測試報告

這份文件整理到目前為止所有的測試：回歸測試、與 timestamp9 的行為比較、TimescaleDB 相容性、效能基準測試、遷移與並行測試。文中數字全部取自實際執行的紀錄，沒有估算值。只跑過一次的數字會標明，雜訊較大的也會說明。測試日期都是 2026-10-23（Asia/Taipei）。

## 1. 測試環境

| 項目 | 內容 |
|---|---|
| 機器 | 共享 KVM 虛擬機，8 vCPU Intel Xeon（時鐘源 kvm-clock），15 GiB RAM |
| 作業系統 | Debian 13，Linux 6.12 |
| PostgreSQL | 17.11 與 18.6（PGDG 套件，gcc 14.2.0） |
| TimescaleDB | 2.31.0（Timescale 官方套件） |
| timestamp9 | 1.4.0，commit 2d689f8，CMake 建置（只裝在 PG 18） |
| 編譯 | PGXS，PG 17 與 18 都是 0 警告 |
| pg_nanotime commit | Phase 1：4fa53d5、5d4e08f；Phase 2：0df79e0、da6916d、b99b2f7；Phase 3：eddc1f3（文件更新在其後的 commit） |
| 核心 TAI 偏移 | 0 秒（這台機器沒有設定，見 §8） |

這是共享虛擬機，同一個測試重跑一次常有 10–20% 的差距，偶爾會出現明顯的異常值。只差幾個百分點的結果請視為打平。

## 2. 回歸測試（pg_regress）

### 執行方式

```sh
make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
sudo make install PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
make installcheck PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config PGHOST=/tmp PGPORT=5432 PGUSER=postgres
# 加跑 TimescaleDB 測試（伺服器需要已安裝 TimescaleDB，並已加入 shared_preload_libraries）：
make installcheck WITH_TIMESCALEDB=1 ...
```

`.so` 檔依 PG 版本編譯，換版本測試前要先 `make clean` 再重新編譯、安裝。

### 各測試檔涵蓋範圍

| 測試 | 內容 |
|---|---|
| `basic` | 儲存格式、範圍上下界與越界錯誤、1677/2262 以外與 1970 以前的值、比較、聚合 |
| `io` | 1/9/10 位小數、ISO `T`/`Z`、多個時區、與 timestamptz ISO 輸出一致、負值、text 與 binary 往返（COPY） |
| `casts` | timestamptz floor 取整、infinity 報錯、bigint 極值與 ±1 ns 越界、隱式轉型被拒 |
| `clocks` | `clock_ns`/`now_ns`/`statement_ns` 的易變性、交易內不變、`now_ns() >= now()`、作為 DEFAULT |
| `index` | B-tree 範圍與排序（含兩端極值）、hash 等值與 hash join、BRIN |
| `compact` | 8 B `nanotimestamptz8`：範圍、越界錯誤訊息、轉型、索引、時鐘函數 |
| `interval` | `nanointerval` I/O、單位、ISO 格式、溢位、運算子、與 interval/bigint 轉型 |
| `arith` | `ts − ts`、`ts ± nanointerval`、`ts ± interval`（DST）、溢位 |
| `bucket` | `time_bucket_ns`（1970 以前、origin、夾到最小值）、`date_trunc`、`extract_ns` |
| `notz` | `nanotimestamp`：I/O、DST 缺口、索引、轉型（與核心 timestamp/timestamptz 的 DST 行為比對）、`timezone()`、算術 |
| `migrate` | 遷移輔助函數：運算式、可疑值計數、dry_run、預設值處理、逐位元比對、索引重建、失敗時不變更 |
| `monotonic` | `clock_ns_monotonic`：20 萬次呼叫嚴格遞增、模擬時鐘倒退 2 秒、監控計數、權限、`nanotime.clock_source` |
| `global` | `clock_ns_global`：有 preload 時（`global.out`）測 20 萬次嚴格遞增；沒有 preload 時（`global_1.out`）測錯誤訊息 |
| `range`（0.3.0） | `nanotstzrange`／`nanotsrange`／multirange：I/O、奈秒邊界的相鄰與重疊、只差 1 ns 的範圍、聯集／交集／差集、`range_agg`、subtype_diff 精度、COPY binary、`EXCLUDE USING gist` 擋下只重疊 1 ns 的預約、GiST 計畫、B-tree／hash |
| `timescale_missing`（0.3.0） | 沒有 TimescaleDB 時 `nanotime_timescale_setup`／`nanotime_drop_chunks` 的錯誤與提示；兩個函式不依賴其他擴充 |
| `timescale`（選用） | 分區映射的飽和、`ns()`、`nanotime_now_int8`、16 B 與 8 B hypertable、排除 chunk、drop_chunks、保留策略；0.3.0：一鍵設定三種型別、chunk 與 `(t DESC)` 索引（含沿用既有索引）、`ORDER BY t DESC LIMIT` 走索引、保留策略、`nanotime_drop_chunks`（含原生 8 B 維度與 1677 年以前的邊界）、錯誤情況 |

### 結果

| 階段 | PG 17.11 | PG 18.6 |
|---|---|---|
| Phase 1（5 個測試） | — | 連續 3 次 5/5 通過 |
| Phase 1 加入 8 B 型別（6 個） | 3 次 6/6 | 3 次 6/6 |
| Phase 2 第一批（9 個） | 3 次 9/9 | 3 次 9/9 |
| Phase 2 完成（11 個） | 3 次 11/11 | 3 次 11/11 |
| Phase 3（14 個，含 timescale，有 preload） | 3 次 14/14 | 3 次 14/14 |
| 0.3.0 範圍型別（18 個，有 preload，不含 timescale；2026-10-26） | 1 次 18/18 | 1 次 18/18 |
| 0.3.0 TimescaleDB 一鍵設定（20 個，含 timescale，TimescaleDB 2.31.0，有 preload；2026-10-26） | 1 次 20/20 | 1 次 20/20 |

`global_1.out`（沒有 preload）只在 PG 18 實際產生並比對過。

過程中發現並已修正的問題：
- `-9223372036854775808` ns 轉 bigint 時，中間值會誤報溢位。
- 測試把文件寫的「4713 BC」誤當下界，實際的公曆輸出是 4714-11-24 BC。
- 兩台伺服器共用 `/tmp` 下同名的 COPY 檔，造成權限衝突（環境問題）。
- SQL 函式名 `interval` 是保留字。
- 整數字面值乘 nanointerval 有歧義，已加上 int4 版本的運算子。
- 遷移程序原本會丟掉欄位的預設值，現在改為保留，無法轉換時報錯並附提示。
- 0.3.0：subtype_diff 最初把秒與奈秒分開轉成 float8，`1 s - 0.999999999 s` 得到 `9.99999971718069e-10` 而不是 `1e-09`；改為先在 int128 精確相減再轉換。

## 3. timestamp9 1.4.0 行為紀錄

這是設計 pg_nanotime 時對 timestamp9 現況所做的實測紀錄，用來決定新型別的範圍檢查與取整規則。腳本：`bench/phase0/timestamp9_boundaries.sql`，session 時區為 UTC。

| 指令 | 輸出 | 說明 |
|---|---|---|
| `(-9223372036854775808)::bigint::timestamp9` | 1677-09-21 00:12:43.145224192 +0000 | 下界 |
| `9223372036854775807::bigint::timestamp9` | 2262-04-11 23:47:16.854775807 +0000 | 上界 |
| `(-1)::bigint::timestamp9` | 1969-12-31 23:59:59.999999999 +0000 | 1970 年以前可正常使用 |
| `'1677-09-21 00:12:43.145224191 +0000'::timestamp9` | 2262-04-11 23:47:16.854775807 +0000 | 超出範圍的值會繞回 |
| `'2262-04-11 23:47:16.854775808 +0000'::timestamp9` | 1677-09-21 00:12:43.145224192 +0000 | 同上 |
| `'1500-01-01 00:00:00 +0000'::timestamp9` | 2084-07-20 23:34:33.709551616 +0000 | 同上，從 timestamptz 或 date 轉入時也一樣 |
| `'3000-01-01 00:00:00 +0000'::timestamp9` | 1830-11-23 00:50:52.580896768 +0000 | 同上 |
| `(-1)::bigint::timestamp9::timestamptz` | 1970-01-01 00:00:00+00 | 轉成微秒時往 0 取整 |
| `'1900-01-01 00:00:00.000000001 +0000'::timestamp9::timestamptz` | 1900-01-01 00:00:00.000001+00 | 同上（1970 年以前會往上進位） |
| `(-1)::bigint::timestamp9::date` | 1970-01-01 | 同上 |
| `9223372036854775807::bigint::timestamp9 + interval '1 microsecond'` | 1677-09-21 00:12:43.145225191 +0000 | 加減運算超出範圍時會繞回 |
| `timestamp9 - timestamp9` | ERROR: operator does not exist | 沒有差值運算子 |
| 函數名稱含 now、clock、current 的函數 | 0 個（共 25 個函數） | 沒有產生目前時間的函數 |

timestamp9 的範圍其實涵蓋 1970 年以前；它 README 中「最小值 1970」的說法與實測不符。

pg_nanotime 的對應做法：所有輸入、轉型、算術超出範圍時都會報 out of range 錯誤（`ERRCODE_DATETIME_VALUE_OUT_OF_RANGE`）；轉成微秒或日期時一律用 floor（往負無限大取整）。

## 4. TimescaleDB 相容性

### timestamp9 作為對照組（TimescaleDB 2.31.0、PG 18.6）

| 項目 | 結果 |
|---|---|
| 不加分區函數直接建 hypertable | 可以，被視為整數維度 |
| 1970 年以前的 chunk、排除 chunk、壓縮 | 正常 |
| `time_bucket(bigint, t)` | 函數不存在；`time_bucket(..., t::bigint)` 可用 |
| 連續聚合 | 不支援（time bucket 必須直接引用維度欄位；有自訂分區函數時也不支援） |
| `set_integer_now_func` | 必須設分區函數才可以 |
| `drop_chunks`、保留策略 | 參數只能用 bigint |

### pg_nanotime 型別

| 項目 | `nanotimestamptz8`（8 B） | `nanotimestamptz` / `nanotimestamp`（16 B） |
|---|---|---|
| 建立 hypertable | 不需分區函數就可以（`by_range('t', ns('1 day'))`） | 要用 `partition_func => 'nanotime_part'`（無時區版本用 `nanotime_part_notz`） |
| 排除 chunk（壓縮前後） | 只掃描 1 個 chunk | 只掃描 1 個 chunk |
| 1677/2262 以外的值 | 寫入時就會報錯（型別範圍） | 映射飽和到 int64 兩端，落入兩端的 chunk，查詢正常 |
| `set_integer_now_func(nanotime_now_int8)` | 需要 `partition_func => 'nanotime_part8'`（恆等映射）；沒有的話報 custom time function not supported | 可以 |
| `drop_chunks`、`add_retention_policy` | 可以，參數用 `ns('...')` 或 `nanotime_part8(...)` | 可以 |
| 壓縮 | 可以（ColumnarScan 仍能排除 chunk） | 可以（以 ns16 原型測試） |
| `time_bucket` | 不接受此型別；請改用 `time_bucket_ns` 或 `time_bucket(bigint, t::bigint)` | 同左 |
| 連續聚合 | 不支援 | 不支援 |

需要連續聚合時，請把時間另外存成 bigint 欄位。完整用法見 [TIMESCALEDB.md](TIMESCALEDB.md)。

分區函數邊界（ns16 原型）：輸入低於 1677 下界 1 ns 時輸出 INT64_MIN，高於 2262 上界 1 ns 時輸出 INT64_MAX。西元 1 年與 9999 年分別飽和到兩端。各 100 萬筆隨機值排序後比對，遞減次數都是 0。正式版的 `nanotime_part` 在 `timescale` 回歸測試中驗證了相同的邊界。

補充（2026-10-26，TimescaleDB 2.31.0、PG 17.11 與 18.6）：不設分區函數的 8 B hypertable，`add_retention_policy` 可以建立，但用 `run_job` 執行時報 `interval field value out of range: "86400000000000"`；設了 `nanotime_part8` 與 `set_integer_now_func` 後保留策略正常刪除。

### 一鍵設定 `nanotime_timescale_setup`（0.3.0，TimescaleDB 2.31.0、PG 17.11 與 18.6）

由 `timescale` 回歸測試驗證（各跑 1 次，20/20 通過）：

- 三種型別各建一張表：分區函數分別是 `nanotime_part`／`nanotime_part_notz`／`nanotime_part8`，chunk 間隔與 `integer_now_func` 正確寫入 TimescaleDB 目錄。
- 4320 列（3 天）→ 3 個 chunk，每個 chunk 只有 `(t DESC)` 一個索引；`ORDER BY t DESC LIMIT 3` 的計畫走索引、沒有 Sort／Seq Scan，範圍查詢也走索引。已有 `(t)` 索引的表沿用既有索引。
- `nanotime_drop_chunks`：`older_than`、`newer_than` 各刪 1 個 chunk；早於 1677 年的 `older_than` 回傳 0 列、不報錯；原生 8 B 維度（手動 `by_range`）也能刪；`add_retention_policy` + `run_job` 刪光過期資料。
- 錯誤：已經是 hypertable、型別不符、欄位不存在、chunk 為 0、不是 hypertable、表非空（TimescaleDB 的錯誤與提示），`migrate_data => true` 可處理非空表。
- 沒有 TimescaleDB 的錯誤路徑在一般測試 `timescale_missing`（CI 的 PG17／18 job 都會跑）。
- 案例 7 頁面另以 100 萬列在 PG 18.6 重跑：一分鐘範圍查詢為 Index Scan，`ORDER BY ts DESC LIMIT 5` 只打開 1 個 chunk 並走 `readings_ts_idx`。

## 5. 效能基準測試

設定：PG 18.6，shared_buffers 2GB、maintenance_work_mem 1GB，關閉平行查詢，unlogged 表 `(t, v int)`。10M 列取 3 次乾淨執行的中位數；50M 列只跑 1 次。腳本：`bench/phase0/bench_types.sh`。表中的 ns16 是與正式版佈局相同的原型。

### 10M 列

| 項目 | bigint | timestamptz | timestamp9 | ns16 | uuid |
|---|---|---|---|---|---|
| 表大小 (MiB) | 422.3 | 422.3 | 422.3 | 497.6 | 497.6 |
| B-tree 大小 (MiB) | 214.2 | 203.3 | 214.2 | 300.8 | 300.8 |
| BRIN 大小 (KiB) | 32 | 32 | 不支援 | 40 | 40 |
| 批次 INSERT (ms) | 4387 | 7214 | 4360 | 4944 | 8615 |
| 建 B-tree (ms) | 2008 | 2232 | 1746 | 1947 | 2222 |
| 建 BRIN (ms) | 881 | 897 | 不支援 | 920 | 997 |
| ORDER BY 全表 (ms) | 741 | 765 | 733 | 880 | 1109 |
| 點查詢 (ms，200 次中位數) | 0.074 | 0.078 | 0.109 | 0.091 | 0.083 |
| 1% 範圍掃描 B-tree (ms) | 11.21 | 11.92 | 11.62 | 11.55 | 12.06 |
| 1% 範圍掃描 BRIN (ms) | 13.06 | 13.16 | 不支援 | 13.92 | 13.87 |

### 50M 列（只跑 1 次）

| 項目 | bigint | timestamptz | timestamp9 | ns16 | uuid |
|---|---|---|---|---|---|
| 表大小 (MiB) | 2111.5 | 2111.5 | 2111.5 | 2488.0 | 2488.0 |
| B-tree 大小 (MiB) | 1071.1 | 1016.4 | 1071.1 | 1504.1 | 1504.1 |
| BRIN 大小 (KiB) | 88 | 88 | 不支援 | 136 | 136 |
| 批次 INSERT (ms) | 288883（異常值） | 35833 | 20998 | 26198 | 41796 |
| 建 B-tree (ms) | 13774 | 12670 | 12249 | 13716 | 13562 |
| ORDER BY 全表 (ms) | 4067 | 3949 | 4227 | 4821 | 4788 |
| 1% 範圍掃描 B-tree (ms) | 58.3 | 74.6 | 61.0 | 59.3 | 57.7 |

注意事項：
- INSERT 量測的是 `INSERT ... SELECT` 加上從 bigint 轉型的時間，不是 COPY。
- 50M 列 bigint 的 INSERT 時間明顯異常（可能剛好遇到 checkpoint 或前一輪的清理），不應採用。
- 結論：16 B 的主要代價是空間，表約大 18%，B-tree 約大 40%。寫入與查詢的差距都在雜訊範圍內，排序約慢 15–20%。

### 時鐘函數（每次呼叫的額外成本）

扣除 `count(1)` 基準後的值。Phase 0 是在原型上量測（5M 次、5 次中位數）；Phase 3 用正式版，腳本是 `bench/phase3/cost.sh`。

| 函數 | Phase 0 (ns) | Phase 3：PG 17.11 (ns) | Phase 3：PG 18.6 (ns) |
|---|---|---|---|
| `clock_timestamp()` | 19.2 | 20.2 | 47.6（明顯偏離，視為雜訊） |
| `clock_ns8()`（8 B） | 26.0（bigint 原型） | 19.6 | 19.2 |
| `clock_ns8_monotonic()` | — | 24.8 | 20.2 |
| `clock_ns8_global()`（單一連線） | — | 23.6 | 16.5 |
| `clock_ns()`（16 B） | 36.8 | 38.1 | 39.5 |
| `clock_ns_monotonic()` | — | 35.5 | 31.3 |
| `clock_ns_global()`（單一連線） | — | 40.5 | 39.0 |

單一連線時，monotonic 與 global 的額外成本都在雜訊範圍內。16 B 版本因為要配置記憶體（palloc），每次呼叫大約多 15–20 ns。

## 6. 16 B 佈局比較與 COPY

`ns16 = {int64 sec, int64 nsec}` 對照 `ns128 = 單一 __int128 奈秒`，兩者都是 16 B、傳參考。腳本：`bench/phase0/bench_copy_layout.sh`。

| 10M 列（兩輪，各取 3–5 次中位數） | ns16 | ns128 |
|---|---|---|
| 表 / B-tree / BRIN 大小 | 497.6 MiB / 300.8 MiB / 40 KiB | 相同 |
| 建 B-tree (ms) | 1793 / 2009 | 1783 / 1885 |
| 建 BRIN (ms) | 933 / 938 | 1098 / 928 |
| ORDER BY 全表 (ms) | 556 / 583 | 625 / 571 |
| 1% 範圍 B-tree (ms) | 11.10 / 12.71 | 13.80 / 11.87 |
| 1% 範圍 BRIN (ms) | 13.31 / 14.49 | 14.72 / 13.97 |
| 1% 範圍全表掃描 (ms) | 337.5 / 346.6 | 384.6 / 352.5 |

兩輪的快慢方向不一致，屬於雜訊。最後選擇 sec+nsec，理由是：可攜到 MSVC、沒有對齊問題、text I/O 較簡單。

| 10M 列 COPY FROM（3 次中位數，ms） | text | binary | text 檔大小 (MB) |
|---|---|---|---|
| bigint | 2236 | 1728 | 278.9 |
| timestamptz | 5196 | 2170 | 377.6 |
| timestamp9 | 6616 | 1578 | 438.9 |
| ns16 | 2940 / 2639 | 1926 / 2022 | 288.9 |
| ns128 | 2366 / 2536 | 1927 / 1886 | 278.9 |

原型的 text 格式（`sec.nnnnnnnnn` 或整數奈秒）與正式版的 ISO 8601 格式不同，所以 ns16/ns128 的 text COPY 數字只能當作下限。timestamp9 的 text COPY 較慢，是因為它要解析完整的日期字串。

## 7. 遷移測試

真實的 timestamp9 1.4.0 資料表（PG 18.6）：
- 200,000 列一般資料，另加 4 個邊界值：INT64_MIN（1677）、1969-12-31 23:59:59.999999999、繞回後的 1500-01-01（顯示為 2084-07-20 23:34:33.709551616）、INT64_MAX（2262）。
- 建了 B-tree、unique `(t, id)`、hash 三個索引。

| 步驟 | 結果 |
|---|---|
| `CALL nanotime_migrate_column('trades','t')` | 報錯：舊預設值（timestamp9 常數）無法轉換，並提示使用 `new_default` |
| 加上 `new_default => 'clock_ns()'` | 成功，兩次執行分別約 531 ms 與 505 ms；3 個索引自動重建 |
| 逐列比對 | 200,004/200,004 列的 ns 值與文字輸出完全相同 |
| 之後的查詢計畫 | 範圍查詢使用 Index Scan |
| 再轉成 `nanotimestamptz8` | 200,004 列全部相同，索引與預設值保留 |

**繞回損毀無法可靠偵測。** timestamp9 繞回後的值仍是合法時刻。`nanotime_suspect_count(tbl, col, lo, hi)` 只能統計落在預期時間窗外的列數。用預設窗 1990–2100 時抓到 3 列（1677、1969、2262），繞回後的 2084 值因為落在窗內，沒有被抓到。窗要依資料實際的時間跨度設定。

回歸測試 `migrate` 在 PG 17 上用名為 timestamp9 的 bigint domain 模擬，因為 PG 17 沒有安裝 timestamp9。

## 8. Phase 3：嚴格遞增時鐘的並行測試

腳本：`bench/phase3/concurrency.sh <port> 64 15`。條件：pgbench 64 個連線、8 個執行緒、15 秒。每個交易插入一列，同時呼叫 `clock_ns8_global()`、`clock_ns8_monotonic()`、`clock_ns8()`。

| 項目 | PG 17 第 1 次 | PG 17 第 2 次 | PG 18 第 1 次 | PG 18 第 2 次 |
|---|---|---|---|---|
| 列數 | 3,033,533 | 2,590,012 | 2,494,094 | 2,390,116 |
| `clock_ns8_global()` 重複值 | **0** | **0** | **0** | **0** |
| 各連線內不遞增的次數（global / monotonic） | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |
| 對照：`clock_ns8()` 重複值 | 4 | 5 | 6 | 3 |
| 對照：monotonic 跨連線重複值 | 0 | 0 | 1 | 1 |
| global 遞增 +1 ns 的次數 / 總呼叫次數 | 1,547 / 3,233,538* | 2,040 / 2,590,012 | 1,946 / 2,494,094 | 1,813 / 2,390,116 |
| 與 identity 順序相反的列數 | 35,196 | 44,878 | 37,520 | 38,152 |

\* 第 1 次執行前沒有重設計數器，所以總呼叫次數包含先前回歸測試的呼叫。腳本已改為先重設。

說明：
- `clock_ns_global()` 保證「呼叫順序」嚴格遞增且不重複，不保證與 commit 順序一致。表中「與 identity 順序相反」的列數就是這個差異：先取到時間的交易，可能較晚取得 identity 值或較晚 commit。需要依 commit 順序排序時，請不要依賴這個時間戳。
- `clock_ns_monotonic()` 只保證同一連線內遞增，不同連線之間可能重複（PG 18 兩次各出現 1 筆）。

多連線同時呼叫的總呼叫速率（`bench/phase3/contended.sh`，8 個連線、10 秒、每個交易呼叫 10 萬次）：

| 函數 | PG 17.11 | PG 18.6 |
|---|---|---|
| `clock_ns8()` | 60.76 M 次/秒 | 84.77 M 次/秒 |
| `clock_ns8_monotonic()` | 58.55 M 次/秒 | 84.56 M 次/秒 |
| `clock_ns8_global()` | 17.19 M 次/秒 | 12.23 M 次/秒 |

`clock_ns_global()` 在多個連線同時大量呼叫時，因為共享同一個 cache line 上的 atomic 變數，總速率只剩一般時鐘的約 14–28%。上面的 INSERT 測試每秒約 16–20 萬筆交易，每筆只呼叫一次，遠低於這個上限。不過我們沒有另外跑「不呼叫 global」的對照組，所以這只是推論，並未實際量測。

時鐘倒退：回歸測試用僅限 superuser 的 `nanotime.debug_clock_offset_us` 把時鐘往回撥 2 秒來驗證，結果如下：
- monotonic 仍然嚴格遞增，倒退時取上一個值 +1 ns。
- `nanotime_clock_status()` 記錄 1 次倒退，幅度約 2 秒，lead（領先實際時鐘的量）約 2 秒。
- 一般的 `clock_ns()` 會跟著時鐘倒退。
- 時鐘往前跳不算倒退。
- 切換 `nanotime.clock_source` 也不算倒退。

TAI：這台機器的核心 TAI 偏移是 0，因此 `nanotime.clock_source = tai` 的讀值與 realtime 相同。Linux 預設不會設定 TAI 偏移，通常要由 chrony（`leapsectz`）或 ptp4l/phc2sys 設定；目前約為 37 秒。

## 9. 已知限制

- 不支援 `infinity`/`-infinity`；輸出固定為 ISO 格式，不受 DateStyle 影響。
- `AT TIME ZONE` 和 `EXTRACT` 這兩個語法在 PG 中寫死，擴充套件無法支援。請改用 `timezone(zone, ts)` 與 `extract_ns(field, ts)`。
- `smallint` 乘 nanointerval 時要先轉型，否則會出現 operator is not unique。
- 不帶型別的字串字面值加在時間上（例如 `ts + '1 day'`）會被解析成內建 interval，最小單位是 µs。
- TimescaleDB：不能用連續聚合，`time_bucket` 不接受這些型別。16 B 型別需要分區函數，超出 int64 範圍的值會集中在兩端的 chunk。
- 不支援閏秒。TAI 偏移取決於系統設定。
- `clock_ns_global()` 需要 `shared_preload_libraries`。它的計數器存在共享記憶體，伺服器重啟後會重來，所以如果重啟後系統時鐘比重啟前還慢，跨重啟就不保證遞增。
- 回歸測試涵蓋 PG 17 與 18；timestamp9 的實測只在 PG 18 上做過。
