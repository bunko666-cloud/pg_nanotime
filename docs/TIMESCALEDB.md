# 在 TimescaleDB 上使用 pg_nanotime

以下用法都在 TimescaleDB 2.31.0、PG 17.11 與 18.6 上測試過（回歸測試 `timescale`）。

## 一鍵設定（0.3.0，尚未釋出）

`nanotime_timescale_setup(表, 欄位, chunk 長度 DEFAULT '1 day', migrate_data DEFAULT false)` 一次做完下面「範例一／範例二」的手動步驟：

```sql
CREATE TABLE ev(t nanotimestamptz NOT NULL, v int);
SELECT nanotime_timescale_setup('ev', 't', '1 day');
-- hypertable ev: column t (nanotimestamptz), partition_func nanotime_part, chunk 1 day (86400000000000 ns),
--   integer_now_func nanotime_now_int8, index ev_t_idx created
```

它會依欄位型別做這些事：

| 欄位型別 | 分區函數 | chunk 長度 | 其他 |
|---|---|---|---|
| `nanotimestamptz` | `nanotime_part` | `nanointerval` 轉成奈秒 bigint | 三種型別都會設 `set_integer_now_func(..., 'nanotime_now_int8')`，所以保留策略可以直接用；三種型別都用 `create_default_indexes => false` 建立，再補一個 `(欄位 DESC)` 索引 |
| `nanotimestamp` | `nanotime_part_notz` | 同上 | 同上 |
| `nanotimestamptz8` | `nanotime_part8` | 同上 | 同上 |

- **索引**：TimescaleDB 的預設索引會建在分區運算式（例如 `nanotime_part(t) DESC`）上，以 `t` 查詢用不到，所以函式不建預設索引，改建 `(t DESC)`。如果表上已經有「第一個欄位就是 `t`」的一般 B-tree 索引（ASC 或 DESC 都可以，不能是部分索引），就沿用它，不重複建立；回傳文字會寫 `already exists (kept)`。
- **8 B 型別為什麼也用分區函數**：不設分區函數時（原生維度）TimescaleDB 不允許 `set_integer_now_func`；`add_retention_policy` 雖然可以建立，但實際執行時報 `interval field value out of range`（TimescaleDB 2.31.0 實測）。用 `nanotime_part8` 才能讓保留策略正常運作，因此一鍵設定統一使用分區函數。只需要 chunk 排除、不需要保留策略時，仍可以手動 `by_range('t', ns('1 day'))` 建立原生維度。
- **表裡已經有資料**：TimescaleDB 會報 `table "..." is not empty`，加上 `migrate_data => true` 即可（資料多時會花時間）。
- **已經是 hypertable、欄位不存在、型別不對、chunk ≤ 0**：都會報錯，而且整個呼叫在同一個交易裡，不會只做一半。
- **沒有安裝 TimescaleDB**：報 `TimescaleDB is not installed in this database`，並提示要加進 `shared_preload_libraries` 再 `CREATE EXTENSION timescaledb`。pg_nanotime 本身不依賴 TimescaleDB，這兩個函式是用動態 SQL 呼叫它的。
- **支援的 TimescaleDB 版本**：需要 `by_range()` 介面（TimescaleDB 2.13 起；支援 PostgreSQL 17／18 的版本都有）。實測版本是 2.31.0；沒有 `by_range()` 的版本會報錯，不會改用舊的 `create_hypertable(表, 欄位, ...)` 寫法。

### 刪除舊 chunk：`nanotime_drop_chunks`

```sql
SELECT * FROM nanotime_drop_chunks('ev', older_than => '2024-01-02 00:00:00+00');
SELECT * FROM nanotime_drop_chunks('ev', newer_than => '2030-01-01 00:00:00+00');
```

直接給奈秒時間，不用自己加 `::bigint`。函式會查 hypertable 的時間維度，用和分區函數相同的方式換算（`nanotime_part` 系列，超出 int64 範圍時飽和），再呼叫 TimescaleDB 的 `drop_chunks`，回傳被刪除的 chunk 名稱。

- 原生維度（不設分區函數）的 8 B 表也可以用：此時傳給 TimescaleDB 的是 `nanotimestamptz8`，超出 1677–2262 的時間會報 8 B 型別的範圍錯誤。
- 有分區函數的表，`older_than` 早於 1677 年時直接回傳空結果（沒有東西比最小值更舊；TimescaleDB 本身會對這種範圍報錯）。
- 不含時區的表（`nanotimestamp`），參數仍是 `nanotimestamptz`，依 session 時區換算成本地時間；請在 session 時區與資料一致時使用。
- 兩個參數都省略時，由 TimescaleDB 報 `invalid time range for dropping chunks`。

## 輔助函數

| 函數 | 用途 |
|---|---|
| `ns(nanointerval) → bigint` | 把區間轉成奈秒，給 chunk 間隔與策略參數使用，例如 `ns('1 day')` 會得到 86400000000000 |
| `nanotime_now_int8() → bigint` | STABLE，回傳交易開始時間（等於 `now_ns8()::bigint`），給 `set_integer_now_func` 使用 |
| `nanotime_part(nanotimestamptz) → bigint` | 16 B 含時區型別的分區函數：IMMUTABLE、單調、超出 int64 範圍時飽和到兩端 |
| `nanotime_part_notz(nanotimestamp) → bigint` | 同上，用於不含時區的型別 |
| `nanotime_part8(nanotimestamptz8) → bigint` | 8 B 型別的恆等映射，設了它才能使用 `set_integer_now_func` |

三個分區函數的名稱不同，因為 TimescaleDB 用不含型別的函數名稱查找分區函數，同名多載會出現 `more than one function named` 錯誤。

## 範例一：8 B 型別（大量 tick 資料，手動設定）

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

## 範例二：16 B 型別（需要 1677–2262 以外的範圍，手動設定）

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
