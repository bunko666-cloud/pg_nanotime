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

0.2.0 起可以直接對 `nanointerval` 用 `sum()`、`avg()`（精確累加；`avg` 四捨五入到奈秒，剛好一半時遠離 0）。`percentile_disc(0.5) WITHIN GROUP (ORDER BY recv_ts - exch_ts)` 可以直接用在 `nanointerval` 上（它只需要排序）；只有 `percentile_cont` 要內插、不支援 `nanointerval`，需要時先轉成 bigint 奈秒，算完再用 `nanointerval_from_ns(...)` 轉回來（沒有 `numeric::nanointerval` 轉型）。0.2.0 起也有 `abs(nanointerval)`，以及 `generate_series(起, 迄, nanointerval)`（三種時間戳型別都有）可以產生奈秒時間格線，例如找出缺漏的取樣點。比較門檻時寫 `> '50 microseconds'::nanointerval`。完整例子見 [EXAMPLES §1](EXAMPLES.md#1-交易-tick-資料與延遲統計)。

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
CALL nanotime_migrate_column('events', 't');                   -- 正式轉成 nanotimestamptz（預設目標，bigint 來源也一樣）
CALL nanotime_migrate_column('events', 't', 'nanotimestamptz8'); -- 或指定目標型別
```

- 只執行一個 `ALTER TABLE`，索引會自動重建；失敗時整個回滾。
- 如果舊的預設值無法轉換，加上 `new_default => 'clock_ns()'`。
- bigint 奈秒欄位也可以直接寫 `ALTER TABLE ... TYPE nanotimestamptz8 USING col::nanotimestamptz8`。
- timestamp9 超出範圍時會悄悄「繞回」成錯誤但看似合理的時間，這種資料無法可靠地自動偵測。`nanotime_suspect_count(表, 欄位, 下限, 上限)` 可以統計落在預期時間範圍外的列數，協助人工檢查。

## 8. TimescaleDB 基本用法

0.3.0 起，一個函式就能設定好：

```sql
CREATE TABLE ticks (ts nanotimestamptz8 NOT NULL, price numeric);
SELECT nanotime_timescale_setup('ticks', 'ts', '1 day');
-- 建立 hypertable（分區函數 nanotime_part8）、設定 integer now、補上 (ts DESC) 索引
SELECT add_retention_policy('ticks', drop_after => ns('30 days'));   -- 保留策略可以直接用
SELECT * FROM nanotime_drop_chunks('ticks', older_than => '2026-10-01+08');  -- 不用自己加 ::bigint
```

`nanotimestamptz`、`nanotimestamp` 也是同一個寫法，函式會選對分區函數。沒有安裝 TimescaleDB 時會直接報錯並提示安裝方式。

0.2.0 或想手動設定時：

```sql
CREATE TABLE ticks (ts nanotimestamptz8 NOT NULL, price numeric);
SELECT create_hypertable('ticks', by_range('ts', ns('1 day')));
```

- `nanotimestamptz8` 可以直接當 hypertable 的時間欄位。`ns('1 day')` 會把時間長度換成 TimescaleDB 需要的奈秒整數。
- `nanotimestamptz` 需要分區函式 `nanotime_part`。
- 有設 `partition_func`（`nanotime_part`、`nanotime_part8`）時：
  - TimescaleDB 的預設索引建在分區運算式上，直接用 `ts` 查詢用不到，請補 `CREATE INDEX ON ticks (ts DESC);`。
  - `drop_chunks` 的 `older_than` 要給 bigint，例如 `'2026-10-01+00'::nanotimestamptz8::bigint`。沒設分區函式時可以直接給 `nanotimestamptz8`。
- 連續聚合（continuous aggregate）目前不支援這兩種型別。

詳細步驟與限制見 [TIMESCALEDB.md](TIMESCALEDB.md)。

## 9. 時段不能重疊：預約與量測視窗（`nanotstzrange`，0.3.0）

> 0.3.0 新增；從 0.2.0 升級用 `ALTER EXTENSION pg_nanotime UPDATE TO '0.3.0';`。設計細節見 [TECHNICAL.md 的範圍型別](TECHNICAL.md#範圍型別-nanotstzrangenanotsrange030)。

會議室被兩個人同時訂走，是辦公室裡很常見的小災難。與其在程式裡先查再寫（兩個人同時按下去還是會撞），不如讓資料庫直接擋下來：

```sql
CREATE EXTENSION btree_gist;   -- 讓 room 這種一般欄位也能放進 GiST 排他約束
CREATE TABLE room_booking (
  room   text NOT NULL,
  who    text NOT NULL,
  during nanotstzrange NOT NULL,
  EXCLUDE USING gist (room WITH =, during WITH &&)   -- 同一間會議室，時段不能重疊
);
INSERT INTO room_booking VALUES
  ('會議室A', '小陳', '[2026-10-27 09:00+08, 2026-10-27 10:00+08)'),
  ('會議室A', '小林', '[2026-10-27 10:00+08, 2026-10-27 11:00+08)');   -- 前後相接：可以
INSERT INTO room_booking VALUES ('會議室A', '小王', '[2026-10-27 09:30+08, 2026-10-27 10:30+08)');
-- ERROR:  conflicting key value violates exclusion constraint "room_booking_room_during_excl"
```

常用的查詢：

```sql
-- 10:15 誰在用？（@> 右邊可以是單一時間點）
SELECT who FROM room_booking
WHERE room = '會議室A' AND during @> '2026-10-27 10:15+08'::nanotimestamptz;   -- 小林

-- 一天的忙碌時段（range_agg 合併成 multirange）
SELECT range_agg(during) FROM room_booking WHERE room = '會議室A';
-- {["2026-10-27 09:00:00.000000000+08","2026-10-27 11:00:00.000000000+08")}

-- 08:00–12:00 之間的空檔（multirange 差集）
SELECT nanotstzmultirange('[2026-10-27 08:00+08, 2026-10-27 12:00+08)'::nanotstzrange) - range_agg(during)
FROM room_booking WHERE room = '會議室A';
-- {[08:00, 09:00), [11:00, 12:00)}（實際輸出含日期、9 位小數與時區）
```

會議室用微秒的 `tstzrange` 就夠了。需要奈秒範圍的是時間本來就很密的資料：高頻量測的取樣視窗、封包擷取的時段、撮合引擎的批次區間。這時「前一段在 10:00:00.000000001 結束、下一段從那一刻開始」必須判定為相鄰而不是重疊，只重疊 1 奈秒的時段也要能被擋下，這些都在回歸測試 `range` 裡實測過。

小提醒：

- **一律用半開區間 `[開始, 結束)`。**範圍型別和 `tstzrange` 一樣是「連續型」：`[09:00, 10:00]` 和 `[10:00, 11:00)` 會共用 10:00 這一刻而被判定重疊。
- 單一時間點不能建 GiST 索引，但範圍型別可以：`CREATE INDEX ON t USING gist (during)`，`&&`、`@>` 查詢會走索引。
- 長度用 `upper(during) - lower(during)`，得到 `nanointerval`。
- `nanotimestamptz8` 欄位也能直接組成範圍：`nanotstzrange(start8, end8)`（會隱含轉成 16 bytes）。

## 10. 常見陷阱

1. **沒標型別的 `'1 day'` 是 PostgreSQL 內建 interval。**`ts + '1 day'` 是日曆上的「明天同一時刻」：遇到日光節約時間切換，實際長度會是 23 或 25 小時，而且精度只到微秒。需要固定長度或奈秒精度時，請寫 `'1 day'::nanointerval`。例如在 America/New_York 時區：

   ```sql
   SELECT '2026-10-31 12:00:00-04'::nanotimestamptz + '1 day';                -- 2026-11-01 12:00:00.000000000-05
   SELECT '2026-10-31 12:00:00-04'::nanotimestamptz + '1 day'::nanointerval;  -- 2026-11-01 11:00:00.000000000-05
   ```

2. **不要混用 `now()` 與 `now_ns()`。**`now_ns()` 在交易的第一個查詢開始時才讀取時鐘，會比 `now()` 晚幾微秒。擴充套件不會阻止混用（`timestamptz` 會隱式轉成 `nanotimestamptz`，`INSERT ... VALUES (now())`、`clock_ns() - now()` 都不會報錯），所以這是要自己遵守的慣例。兩者混在同一欄位或互相比較時，可能出現「先發生的反而比較晚」。奈秒欄位請一律使用 pg_nanotime 的函式。
3. **`clock_ns()` 不保證不重複。**需要唯一、遞增的值時，請用 §3 的 monotonic 或 global 版本。
4. **`EXTRACT(...)` 和 `AT TIME ZONE` 語法無法擴充**：請改用 `extract_ns('epoch', ts)` 與 `timezone('Asia/Taipei', ts)`。注意 `extract_ns('nanosecond', ts)` 和 PG 的 microsecond 欄位一樣包含整數秒：`...01.000000500` 會得到 `1000000500`；只要秒以下部分時用 `% 1000000000`。
5. **8 bytes 型別只到 2262 年。**超出範圍時會報錯，不會繞回。需要更大範圍時請改用 `nanotimestamptz`。
6. **範圍的結束點要用 `)`，不要用 `]`。**`[09:00, 10:00]` 會包含 10:00 這一刻，和下一段 `[10:00, 11:00)` 重疊而被排他約束拒絕。範圍型別沒有 canonical 函式（和 `tstzrange` 一樣），不會自動幫你改寫邊界，見 §9。
