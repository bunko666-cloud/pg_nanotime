# pg_nanotime

PostgreSQL 奈秒精度時間戳擴充套件，作為 [timestamp9](https://github.com/optiver/timestamp9) 的替代方案。授權：PostgreSQL License。

> 狀態：**v0.1.0（Phase 1–3 完成，準備發佈）**。原始碼：`<REPO_URL>`（待填）。CI：`<CI_BADGE>`（待填）。[English summary](#english)
>
> **只支援 PostgreSQL 17 與 18**（已在 17.11、18.6 上建置並通過全部回歸測試）。PG 16 以下會在建置時直接報錯：Makefile 會檢查 `pg_config --version`，原始碼也有 `#error`。程式中沒有任何舊版相容碼。

## 使用原則（重要）

奈秒欄位請**一律**使用 `nanotimestamptz`（或 `nanotimestamptz8`），並搭配 `now_ns()` / `statement_ns()` / `clock_ns()` 產生時間。**不要**和 `now()` / `timestamptz` 混用：

- `now_ns()` 是交易中**第一個查詢開始執行時**由本擴充套件讀取的時鐘，而 `now()` 是 PostgreSQL 在交易開始時讀取的另一個時鐘值。兩者通常相差幾微秒，`now_ns()` 比較晚。如果同一筆資料一欄用 `now()`、另一欄用 `now_ns()`，或拿 `now()` 去和 `now_ns()` 寫入的值比較，就會出現幾微秒的不一致。
- `statement_ns()` 同理，是陳述式開始時讀取的值，同一陳述式內不變。
- `clock_ns()` 的語意和 `clock_timestamp()` 相同：每次呼叫都即時讀取牆鐘（`CLOCK_REALTIME`），只是精度到奈秒。

## 型別 `nanotimestamptz`

| 項目 | 說明 |
|---|---|
| 儲存 | 16 bytes：`{ int64 sec; int64 nsec; }`，對齊 `double`，`STORAGE plain` |
| 紀元 | Unix 紀元 1970-01-01 00:00:00 UTC；`sec` 為向下取整（floor）的秒數 |
| `nsec` | 永遠正規化為 0..999999999（1969-12-31 23:59:59.999999999 = `{-1, 999999999}`） |
| 範圍 | 與 `timestamptz` 相同：4714-11-24 00:00:00 BC（PG 文件稱「4713 BC」，為儒略曆寫法）到 294276-12-31 23:59:59.999999999 |
| 閏秒 | v1 不處理（與 PostgreSQL 一致）；CLOCK_TAI 選項規劃於 Phase 3 |

### 文字輸入／輸出

- 輸入：接受 `timestamptz` 能接受的任何格式，秒數後可帶 1–9 位小數；第 10 位以後只允許 `0`，否則報錯（不靜默截斷）。時區、`BC` 的解析完全交給 PostgreSQL 本身。
- 輸出：固定 ISO 8601 樣式 `YYYY-MM-DD HH:MI:SS.fffffffff±TZ`，永遠 9 位小數，依 session `TimeZone` 顯示偏移（與 `timestamptz` 在 `DateStyle=ISO` 時相同）。**不跟隨 DateStyle**。
- 負值輸出無歧義：`(-1)::bigint::nanotimestamptz` → `1969-12-31 23:59:59.999999999+00`。
- `infinity` / `-infinity`：v0.1 不支援，會報錯。

### 二進位 I/O

`send`/`recv`：兩個 big-endian int64（sec、nsec）。`recv` 會檢查 nsec 範圍與時間範圍。

## 精簡型別 `nanotimestamptz8`

| 項目 | 說明 |
|---|---|
| 儲存 | 8 bytes，傳值（pass by value），int64 Unix 奈秒，與 `bigint` 的二進位格式相同 |
| 範圍 | 1677-09-21 00:12:43.145224192 到 2262-04-11 23:47:16.854775807 UTC，沒有 1970 下限；超出範圍一律報錯，不會溢位繞回 |
| I/O | 文字輸入／輸出的程式碼與 16 B 型別共用；binary 格式與 int8 相同 |
| 索引 | B-tree、hash、BRIN minmax（比較直接使用 PG 內建 int8 函式） |
| 轉型 | 轉成 `nanotimestamptz` 精確且為 IMPLICIT（所以兩型別可以直接比較）；`nanotimestamptz → 8` 為 ASSIGNMENT，超出範圍報錯；與 `timestamptz` 雙向為 ASSIGNMENT，轉成 timestamptz 時 floor；與 `bigint` 雙向為明確轉型，`WITHOUT FUNCTION`，零成本 |
| 時鐘 | `clock_ns8()`、`now_ns8()`、`statement_ns8()`，與 16 B 版本是同一次時鐘讀取 |

### TimescaleDB（2.31.0 實測）

- 可以直接作為 hypertable 的時間維度，不需要分區函數：`create_hypertable('t', by_range('ts', 86400000000000))`。chunk 排除、壓縮、`drop_chunks(older_than => '...'::nanotimestamptz8)` 都正常。
- **不能**使用 `set_integer_now_func` 與連續聚合：TimescaleDB 不把它當成整數維度。`time_bucket` 也沒有這個型別的版本，請用 `time_bucket(bigint, ts::bigint)::nanotimestamptz8` 查詢。需要連續聚合時，請把時間欄位存成 `bigint`。

## 運算子與索引

- `< <= = <> >= >`、`min()`/`max()`、`greatest`/`least`。
- B-tree、hash、BRIN minmax 運算子類別（都是預設）；`=` 支援 hash join 與 merge join。

## 型別轉換

| 轉換 | 語意 | 情境 |
|---|---|---|
| `timestamptz → nanotimestamptz` | 精確 | IMPLICIT |
| `nanotimestamptz → timestamptz` | 向下取整到微秒（1970 前亦為 floor） | ASSIGNMENT |
| `bigint → nanotimestamptz` | bigint = 1970 起算的奈秒數 | 僅 EXPLICIT |
| `nanotimestamptz → bigint` | 超出 1677-09-21 00:12:43.145224192 ～ 2262-04-11 23:47:16.854775807 時報錯 | 僅 EXPLICIT |

所有超出範圍的情況一律報錯，不會溢位繞回（wraparound）。

## 時鐘函式

| 函式 | 易變性 | 說明 |
|---|---|---|
| `clock_ns()` | VOLATILE | 每次呼叫讀 `clock_gettime(CLOCK_REALTIME)` |
| `now_ns()` | STABLE | 交易開始時間（奈秒）。在該交易第一次 executor 啟動時讀取時鐘並快取 |
| `statement_ns()` | STABLE | 目前陳述式開始時間（奈秒），同一陳述式內不變 |

注意：`now_ns()` 是由擴充套件在 `ExecutorStart_hook` 讀取的時鐘，**不是** PostgreSQL `now()` 的同一次讀取，因此通常比 `now()` 晚數微秒（`now_ns()::timestamptz >= now()`）。如果函式庫在陳述式開始後才首次載入，第一次呼叫時才讀時鐘。建議在 `postgresql.conf` 設定 `shared_preload_libraries = 'pg_nanotime'` 或 `session_preload_libraries`，讓時間更貼近交易開始。

```sql
CREATE TABLE events (
  id bigserial,
  ts nanotimestamptz NOT NULL DEFAULT clock_ns(),
  tx nanotimestamptz NOT NULL DEFAULT now_ns()
);
```

## 安裝

需要 PostgreSQL 17 或 18 的開發套件（Debian/Ubuntu 為 `postgresql-server-dev-17` 或 `postgresql-server-dev-18`）與 C 編譯器。

```sh
git clone <REPO_URL> pg_nanotime && cd pg_nanotime
make PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
sudo make install PG_CONFIG=/usr/lib/postgresql/18/bin/pg_config
# 或從 PGXN 安裝：pgxn install pg_nanotime（發佈後）
```

若要使用 `clock_ns_global()`，或想讓 `now_ns()` 更貼近交易開始時間，請在 `postgresql.conf` 加上以下設定，然後重新啟動：

```
shared_preload_libraries = 'pg_nanotime'      # 已用 TimescaleDB 時：'timescaledb, pg_nanotime'
```

## 快速上手

```sql
CREATE EXTENSION pg_nanotime;

CREATE TABLE trades (
  id  bigserial PRIMARY KEY,
  t   nanotimestamptz  NOT NULL DEFAULT clock_ns(),        -- 完整範圍，16 B
  t8  nanotimestamptz8 NOT NULL DEFAULT clock_ns8(),       -- 1677–2262，8 B
  seq nanotimestamptz8 NOT NULL DEFAULT clock_ns8_global() -- 跨連線嚴格遞增（需要 preload）
);
INSERT INTO trades DEFAULT VALUES;
SELECT t, t - lag(t) OVER (ORDER BY t) AS gap FROM trades;
SELECT time_bucket_ns('1 second', t), count(*) FROM trades GROUP BY 1;

-- 從 timestamp9 遷移：
CALL nanotime_migrate_column('old_table', 'ts', new_default => 'clock_ns()');
```

## 建置與測試

```sh
make installcheck PGHOST=/tmp PGPORT=5432 PGUSER=postgres
```

- 加上 `WITH_TIMESCALEDB=1` 會多跑 `timescale` 測試。
- 有沒有 preload 都能跑：`global` 測試準備了兩份預期結果。
- `make dist` 會從 HEAD 產生 PGXN 用的 zip。

## 文件

- [docs/TESTING.md](docs/TESTING.md)：測試報告，包含環境、回歸測試、timestamp9 行為、TimescaleDB 相容性、效能、遷移與並行測試
- [docs/TIMESCALEDB.md](docs/TIMESCALEDB.md)：TimescaleDB 使用範例
- [bench/](bench/README.md)：重現測試用的腳本
- [CHANGELOG.md](CHANGELOG.md)、[CONTRIBUTING.md](CONTRIBUTING.md)

## 尚未完成

- `infinity`，以及依 DateStyle 輸出。
- TimescaleDB 連續聚合：需要向上游提案。

## Phase 2：nanointerval、算術、分桶

### nanointerval
- 只存固定奈秒數（沒有月、日欄位），16 bytes `{int64 sec, int64 nsec}`。
- **為什麼不用 int64**：int64 奈秒只涵蓋約 ±292 年，但 `nanotimestamptz` 涵蓋約 30 萬年，任兩個值相減都必須放得下。16B 的範圍是 ±(max − min) ≈ ±9.4e21 ns，剛好容納所有 ts − ts 的差值，超出時嚴格報錯 `nanointerval out of range`。
- 輸出：`1 day 02:03:04.123456789`、`-1 day -02:00:00.000000000`、`-14 days`，小數固定 9 位。
- 輸入：單位字（ns/us/ms/s/min/h/d/w 及全名）、`HH:MM[:SS.f]`、`@`、`ago`、純數字（秒）、ISO 8601 `P..T..`。month/year 會報錯並提示改用 interval；比 1 ns 更細也會報錯。
- 運算子：比較、B-tree、hash、一元 `-`、`+`、`-`、`* / int`（/ 四捨五入，遠離 0）、`* / numeric`。`smallint` 需要先轉型（不然會有 `operator is not unique`）。
- 轉型：`interval ↔ nanointerval` 是 ASSIGNMENT 轉型。從 interval 轉入時，有月份或 infinity 會報錯，**1 day 當作 24 小時**。轉成 interval 時會向下取整到 µs。`bigint ↔ nanointerval`（奈秒）只能明確轉型。
- `nanointerval_ns(x) → numeric`、`nanointerval_from_ns(numeric)`。

### 算術（兩種時間型別都有，溢位都會報錯）
- `ts − ts → nanointerval`
- `ts ± nanointerval`：固定奈秒
- `ts ± interval`：依 session 時區做日曆運算（與 timestamptz 相同，DST 下 +1 day 會保留牆上時間），保留 µs 以下的位數。因為受時區影響，所以是 STABLE。
- ⚠️ **字面值陷阱**：`ts + '1 day'` 這類未標型別的字串會解析成內建的 **interval**（日曆語意、µs 精度）。需要奈秒精度或固定長度時，請寫 `'...'::nanointerval`。`ts − '2024-01-01'` 會解析成 ts − ts。

### 分桶與相關函式
- `time_bucket_ns(width nanointerval, ts [, origin])`：兩種型別都有，回傳與輸入相同的型別。預設 origin 是 1970-01-01 UTC，向下取整（1970 年以前也正確）。width ≤ 0 會報錯。**若桶起點低於型別最小值，會夾到最小值**（例如 nt8 在 1677-09-21 那一天）。
- `date_trunc(text, ts [, zone])`：µs 以上的單位交給 PG 的 timestamptz_trunc；`'nanosecond'` 則原值回傳。
- `extract_ns(text, ts|nanointerval) → numeric`（`EXTRACT(... FROM ...)` 語法在 PG 中寫死，無法擴充）：epoch 精確到 9 位小數；nanosecond、microsecond、millisecond、second 都含奈秒；其他欄位交給 PG 處理。nanointerval 支援 epoch、day、hour、minute 與秒以下的欄位。

### nanotimestamp（不含時區）
- 16 bytes `{int64 sec, int64 nsec}`，與 nanotimestamptz 共用程式碼。sec 是 1970-01-01 00:00:00 起算的牆上時間秒數（不含時區），語意與 PG `timestamp` 相同。範圍等同 timestamp。
- text I/O 會忽略輸入中的時區（`'...+05'` 直接取牆上時間），輸出沒有時區後綴；IMMUTABLE。
- 比較、min/max、B-tree、hash、BRIN minmax。
- 轉型（context 與核心的 timestamp/timestamptz 相同）：
  - `timestamp → nanotimestamp` IMPLICIT；反向是 ASSIGNMENT，floor 到 µs。
  - `date → nanotimestamp` IMPLICIT；反向是 ASSIGNMENT。`date ↔ nanotimestamptz` 也有，都是 ASSIGNMENT。
  - `nanotimestamp → nanotimestamptz` IMPLICIT；反向是 ASSIGNMENT。兩者都依 session 時區換算（DST 的 gap 和 overlap 處理和核心相同），µs 以下的位數保留。
  - `bigint ↔ nanotimestamp` 只能明確轉型（牆上時間 ns）。
- `AT TIME ZONE`：這個語法在 PG 中寫死為 `pg_catalog.timezone`，擴充套件無法支援。請改用 `timezone(zone, nanotimestamp) → nanotimestamptz` 與 `timezone(zone, nanotimestamptz) → nanotimestamp`，結果與核心一致。
- 算術：`ts − ts`、`ts ± nanointerval`、`ts ± interval`（純日曆運算，不受時區與 DST 影響，IMMUTABLE）、`time_bucket_ns`、`date_trunc`（沒有 zone 參數）、`extract_ns`。

**為什麼沒有 8 B 不含時區版本**：8 B 型別存在的理由，是 TimescaleDB 維度和 bigint 二進位相容，加上大量 tick 資料。這些資料都是絕對時刻，應該存 `nanotimestamptz8`。不含時區的牆上時間多半是排程、本地事件，量小，而且需要 1677–2262 以外的範圍。每多一個型別，轉型與運算子的組合就會成倍增加，候選函式也更容易產生歧義。真的需要時，可以用 `nanotimestamptz8` 搭配 `timezone('UTC', …)`。

## 遷移工具
- `nanotime_migration_expr(src regtype, target regtype, col name) → text`：產生 `ALTER TABLE ... USING` 的運算式。
  - timestamp9 經由它自己的二進位 bigint 轉型 `col::bigint::nanotimestamptz`。pg_nanotime 不依賴 timestamp9，只是欄位存在時 timestamp9 必須已安裝。
  - bigint ns 會直接轉成 nanotimestamptz8，不做任何換算。
  - timestamptz、timestamp、date 是精確轉換（µs × 1000）；跨越有無時區時，依 session 時區。
- `CALL nanotime_migrate_column(tbl, col, target DEFAULT 'nanotimestamptz', new_default DEFAULT NULL, dry_run DEFAULT false)`：
  - 用一個 `ALTER TABLE ... TYPE ... USING` 完成。PG 會在同一個陳述式中，用新型別的預設 opclass 重建該欄位的 B-tree、hash、BRIN、unique 索引，失敗時整個回滾。
  - 舊的預設值如果無法轉換（例如 timestamp9 常數），會報錯並提示用 `new_default => 'clock_ns()'`。
  - 有 view 或 rule 依賴該欄位時，ALTER 會失敗（PG 的限制）。
  - `dry_run` 只印出 SQL 和會重建的索引。
- 手動寫法：`ALTER TABLE t ALTER COLUMN c TYPE nanotimestamptz USING c::bigint::nanotimestamptz;`（timestamp9），或 `USING c::nanotimestamptz8`（bigint ns）。
- **timestamp9 繞回損毀**：timestamp9 會把超出範圍的輸入靜默繞回，例如 1500-01-01 變成 2084-07-20 23:34:33.709551616。繞回後仍是合法時刻，**無法可靠偵測**。`nanotime_suspect_count(tbl, col, lo, hi)` 只能統計落在你預期時間窗 [lo, hi) 之外的列數，預設窗是 1990–2100。窗要依照資料實際的時間跨度來設，越窄越有用。
- 實測（PG 18.6、timestamp9 1.4.0，2026-10-23）：
  - 20 萬 + 4 列，含 1677/2262 兩端、1969 與 1500 的繞回值，3 個索引，約 0.5 秒完成。
  - 200004/200004 列的 ns 值與文字輸出完全相同。
  - 預設窗只抓到 3 列（1677、1969、2262），抓不到 2084 的繞回值，正好說明它的限制。
  - 回歸測試用一個名為 timestamp9 的 bigint domain 模擬，因為 PG 17 上沒有安裝 timestamp9。

## Phase 3：嚴格遞增時鐘、時鐘來源、TimescaleDB 輔助

### 嚴格遞增時鐘

| 函式 | 保證 | 需求 |
|---|---|---|
| `clock_ns_monotonic()` / `clock_ns8_monotonic()` | 同一連線內嚴格遞增：時鐘沒有前進時取上一個值 + 1 ns。不加鎖。16 B 和 8 B 版本共用同一個計數器 | 無 |
| `clock_ns_global()` / `clock_ns8_global()` | 跨所有連線嚴格遞增且不重複：在共享記憶體上用 atomic CAS 取 `max(now, last + 1)` | `shared_preload_libraries = 'pg_nanotime'`，否則會報出清楚的錯誤 |

注意事項：
- 保證的是「呼叫順序」，**不是** commit 順序。先取到時間的交易可能較晚 commit。
- global 的計數器存在共享記憶體，伺服器重啟後會重來。
- 多個連線同時大量呼叫時，global 的總速率只有一般時鐘的約 14–28%。實測數字見 [docs/TESTING.md](docs/TESTING.md) §8。

### 時鐘倒退與監控

`SELECT * FROM nanotime_clock_status();` 回傳以下欄位：
- 目前的時鐘來源、核心 TAI 偏移（秒）、是否已 preload。
- global：最後發出的值、`global_lead_ns`（領先實際時鐘的奈秒數，持續為正表示時鐘倒退過或呼叫非常密集）、呼叫次數、`bumps`（時鐘沒前進、改用 +1 ns 的次數）、倒退次數與最大倒退幅度。
- 本連線：同樣一組數值。

倒退的判定方式：同一連線讀到的時鐘值比上一次小。切換時鐘來源不算倒退。`nanotime_reset_stats()` 用來歸零計數，預設只有 superuser 能執行。時鐘倒退時，monotonic 與 global 會持續 +1 ns，直到實際時鐘追上；一般的 `clock_ns()` 則會跟著時鐘倒退。

### `nanotime.clock_source = realtime | tai`

- `realtime`（預設）：`CLOCK_REALTIME`，也就是 UTC。
- `tai`：`CLOCK_TAI`。**Linux 預設的 TAI 偏移是 0**，這時讀到的值和 realtime 相同。偏移要由 chrony（`leapsectz right/UTC`）或 ptp4l/phc2sys 設定，目前約為 37 秒，可以從 `nanotime_clock_status().tai_offset_s` 確認。
- 用 tai 寫入的值是 TAI 時間，但輸出仍標示為 UTC 格式，與 realtime 的值相差偏移量。請不要在同一個欄位混用兩種來源。
- 這個設定會影響所有時鐘函式，可以在每個連線各自設定。

`nanotime.debug_clock_offset_us` 只供測試使用（限 superuser），會在所有時鐘讀值上加上一個偏移，用來模擬時鐘倒退。

### TimescaleDB 輔助

`ns(nanointerval)`、`nanotime_now_int8()`、`nanotime_part()`、`nanotime_part_notz()`、`nanotime_part8()`。用法範例見 **[docs/TIMESCALEDB.md](docs/TIMESCALEDB.md)**。

<a id="english"></a>
## English

pg_nanotime is a PostgreSQL 17/18 extension providing nanosecond timestamps, as an alternative to timestamp9. Source: `<REPO_URL>` (to be filled in).

- **Types**:
  - `nanotimestamptz`: 16 bytes, the full PostgreSQL timestamp range.
  - `nanotimestamptz8`: 8 bytes, int64 Unix ns, 1677–2262; binary-compatible with bigint, so TimescaleDB uses it as a native dimension.
  - `nanotimestamp`: without time zone.
  - `nanointerval`: fixed nanoseconds.
  - Out-of-range input, casts and arithmetic raise errors instead of wrapping around.
- **Indexes and functions**: B-tree, hash and BRIN; `ts - ts`, `± nanointerval` and `± interval`; `time_bucket_ns`, `date_trunc`, `extract_ns`, `timezone()`.
- **Clocks**:
  - `now_ns()`, `statement_ns()`, `clock_ns()` (and `*_ns8` variants).
  - `clock_ns_monotonic()` is strictly increasing within a session.
  - `clock_ns_global()` is strictly increasing and unique across sessions; it needs `shared_preload_libraries`.
  - The clock is selected with `nanotime.clock_source = realtime | tai`.
  - `nanotime_clock_status()` reports clock regressions and drift.
- **Migration**: `nanotime_migrate_column()` converts timestamp9, bigint ns, timestamptz and timestamp columns in a single `ALTER TABLE`, rebuilding indexes.
- **TimescaleDB**: `ns()`, `nanotime_now_int8()`, `nanotime_part*()`. See docs/TIMESCALEDB.md.

Install with `make && sudo make install` (PGXS), then `CREATE EXTENSION pg_nanotime;`. Run the tests with `make installcheck`. Detailed docs are in Traditional Chinese; test results, with real measured numbers, are in docs/TESTING.md. License: PostgreSQL.
