# pg_nanotime

PostgreSQL 奈秒精度時間戳擴充套件，作為 [timestamp9](https://github.com/optiver/timestamp9) 的替代方案。授權：PostgreSQL License。

> 狀態：**Phase 1（v0.1.0，開發中）**。目前僅在 PostgreSQL 18.6 上建置與測試；PG 13–17 為目標但尚未驗證。

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

## 運算子與索引

- `< <= = <> >= >`、`min()`/`max()`、`greatest`/`least`。
- B-tree（預設）與 hash（預設）運算子類別；`=` 支援 hash join 與 merge join。

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

## 建置與測試

```sh
make
sudo make install
make installcheck PGHOST=/tmp PGPORT=5499 PGUSER=postgres
```

測試（`test/sql`）：`basic`（範圍邊界、1970 前、比較）、`io`（小數位數、時區、BC、二進位往返）、`casts`（floor 取整、bigint 邊界與溢位錯誤）、`clocks`（易變性、DEFAULT）、`index`（B-tree/hash 索引使用）。

## 尚未完成（下一步）

- 8 bytes 精簡型別（int64 Unix 奈秒，1677–2262）。
- `nanointerval`（固定奈秒）與算術運算子、`ts - ts`。
- `date_trunc`/`time_bucket` 類函式、BRIN 運算子類別、`infinity`。
- PG 13–17 建置矩陣驗證。
