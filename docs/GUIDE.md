# pg_nanotime 使用指南

依情境一步步說明。每個情境的完整執行結果請見 [EXAMPLES.md](EXAMPLES.md)；所有函式與語意細節請見 [TECHNICAL.md](TECHNICAL.md)。

## 1. 建立有奈秒時間的表

```sql
CREATE EXTENSION pg_nanotime;

CREATE TABLE measurements (
  id     bigserial PRIMARY KEY,
  ts     nanotimestamptz NOT NULL,
  value  double precision
);
INSERT INTO measurements(ts, value)
VALUES ('2026-10-23 09:00:00.123456789+08', 1.5);
```

- 文字格式與 PostgreSQL 的 `timestamptz` 相同，小數點後最多 9 位；超過 9 位會報錯，不會偷偷捨去。
- 輸出永遠是 ISO 格式、9 位小數，並依 session 的 `TimeZone` 換算。
- 型別選擇見 [README](../README.md#該用哪一種型別)。不確定時就用 `nanotimestamptz`。

## 2. 自動填入時間：`clock_ns()` 還是 `now_ns()`？

| 函式 | 意義 | 何時用 |
|---|---|---|
| `clock_ns()` | 每次呼叫都讀取當下時鐘 | 想知道「這一列實際寫入的時刻」，例如收到訊息的時間 |
| `now_ns()` | 交易開始時的時間，同一交易內固定不變 | 想讓同一筆交易寫入的所有列有相同時間 |
| `statement_ns()` | 這一條 SQL 開始的時間 | 同一條 SQL 的列共用時間，但不同 SQL 不同 |

```sql
CREATE TABLE inbox (
  id         bigserial PRIMARY KEY,
  received   nanotimestamptz NOT NULL DEFAULT clock_ns(),
  batch_time nanotimestamptz NOT NULL DEFAULT now_ns()
);
```

8 bytes 型別使用對應的 `clock_ns8()`、`now_ns8()`、`statement_ns8()`。

## 3. 嚴格遞增、不重複的時間

一般時鐘在極短時間內可能讀到相同的值，系統校時（NTP）時甚至可能倒退。需要「絕對不重複、一定越來越大」時：

| 函式 | 保證範圍 | 需求 |
|---|---|---|
| `clock_ns_monotonic()` / `clock_ns8_monotonic()` | 同一個連線內嚴格遞增 | 無 |
| `clock_ns_global()` / `clock_ns8_global()` | **所有連線之間**嚴格遞增、不重複 | `shared_preload_libraries` |

使用 global 版本前，在 `postgresql.conf` 加入以下設定並重新啟動 PostgreSQL：

```
shared_preload_libraries = 'pg_nanotime'   # 已使用 TimescaleDB 時：'timescaledb, pg_nanotime'
```

```sql
CREATE TABLE orders (
  seq_ts nanotimestamptz8 PRIMARY KEY DEFAULT clock_ns8_global(),
  side   char(1), price numeric, qty int
);
```

- 時鐘沒有前進時，函式會回傳上一個值加 1 ns，所以值會稍微領先真實時間。`SELECT * FROM nanotime_clock_status();` 可以看到領先多少，以及時鐘倒退過幾次。
- 保證只在 PostgreSQL 運行期間有效，重新啟動後從當下時鐘重新開始。
- 實際效果：[EXAMPLES §2](EXAMPLES.md#2-撮合引擎先到先處理fifo)。

## 4. 計算延遲：`ts - ts`

兩個時間相減得到 `nanointerval`：

```sql
SELECT recv_ts - exch_ts AS latency FROM ticks;            -- 00:00:00.000041250
SELECT (recv_ts - exch_ts)::bigint AS latency_ns FROM ticks; -- 41250
```

要算平均、百分位數時，先轉成 bigint 奈秒再用 PostgreSQL 內建的聚合函式（`avg`、`percentile_disc`）。比較門檻時寫 `> '50 microseconds'::nanointerval`。完整例子見 [EXAMPLES §1](EXAMPLES.md#1-交易-tick-資料與延遲統計)。

## 5. 依時間分桶統計：`time_bucket_ns`

```sql
SELECT time_bucket_ns('1 second'::nanointerval, ts) AS bucket, count(*), avg(value)
FROM readings GROUP BY 1 ORDER BY 1;
```

第三個參數可以指定起點（預設 1970-01-01 UTC）。1970 年以前的時間也會正確分桶。若要依日曆單位（日、月）截斷，可以用 `date_trunc('day', ts)`。

## 6. 與 `timestamptz` 互轉

```sql
SELECT '2026-10-23 09:00:00+08'::timestamptz::nanotimestamptz;  -- 2026-10-23 09:00:00.000000000+08
SELECT '2026-10-23 09:00:00.123456789+08'::nanotimestamptz::timestamptz;  -- 2026-10-23 09:00:00.123456+08
```

轉成 `timestamptz` 時，微秒以下會無條件捨去（往過去取整），奈秒資訊會消失。只有在要交給只認識內建型別的工具時才轉換。

## 7. 從 timestamp9 或 bigint 遷移

```sql
CALL nanotime_migrate_column('events', 't', dry_run => true);  -- 只顯示要執行的 SQL
CALL nanotime_migrate_column('events', 't');                   -- 正式轉成 nanotimestamptz
CALL nanotime_migrate_column('events', 't', 'nanotimestamptz8'); -- 或指定目標型別
```

- 只執行一個 `ALTER TABLE`，索引會自動重建；失敗時整個回滾。
- 如果舊的預設值無法轉換，加上 `new_default => 'clock_ns()'`。
- bigint 奈秒欄位也可以直接寫 `ALTER TABLE ... TYPE nanotimestamptz8 USING col::nanotimestamptz8`。
- timestamp9 超出範圍時會悄悄「繞回」成錯誤但看似合理的時間，這種資料無法可靠地自動偵測。`nanotime_suspect_count(表, 欄位, 下限, 上限)` 可以統計落在預期時間範圍外的列數，協助人工檢查。

## 8. TimescaleDB 基本用法

```sql
CREATE TABLE ticks (ts nanotimestamptz8 NOT NULL, price numeric);
SELECT create_hypertable('ticks', by_range('ts', ns('1 day')));
```

- `nanotimestamptz8` 可以直接當 hypertable 的時間欄位。`ns('1 day')` 會把時間長度換成 TimescaleDB 需要的奈秒整數。
- `nanotimestamptz` 需要分區函式 `nanotime_part`。
- 連續聚合（continuous aggregate）目前不支援這兩種型別。

詳細步驟與限制見 [TIMESCALEDB.md](TIMESCALEDB.md)。

## 9. 常見陷阱

1. **沒標型別的 `'1 day'` 是 PostgreSQL 內建 interval。**`ts + '1 day'` 是日曆上的「明天同一時刻」：遇到日光節約時間切換，實際長度會是 23 或 25 小時，而且精度只到微秒。需要固定長度或奈秒精度時，請寫 `'1 day'::nanointerval`。例如在 America/New_York 時區：

   ```sql
   SELECT '2026-10-31 12:00:00-04'::nanotimestamptz + '1 day';                -- 2026-11-01 12:00:00.000000000-05
   SELECT '2026-10-31 12:00:00-04'::nanotimestamptz + '1 day'::nanointerval;  -- 2026-11-01 11:00:00.000000000-05
   ```

2. **不要混用 `now()` 與 `now_ns()`。**`now_ns()` 在交易的第一個查詢開始時才讀取時鐘，會比 `now()` 晚幾微秒。兩者混在同一欄位或互相比較時，可能出現「先發生的反而比較晚」。奈秒欄位請一律使用 pg_nanotime 的函式。
3. **`clock_ns()` 不保證不重複。**需要唯一、遞增的值時，請用 §3 的 monotonic 或 global 版本。
4. **`EXTRACT(...)` 和 `AT TIME ZONE` 語法無法擴充**：請改用 `extract_ns('epoch', ts)` 與 `timezone('Asia/Taipei', ts)`。
5. **8 bytes 型別只到 2262 年。**超出範圍時會報錯，不會繞回。需要更大範圍時請改用 `nanotimestamptz`。
