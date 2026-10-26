# pg_nanotime 發展規劃（Roadmap）

整理日期：2026-10-26（Asia/Taipei）。目前版本：0.2.0（已發布到 GitHub 與 [PGXN](https://pgxn.org/dist/pg_nanotime/)）；0.3.0 的範圍型別與 TimescaleDB 一鍵設定已完成、尚未釋出。

這份文件記錄「接下來要做什麼、為什麼這樣排、哪些決定不做」，讓之後接手的人（包括未來的自己）不必重新討論一次。每完成一項，就在清單上打勾，並同步更新 [CHANGELOG.md](../CHANGELOG.md) 和 [COVERAGE.md](COVERAGE.md)。

## 一、規劃原則

1. **定位清楚，不過度設計。** pg_nanotime 處理的是「奈秒精度的時間點與固定長度的時間量」。月、年這類日曆單位交給 PostgreSQL 內建的 `interval`；和時間無關的功能另外開專案，不塞進這個擴充。
2. **從日常需求出發。** 先做使用者馬上用得到的功能，再做進階、少數人才需要的。每個新功能至少搭配一個貼近生活的案例教學，案例同時也是測試。
3. **小步前進，向下相容。** 新函式放進升級腳本（例如 `pg_nanotime--0.2.0--0.3.0.sql`），讓既有使用者用 `ALTER EXTENSION pg_nanotime UPDATE` 升級；CI 檢查「升級後」與「全新安裝」的物件完全一致。
4. **不重複驗證。** 已經在 COVERAGE.md 記錄為通過的功能不重測；只有程式碼變動時才跑 PG 17／18 完整測試，純文件變更由 CI 自動略過。
5. **先確認現況，再決定要不要做。** 動手前先查 PostgreSQL 新版本或其他擴充是否已經提供，避免重複造輪子。

## 二、已經具備、暫不擴充的部分

討論時想到的幾個點子，查過後發現 0.2.0 已經有了，記在這裡避免重複規劃：

| 功能 | 現況 |
|---|---|
| 奈秒分桶 | `time_bucket_ns()` 已支援三種時間型別 |
| 二進位傳輸 | 三種時間型別與 `nanointerval` 都有 send／recv |
| TimescaleDB 基本支援 | `nanotime_part()`、`nanotime_part8()`、`ns()`、`nanotime_now_int8()`，用法見 [TIMESCALEDB.md](TIMESCALEDB.md) |
| TAI 時鐘來源 | GUC `nanotime.clock_source = tai` 已實作 |

### 關於閏秒與 TAI 的決定

2022 年國際度量衡大會（CGPM）決議最晚在 2035 年前停止加入閏秒，而且 2017 年以後就沒有再加過。這代表 UTC 與 TAI 之後會固定相差 37 秒，TAI 的實用價值大幅下降。

**決定：** 保留現有的 `nanotime.clock_source = tai`（已實作，不移除以免破壞相容性），但**不再投入**閏秒處理或「實際 37 秒偏移」的驗證環境（chrony／ptp4l）。除非有使用者明確需要，否則維持現狀。

## 三、待辦清單

### 優先 1：時間範圍型別 `nanotstzrange`（目標 0.3.0）

**為什麼：** 「這段時間有沒有重疊」是非常普遍的需求，例如會議室、機台、GPU、直播時段不能重複預約。PostgreSQL 內建的 `tstzrange` 只到微秒，而高頻交易、量測、封包分析需要奈秒級的區間。

- [x] 用 `CREATE TYPE ... AS RANGE` 定義 `nanotstzrange`（以 `nanotimestamptz` 為子型別），並加上 `nanotsrange`（`nanotimestamp`）；8 bytes 版不做（`nanotimestamptz8` 可隱含轉型後直接使用）
- [x] 提供 subtype_diff 函式，讓 GiST 索引能有效率地估算（回傳秒，與 `tstzrange_subdiff` 相同；沒有 canonical 函式，與 `tstzrange` 一樣是連續型）
- [x] 確認內建的範圍運算子（`&&`、`@>`、`<@`、`-|-` 等）、`range_agg`、multirange 都能正常運作
- [x] GiST 索引與排他約束（`EXCLUDE USING gist (資源 WITH =, 時段 WITH &&)`），搭配 `btree_gist`
- [x] 回歸測試 `range`（PG 17.11／18.6 通過），並更新 COVERAGE.md
- [x] 案例教學一篇：「共用儀器預約不撞期」（案例 16）
- [x] 文件：TECHNICAL.md、GUIDE.md、EXAMPLES.md

**範圍外：** 不自訂新的範圍運算子；PostgreSQL 內建的範圍機制已經足夠。

### 優先 2：TimescaleDB 一鍵設定輔助函式（目標 0.3.0，已完成）

**為什麼：** 目前用 TimescaleDB 有兩個容易踩到的坑，寫在文件裡但仍然常被忽略：
1. 使用 `partition_func` 時，預設索引建在分區運算式上，查詢時間欄位需要自己再建 `(ts DESC)` 索引。
2. `drop_chunks` 的時間參數需要加 `::bigint`。

- [x] `nanotime_timescale_setup(tbl regclass, col name, chunk nanointerval DEFAULT '1 day', migrate_data bool DEFAULT false)`：一次完成建立 hypertable（三種型別都用對應的分區函數）、`set_integer_now_func` 與補上 `(ts DESC)` 索引（已有等效索引時沿用）
- [x] `nanotime_drop_chunks(tbl, older_than nanotimestamptz, newer_than nanotimestamptz)`：免去手動轉型
- [x] 沒有安裝 TimescaleDB 時給出清楚的錯誤訊息（擴充本身不依賴 TimescaleDB，用動態 SQL 呼叫；回歸測試 `timescale_missing`）
- [x] 測試（選用測試 `timescale`，TimescaleDB 2.31.0、PG 17.11／18.6 通過）與 TIMESCALEDB.md 更新；案例 7「工廠感測器」補上一鍵設定一節

### 之後再評估（有人需要再做）

| 點子 | 暫緩原因 |
|---|---|
| PTP／硬體時鐘來源 | 需要特定網卡與環境，使用者少 |
| ULID／UUIDv7 產生器 | PG 18 已內建 `uuidv7()`，要先確認還有什麼不足 |
| 查詢延遲直方圖 | 和時間型別無關，適合另開專案，可與 PG 監控工作結合 |
| 閏秒處理、TAI 實際偏移驗證 | 閏秒將停用，見上方的決定 |

## 四、每一項功能的完成標準

1. 程式碼放在新版本的安裝腳本與升級腳本，CI 的升級與全新安裝一致性檢查通過。
2. PG 17 與 PG 18 回歸測試全部通過。
3. COVERAGE.md 在同一個 commit 更新（依 [CONTRIBUTING.md](../CONTRIBUTING.md) 的規則）。
4. 至少一篇案例教學，並更新 CHANGELOG.md。
5. 發布時同步更新 GitHub Release 與 PGXN。
