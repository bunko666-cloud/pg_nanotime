# Changelog

格式參考 [Keep a Changelog](https://keepachangelog.com/)，版本號遵循 [SemVer](https://semver.org/)。

## [0.1.0] - 未發佈

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
- 14 組回歸測試（其中 timescale 為選用）、GitHub Actions CI、PGXN META.json、`make dist`。

[0.1.0]: <REPO_URL>/releases/tag/v0.1.0
