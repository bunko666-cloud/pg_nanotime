# Changelog

格式參考 [Keep a Changelog](https://keepachangelog.com/)，版本號遵循 [SemVer](https://semver.org/)。

## [Unreleased]

## [0.3.0] - 2026-10-26

升級：`ALTER EXTENSION pg_nanotime UPDATE TO '0.3.0';`（0.1.0 與 0.2.0 都可以直接升級；只支援 PostgreSQL 17 與 18）。

### 新增
- 範圍型別 `nanotstzrange`（子型別 `nanotimestamptz`）與 `nanotsrange`（子型別 `nanotimestamp`），用 PostgreSQL 的 `CREATE TYPE ... AS RANGE` 定義；multirange 型別 `nanotstzmultirange`、`nanotsmultirange` 自動建立。內建的範圍運算子（`&&`、`@>`、`<@`、`-|-`、`<<`、`>>`、`+`、`*`、`-` 等）、`lower`／`upper`／`isempty`、`range_agg`、`range_intersect_agg`、GiST 索引與 `EXCLUDE USING gist`（搭配 `btree_gist`）都可直接使用，不另外自訂運算子。
- subtype_diff 函式 `nanotimestamptz_subdiff`、`nanotimestamp_subdiff`：回傳秒（float8），與內建 `tstzrange_subdiff` 單位相同；先以 int128 奈秒精確相減再轉換，1 ns 的差距也不會因相消而失準。
- 範圍型別是連續型（沒有 canonical 函式），和 `tstzrange` 一致；文件建議一律使用半開區間 `[開始, 結束)`。不提供 8 bytes 版範圍型別（`nanotimestamptz8` 可隱含轉型後直接組成 `nanotstzrange`）。
- 升級腳本 `pg_nanotime--0.2.0--0.3.0.sql`；CI 的升級一致性檢查改為 0.1.0 與 0.2.0 都升級到目前版本，再和全新安裝比對 `\dx+`。
- 回歸測試 `range`（奈秒邊界的相鄰／重疊、只差 1 ns 的範圍、multirange、COPY binary、排他約束、GiST 計畫、B-tree／hash）；`examples` 新增 ex7「共用儀器預約不撞期」，同步到 EXAMPLES.md §7。
- TimescaleDB 一鍵設定 `nanotime_timescale_setup(表, 欄位, chunk, migrate_data)`：依欄位型別選分區函數（`nanotime_part`／`nanotime_part_notz`／`nanotime_part8`），chunk 以奈秒 bigint 傳入 `by_range()`，設定 `set_integer_now_func`（保留策略可用），不建分區運算式上的預設索引，改在沒有等效索引時建立 `(欄位 DESC)`；回傳一行摘要。
- `nanotime_drop_chunks(表, older_than, newer_than)`：直接給 `nanotimestamptz`，自動換成 hypertable 時間維度的值（不用再寫 `::bigint`）。
- 兩個 TimescaleDB 輔助函式都用動態 SQL 呼叫 TimescaleDB，擴充本身不依賴它；沒有安裝時報錯並附提示。需要 TimescaleDB 2.13 以上的 `by_range()` 介面（實測 2.31.0）。
- 回歸測試 `timescale_missing`（一般測試，沒有 TimescaleDB 時的錯誤）；選用測試 `timescale` 加入一鍵設定、chunk 與索引、`ORDER BY t DESC LIMIT` 使用 `(t DESC)` 索引、保留策略、`nanotime_drop_chunks` 與錯誤情況。
- 文件：TECHNICAL.md 新增範圍型別一節與索引矩陣列；GUIDE.md 新增 §9「時段不能重疊」（常見陷阱改為 §10，新增「結束點用 `)`」）；COVERAGE.md 加入新物件（共 305 個）；ROADMAP.md 勾選完成項目；TIMESCALEDB.md 新增「一鍵設定」一節，GUIDE.md §8 改以一鍵設定為主；TECHNICAL.md 記錄原生 8 B 維度的保留策略會在執行時失敗。

## [0.2.0] - 2026-10-23

升級：`ALTER EXTENSION pg_nanotime UPDATE TO '0.2.0';`（只支援 PostgreSQL 17 與 18）。

### 新增
- `sum(nanointerval)`、`avg(nanointerval)` 聚合：int128 精確累加，溢位時報錯 `nanointerval out of range`；`avg` 四捨五入到奈秒（剛好一半時遠離 0，與 `nanointerval / bigint` 一致）；忽略 NULL，沒有資料時回傳 NULL；支援平行查詢與視窗函式移動聚合。新增回歸測試 `agg`。
- 擴充套件版本升到 0.2.0：新增升級腳本 `pg_nanotime--0.1.0--0.2.0.sql`，可用 `ALTER EXTENSION pg_nanotime UPDATE` 從 0.1.0 升級；CI 會檢查升級後與全新安裝的物件一致。
- `abs(nanointerval)`（範圍對稱，最小值也能取負，不會溢位）。
- `generate_series(start, stop, step nanointerval)`，支援 `nanotimestamptz`、`nanotimestamptz8`、`nanotimestamp`：與 PostgreSQL 語意一致（包含 stop、step 0 報錯、負 step 往回數），在型別範圍邊緣不會繞回；附 planner support 函式，常數參數時列數估計精確。
- `nanointerval_from_ns(double precision)`（四捨五入遠離 0；NaN／Infinity 報明確錯誤；超過 2^53 ns 會失去精度，已寫入文件）與精確的 `nanointerval_from_ns(bigint)`（避免整數參數被解析到 double precision 版本）。新增回歸測試 `series`。
- 測試：新增回歸測試 `coverage`，補上 COVERAGE.md 列出的 6 個缺口（`interval + nanotimestamptz`／`nanotimestamptz8`、`nanotimestamptz8 - interval`、`bigint * nanointerval`、`nanointerval / bigint`、其他 3 型別的 `<>`、`percentile_disc` 直接用在 nanointerval）。沒有程式碼變更。
- 文件：新增 `docs/COVERAGE.md` 功能與測試涵蓋表（所有物件、對應回歸測試、驗證版本、案例、缺口、變更影響指南）；CONTRIBUTING 規定功能變更要在同一個 commit 更新它。
- 文件：說明沒有 `numeric → nanointerval` 轉型，請用 `nanointerval_from_ns(numeric)`。
- `tools/check_examples.py` 與 `make check-docs`：檢查 `docs/EXAMPLES.md` 的程式碼區塊與 `examples` 回歸測試逐行一致。
- GitHub Actions「Docs examples」流程：範例文件或測試變動時自動執行上述檢查（不需安裝 PostgreSQL）。

### 修正
- `nanointerval_from_ns('NaN'::numeric)` 與 ±Infinity 改報 `cannot convert NaN to nanointerval`／`cannot convert infinity to nanointerval`，不再是 `nanointerval out of range`。
- 文件：GUIDE.md 誤寫百分位數要先轉 bigint；實際上 `percentile_disc` 可直接用在 `nanointerval`，只有 `percentile_cont` 不行。
- 文件：設了 `partition_func` 的 hypertable，`drop_chunks` 的 `older_than` 必須是 bigint（`::nanotimestamptz8::bigint`）；兩種情況都列出。
- 文件：`nanotime_migrate_column` 的預設目標是 16 B `nanotimestamptz`（bigint 來源也一樣），要 8 B 需傳入 `'nanotimestamptz8'`。
- 文件：`extract_ns('nanosecond', ts)` 與 PG 的 microsecond 欄位一樣包含整數秒，並附範例。
- 文件：說明擴充套件不會阻止混用 `now()`／`timestamptz`（隱式轉型），這是使用慣例。
- 文件：設了 `partition_func` 時 TimescaleDB 預設索引建在分區運算式上，建議另建 `(ts DESC)` 索引；TECHNICAL.md 新增索引支援矩陣。

## [0.1.0] - 2026-10-23

第一個版本，只支援 PostgreSQL 17 與 18。

### 新增
- 型別：
  - `nanotimestamptz`：16 B `{int64 sec, int64 nsec}`，範圍與 timestamptz 相同。
  - `nanotimestamptz8`：8 B，int64 Unix 奈秒，範圍 1677–2262。
  - `nanotimestamp`：不含時區。
  - `nanointerval`：固定奈秒。
- I/O：text 為 ISO 8601、9 位小數；也支援 binary send/recv。
- 比較、min/max、B-tree、hash、BRIN minmax。
- 轉型：與 timestamptz、timestamp、date、interval、bigint 互轉（bigint 只能明確轉型），轉成微秒時一律 floor。
- 算術、`time_bucket_ns`、`date_trunc`、`extract_ns`、`timezone()`；所有越界情況都會報錯。
- 時鐘：
  - `clock_ns`、`now_ns`、`statement_ns`，以及 8 B 版本。
  - `clock_ns_monotonic`：每個連線內嚴格遞增。
  - `clock_ns_global`：跨連線嚴格遞增，需要 `shared_preload_libraries`。
  - `nanotime_clock_status()`、`nanotime_reset_stats()`。
  - GUC `nanotime.clock_source`（realtime/tai）。
- 遷移：`nanotime_migration_expr`、`nanotime_migrate_column`、`nanotime_suspect_count`。
- TimescaleDB：`ns()`、`nanotime_now_int8()`、`nanotime_part`、`nanotime_part_notz`、`nanotime_part8`。
- 15 組回歸測試（其中 timescale 為選用），包含驗證 docs/EXAMPLES.md 的 `examples`；另有 GitHub Actions CI、PGXN META.json、`make dist`。
- 文件：README 改寫成給一般使用者看的版本；原 README 內容移到 `docs/TECHNICAL.md`；新增 `docs/GUIDE.md`（依情境的使用指南）與 `docs/EXAMPLES.md`（實際執行的實例）。

[Unreleased]: https://github.com/bunko666-cloud/pg_nanotime/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/bunko666-cloud/pg_nanotime/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/bunko666-cloud/pg_nanotime/releases/tag/v0.1.0
