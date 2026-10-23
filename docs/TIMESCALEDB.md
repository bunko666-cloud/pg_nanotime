# 在 TimescaleDB 上使用 pg_nanotime

以下用法都在 TimescaleDB 2.31.0、PG 17.11 與 18.6 上測試過（回歸測試 `timescale`）。

## 輔助函數

| 函數 | 用途 |
|---|---|
| `ns(nanointerval) → bigint` | 把區間轉成奈秒，給 chunk 間隔與策略參數使用，例如 `ns('1 day')` 會得到 86400000000000 |
| `nanotime_now_int8() → bigint` | STABLE，回傳交易開始時間（等於 `now_ns8()::bigint`），給 `set_integer_now_func` 使用 |
| `nanotime_part(nanotimestamptz) → bigint` | 16 B 含時區型別的分區函數：IMMUTABLE、單調、超出 int64 範圍時飽和到兩端 |
| `nanotime_part_notz(nanotimestamp) → bigint` | 同上，用於不含時區的型別 |
| `nanotime_part8(nanotimestamptz8) → bigint` | 8 B 型別的恆等映射，設了它才能使用 `set_integer_now_func` |

三個分區函數的名稱不同，因為 TimescaleDB 用不含型別的函數名稱查找分區函數，同名多載會出現 `more than one function named` 錯誤。

## 範例一：8 B 型別（大量 tick 資料，建議用法）

```sql
CREATE TABLE ticks(t nanotimestamptz8 NOT NULL DEFAULT clock_ns8(), sym text, px numeric);
SELECT create_hypertable('ticks', by_range('t', ns('1 day'), partition_func => 'nanotime_part8'));
SELECT set_integer_now_func('ticks', 'nanotime_now_int8');
SELECT add_retention_policy('ticks', drop_after => ns('30 days'));
ALTER TABLE ticks SET (timescaledb.compress, timescaledb.compress_segmentby = 'sym', timescaledb.compress_orderby = 't');
```

設了 `partition_func` 時，TimescaleDB 的預設索引是 `nanotime_part8(t) DESC` 這個運算式索引，直接用 `t` 查詢的條件用不到它（chunk 排除仍有效，但 chunk 內會 seq scan）。請另外建立時間欄索引：

```sql
CREATE INDEX ON ticks (t DESC);
```

`drop_chunks` 的 `older_than` 也必須是 bigint：

```sql
SELECT drop_chunks('ticks', older_than => '2026-10-01+00'::nanotimestamptz8::bigint);  -- 可以
SELECT drop_chunks('ticks', older_than => '2026-10-01+00'::nanotimestamptz8);          -- ERROR: invalid time argument type "nanotimestamptz8"
```

不需要保留策略或 integer now 時，也可以不設分區函數：`by_range('t', ns('1 day'))`。這時預設索引就是 `(t DESC)`，`drop_chunks(..., older_than => '...'::nanotimestamptz8)` 也可以直接用。

## 範例二：16 B 型別（需要 1677–2262 以外的範圍）

```sql
CREATE TABLE ev(t nanotimestamptz NOT NULL, v int);
SELECT create_hypertable('ev', by_range('t', ns('1 day'), partition_func => 'nanotime_part'));
SELECT set_integer_now_func('ev', 'nanotime_now_int8');
SELECT drop_chunks('ev', older_than => nanotime_part('2000-01-01+00'));
CREATE INDEX ON ev (t DESC);  -- 預設索引在 nanotime_part(t) 上，補一個時間欄索引
```

1677 年以前與 2262 年以後的值會集中到兩端各一個 chunk，查詢結果仍然正確，只是那兩個 chunk 不會再細分。

## 分桶

TimescaleDB 的 `time_bucket` 不接受這些型別。請改用：

```sql
SELECT time_bucket_ns('1 minute', t) AS m, count(*) FROM ticks GROUP BY 1;
-- 或者轉成 bigint 後分桶，再轉回來
SELECT time_bucket(ns('1 minute'), t::bigint)::nanotimestamptz8 AS m, count(*) FROM ticks GROUP BY 1;
```

## 限制

- 不支援連續聚合：TimescaleDB 要求 time bucket 直接引用整數或時間維度欄位，而且不支援自訂分區函數。需要連續聚合時，請另外存一個 bigint 奈秒欄位，用它建 hypertable。
- 策略參數只能用 bigint（請用 `ns()`），不接受 interval。
- 測試結果見 [TESTING.md](TESTING.md) §4。
