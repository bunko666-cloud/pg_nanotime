# Changelog

格式參考 [Keep a Changelog](https://keepachangelog.com/)，版本號遵循 [SemVer](https://semver.org/)。

## [Unreleased]

### 新增
- `tools/check_examples.py` 與 `make check-docs`：檢查 `docs/EXAMPLES.md` 的程式碼區塊與 `examples` 回歸測試逐行一致。
- GitHub Actions「Docs examples」流程：範例文件或測試變動時自動執行上述檢查（不需安裝 PostgreSQL）。

### 修正
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
