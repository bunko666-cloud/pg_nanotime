# Changelog

格式參考 [Keep a Changelog](https://keepachangelog.com/)，版本號遵循 [SemVer](https://semver.org/)。

## [Unreleased]

### 新增
- `sum(nanointerval)`、`avg(nanointerval)` 聚合：int128 精確累加，溢位時報錯 `nanointerval out of range`；`avg` 四捨五入到奈秒（剛好一半時遠離 0，與 `nanointerval / bigint` 一致）；忽略 NULL，沒有資料時回傳 NULL；支援平行查詢與視窗函式移動聚合。新增回歸測試 `agg`。
- 擴充套件版本升到 0.2.0：新增升級腳本 `pg_nanotime--0.1.0--0.2.0.sql`，可用 `ALTER EXTENSION pg_nanotime UPDATE` 從 0.1.0 升級；CI 會檢查升級後與全新安裝的物件一致。
- `abs(nanointerval)`（範圍對稱，最小值也能取負，不會溢位）。
- `generate_series(start, stop, step nanointerval)`，支援 `nanotimestamptz`、`nanotimestamptz8`、`nanotimestamp`：與 PostgreSQL 語意一致（包含 stop、step 0 報錯、負 step 往回數），在型別範圍邊緣不會繞回；附 planner support 函式，常數參數時列數估計精確。
- `nanointerval_from_ns(double precision)`（四捨五入遠離 0；NaN／Infinity 報明確錯誤；超過 2^53 ns 會失去精度，已寫入文件）與精確的 `nanointerval_from_ns(bigint)`（避免整數參數被解析到 double precision 版本）。新增回歸測試 `series`。
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

[0.1.0]: https://github.com/bunko666-cloud/pg_nanotime/releases/tag/v0.1.0
