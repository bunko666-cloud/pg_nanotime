# pg_nanotime 功能與測試涵蓋表（COVERAGE）

這份文件把 pg_nanotime 的所有物件（型別、函式、轉型、運算子、聚合、索引 opclass、GUC）和「已經驗證過的測試」整理在一起。整理日期：2026-10-23（Asia/Taipei），對應 0.2.0 版本；2026-10-26 加入 0.3.0（尚未釋出）的範圍型別 `nanotstzrange`／`nanotsrange` 與 TimescaleDB 一鍵設定函式。

## 1. 用途與用法

- **查「這個功能有沒有測過、在哪裡測」**：找到物件所在的表格，看「回歸測試」欄。
- **改了東西要重跑什麼**：看 [§10 變更影響指南](#10-變更影響指南)。原則是「改到 X，就重跑涵蓋 X 的測試」，不需要每次重做所有額外測試。
- **已驗證的項目不必重測**：表中標為已驗證的項目（回歸測試在 PG 17.11 與 18.6 通過、CI 通過，或 [TESTING.md](TESTING.md) 中的實測），只要相關程式碼沒改，就不用重跑。效能、timestamp9 對照、20 萬列遷移等額外測試只在改到相關程式碼時才重做。
- **缺口**：沒有回歸測試的物件集中列在 [§9](#9-沒有回歸測試的物件缺口)，新增測試時優先補這些。

這份表是由 `sql/pg_nanotime--0.2.0.sql`（0.3.0 新增部分見 `sql/pg_nanotime--0.2.0--0.3.0.sql`）逐一列舉物件，再用 `test/sql/*.sql` 的內容比對整理而成；「回歸測試」欄是依測試 SQL 實際寫到的呼叫判斷的（人工檢查過多載與運算子方向）。整理時沒有重跑任何測試。

### 物件數量（0.3.0）

| 類別 | 數量 | 說明 |
|---|---:|---|
| 型別 | 8（+8 個陣列型別） | `nanotimestamptz`、`nanotimestamptz8`、`nanotimestamp`、`nanointerval`；0.3.0 新增範圍型別 `nanotstzrange`、`nanotsrange` 與自動建立的 `nanotstzmultirange`、`nanotsmultirange` |
| 函式（`CREATE FUNCTION`） | 159 + 4 | 對使用者的 42 個；轉型函式 20 個；其餘 97 個是 I/O、比較、運算子實作、聚合支援等內部函式；0.3.0 新增 2 個 subtype_diff（`nanotimestamptz_subdiff`、`nanotimestamp_subdiff`）與 2 個 TimescaleDB 輔助（`nanotime_timescale_setup`、`nanotime_drop_chunks`） |
| 範圍型別自動建立的建構函式 | 10 | `nanotstzrange(a,b[,text])`、`nanotsrange(a,b[,text])`、`nanotstzmultirange(…)` 與 `nanotsmultirange(…)` 各 3 個（0.3.0） |
| 程序（`CREATE PROCEDURE`） | 1 | `nanotime_migrate_column` |
| 聚合 | 10 | 4 型別各 `min`/`max`，加上 `sum(nanointerval)`、`avg(nanointerval)` |
| 轉型（`CREATE CAST`） | 24 + 2 | 0.3.0 自動建立 range → multirange 轉型 2 個 |
| 運算子 | 57 | 比較 24（4 型別 × 6），算術 33 |
| 運算子類別（opclass） | 11 | B-tree 4、hash 4、BRIN minmax 3；另有 11 個隨之建立的 operator family |
| GUC | 2 | `nanotime.clock_source`、`nanotime.debug_clock_offset_us` |

交叉核對：0.3.0 擴充套件相依的物件共 305 個（`pg_depend`，與 `\dx+ pg_nanotime` 的 305 行一致，PG 17.11 與 18.6 相同）= 型別 16 + 函式／程序／聚合 184 + 運算子／opclass／operator family 79 + 轉型 26。0.2.0 是 281 個（型別 8、函式／程序／聚合 170、運算子類 79、轉型 24）。範圍運算子（`&&`、`@>` 等）與 GiST `range_ops` 是 PostgreSQL 內建的多型物件，不屬於擴充套件。

### 驗證版本的寫法

- **回歸測試**：除非另外註明，全部在 PG 17.11 與 18.6 通過（本機 `installcheck` 與 CI 的 PostgreSQL 17、18 兩個 job）。`timescale` 測試在 CI 的「TimescaleDB on PostgreSQL 17/18（optional）」job 執行（TimescaleDB 2.x）。
- **起始版本**：除非標 0.2.0 或 0.3.0，都是 0.1.0 就有。0.3.0 尚未釋出。
- **案例**：數字是 [案例目錄](#8-案例頁與教學涵蓋) 的編號，「教」= 教學頁。案例頁只在 PG 18.6 上執行。

## 2. 型別

| 物件 | 用途／應用 | 回歸測試 | 驗證版本 | 案例 | 已知限制／備註 |
|---|---|---|---|---|---|
| `nanotimestamptz`（16 B） | 絕對時刻，預設選擇；範圍 4714-11-24 BC～294276 AD | basic, io, casts, index, arith, bucket | PG17/18，0.1.0 | 1, 2, 4, 6, 教 | 不支援 infinity；輸出固定 ISO、9 位小數 |
| `nanotimestamptz8`（8 B） | int64 Unix 奈秒，與 bigint 二進位相同；大量資料、TimescaleDB 維度 | compact, arith, bucket, series, timescale | PG17/18，0.1.0 | 5, 6, 7, 12, 13, 14, 教 | 範圍 1677-09-21～2262-04-11，越界報錯 |
| `nanotimestamp`（16 B） | 不含時區的牆上時間 | notz, series | PG17/18，0.1.0 | 9, 教 | 輸入的時區偏移會被忽略 |
| `nanointerval`（16 B） | 固定奈秒長度，可正可負 | interval, arith, agg, series | PG17/18，0.1.0 | 4, 11–15, 教 | 不接受月、年；範圍對稱 ±約 9.4e21 ns |
| `nanotstzrange` | `nanotimestamptz` 的範圍：預約、量測視窗、時段不重疊 | range, examples | PG17/18，**0.3.0** | 16 | 連續型（沒有 canonical，和 `tstzrange` 一樣），建議半開區間 `[)`；沒有 infinity 邊界，用無邊界寫法 |
| `nanotsrange` | `nanotimestamp` 的範圍（不含時區） | range | PG17/18，**0.3.0** | — | 同上 |
| `nanotstzmultirange`／`nanotsmultirange` | 多段時段（`range_agg` 的結果、空檔計算） | range, examples | PG17/18，**0.3.0** | 16 | CREATE TYPE AS RANGE 自動建立 |

I/O（文字與 binary send/recv）：io（16 B）、compact（8 B）、notz、interval 都有 COPY binary 往返；range 測試涵蓋 `nanotstzrange`、`nanotstzmultirange`、`nanotsrange` 的 COPY binary 往返。

## 3. 函式與程序（對使用者）

### 時鐘

| 物件 | 用途／應用 | 回歸測試 | 驗證版本 | 案例 | 已知限制／備註 |
|---|---|---|---|---|---|
| `clock_ns()` / `clock_ns8()` | 每次呼叫讀牆鐘；DEFAULT | clocks, compact, migrate, examples | PG17/18 | 1, 2, 4, 教 | 可能重複、可能隨 NTP 倒退 |
| `statement_ns()` / `statement_ns8()` | 陳述式開始時間 | clocks, compact | PG17/18 | 2, 教 | |
| `now_ns()` / `now_ns8()` | 交易開始時間 | clocks, compact, examples, timescale | PG17/18 | 2, 教 | 與 `now()` 是不同的讀取，通常晚幾 µs；不要混用 |
| `clock_ns_monotonic()` / `clock_ns8_monotonic()` | 同一連線內嚴格遞增 | monotonic, examples | PG17/18 | 3 | 20 萬次呼叫、模擬時鐘倒退 2 秒 |
| `clock_ns_global()` / `clock_ns8_global()` | 所有連線間嚴格遞增、不重複 | global（有 preload：global.out；沒有：global_1.out） | PG17/18；global_1.out 本機只在 PG18 產生過，CI 兩版都跑 | 1, 6, 教 | 需要 `shared_preload_libraries`；保證呼叫順序，不是 commit 順序；重啟後重新開始 |
| `nanotime_clock_status()` | 時鐘監控計數 | monotonic, global | PG17/18 | 1, 3, 6, 教 | |
| `nanotime_reset_stats()` | 計數歸零 | monotonic（含權限） | PG17/18 | 教 | 預設限 superuser |

### 時間運算與工具

| 物件 | 用途／應用 | 回歸測試 | 驗證版本 | 案例 | 已知限制／備註 |
|---|---|---|---|---|---|
| `time_bucket_ns(width, ts [, origin])`（3 個多載） | 固定長度分桶，向下取整 | bucket, notz, examples, timescale | PG17/18 | 5, 11, 14, 教 | 寬度必須 > 0；1970 以前也正確 |
| `date_trunc(unit, ts [, zone])`（5 個多載） | 日曆截斷 | bucket, notz | PG17/18 | 教 | |
| `extract_ns(field, ts \| nanointerval)`（3 個多載） | 取代 `EXTRACT`，回傳 numeric | bucket, notz, monotonic | PG17/18 | 2, 14, 15, 教 | `nanotimestamptz8` 透過隱式轉型到 16 B 版本 |
| `timezone(zone, ts)`（2 個多載） | 取代 `AT TIME ZONE` | notz | PG17/18 | 2, 9, 教 | |
| `interval(nanointerval)`、`timestamp(nanotimestamp)` | 明確函式寫法的轉型 | arith, notz | PG17/18 | 15 | |
| `nanointerval_ns(nanointerval)` | → numeric 奈秒，精確 | interval, agg | PG17/18 | 15 | |
| `nanointerval_from_ns(numeric)` | numeric 奈秒 → nanointerval，四捨五入遠離 0 | interval, agg, series | PG17/18，0.1.0 | 4, 15 | NaN／Infinity 錯誤訊息 0.2.0 改為 `cannot convert NaN/infinity to nanointerval` |
| `nanointerval_from_ns(bigint)` | 精確；讓整數參數不走 double | series | PG17/18，**0.2.0** | — | |
| `nanointerval_from_ns(double precision)` | 浮點奈秒 → nanointerval | series | PG17/18，**0.2.0** | 14, 15 | 超過 2^53 ns 失去精度；NaN／Infinity 報錯 |
| `abs(nanointerval)` | 絕對值 | series | PG17/18，**0.2.0** | 9, 14 | 範圍對稱，不會溢位 |
| `generate_series(start, stop, nanointerval)`（3 個多載） | 產生奈秒時間格線 | series | PG17/18，**0.2.0** | 14 | 語意同 PG：含 stop、step 0 報錯、負 step 往回數；範圍邊緣不繞回；附 planner support（常數參數時列數精確） |

### TimescaleDB 整合

| 物件 | 用途／應用 | 回歸測試 | 驗證版本 | 案例 | 已知限制／備註 |
|---|---|---|---|---|---|
| `nanotime_part(nanotimestamptz)` | 16 B 分區函數，飽和映射到 int64 | timescale | CI TimescaleDB job（PG17/18） | 教 | 超出範圍的值集中到兩端 chunk |
| `nanotime_part8(nanotimestamptz8)` | 8 B 恆等映射 | timescale | 同上 | 7, 教 | 設了它之後 `drop_chunks` 要用 bigint |
| `nanotime_part_notz(nanotimestamp)` | 無時區版本 | timescale | 同上 | — | |
| `ns(nanointerval)` | → bigint，給 chunk 間隔等參數 | timescale | 同上 | 7, 教 | |
| `nanotime_now_int8()` | 給 `set_integer_now_func` | timescale | 同上 | 7, 教 | 需要 `partition_func` |
| `nanotime_timescale_setup(regclass, name, nanointerval, bool)` | 一鍵建立 hypertable：依型別選分區函數、chunk 轉奈秒、設 integer now、補 `(col DESC)` 索引（有等效索引就沿用） | timescale（成功路徑、計畫、錯誤）、timescale_missing（沒有 TimescaleDB） | timescale：TimescaleDB 2.31.0 + PG 17.11／18.6（本機）與 CI 選用 job；timescale_missing：PG17/18，**0.3.0** | 7 | 需要 TimescaleDB 2.13+ 的 `by_range()`；8 B 也用 `nanotime_part8`（原生維度保留策略會失敗）；不建 TimescaleDB 預設索引 |
| `nanotime_drop_chunks(regclass, nanotimestamptz, nanotimestamptz)` | `drop_chunks` 包裝，直接給奈秒時間 | timescale、timescale_missing | 同上，**0.3.0** | 7 | 讀 `_timescaledb_catalog.dimension`（內部目錄）；無時區表依 session 時區換算；早於 int64 下限回傳空集合 |

### 範圍型別（0.3.0）

| 物件 | 用途／應用 | 回歸測試 | 驗證版本 | 案例 | 已知限制／備註 |
|---|---|---|---|---|---|
| `nanotimestamptz_subdiff`、`nanotimestamp_subdiff` | 範圍的 subtype_diff：回傳秒（float8），GiST penalty／picksplit 與 `ANALYZE` 範圍統計使用 | range（含 1 ns 差距不失準、與 `tstzrange_subdiff` 同單位） | PG17/18，**0.3.0** | — | 相差數十年時 float8 表示不到奈秒，只影響估算，不影響判斷結果 |
| 建構函式 `nanotstzrange(a,b[,bounds])`、`nanotsrange(…)`、`nanotstzmultirange(…)`、`nanotsmultirange(…)` | 組成範圍 | range, examples | PG17/18，**0.3.0** | 16 | `nanotimestamptz8`、`timestamptz` 經隱含轉型可直接傳入；lower > upper 報錯 |
| 內建範圍運算子與函式：`&& @> <@ -\|- << >> &< &> + * -`、`lower`／`upper`／`isempty`／`*_inc`／`*_inf`、`range_merge`、`range_agg`、`range_intersect_agg`、`unnest(multirange)` | PG 內建多型機制 | range（奈秒邊界：`[t,t+1ns)` 與 `[t+1ns,…)` 相鄰不重疊；只差 1 ns 的範圍不相等）, examples | PG17/18 | 16 | 不自訂新的範圍運算子 |
| GiST `range_ops`、`EXCLUDE USING gist (x WITH =, during WITH &&)` | 時段不重疊、範圍查詢走索引 | range（EXPLAIN 確認 `&&`、`@>` 走 GiST；只重疊 1 ns 的預約被拒絕）, examples | PG17/18 | 16 | `x WITH =` 需要 `btree_gist` |
| B-tree／hash（內建 `range_ops`） | 排序、`DISTINCT`、`GROUP BY` | range | PG17/18 | — | |

### 遷移

| 物件 | 用途／應用 | 回歸測試 | 驗證版本 | 案例 | 已知限制／備註 |
|---|---|---|---|---|---|
| `nanotime_migrate_column(tbl, col [, target, new_default, dry_run])`（程序） | 一個 ALTER TABLE 完成欄位遷移，索引重建 | migrate, examples | PG17/18（PG17 用名為 timestamp9 的 bigint domain 模擬）；真實 timestamp9 20 萬列只在 PG18（TESTING §7） | 8, 教 | 舊預設值無法轉換時報錯並提示 `new_default` |
| `nanotime_migration_expr(src, target, col)` | 只產生 USING 運算式 | migrate | PG17/18 | 8 | |
| `nanotime_suspect_count(tbl, col, lo, hi)` | 時間窗外的列數 | migrate | PG17/18 | 8, 教 | 無法偵測落在窗內的 timestamp9 繞回值 |

## 4. 聚合

| 物件 | 用途／應用 | 回歸測試 | 驗證版本 | 案例 | 已知限制／備註 |
|---|---|---|---|---|---|
| `min` / `max`（4 型別各一，共 8 個） | 最小／最大，可平行 | basic, agg（nanointerval） | PG17/18，0.1.0 | 11, 14, 教 | |
| `sum(nanointerval)` | int128 精確累加，溢位報錯 | agg | PG17/18，**0.2.0** | 11, 14 | 支援平行（combine/serialize）與移動聚合 |
| `avg(nanointerval)` | 平均，四捨五入到奈秒（遠離 0） | agg, examples | PG17/18，**0.2.0** | 11, 14 | 同上 |
| `percentile_disc(…) WITHIN GROUP (ORDER BY nanointerval)` | PG 內建聚合，只要排序 | coverage（含陣列版本、NULL、`percentile_cont` 報錯） | PG17/18 | 5, 9, 11, 14 | `percentile_cont` 不支援 nanointerval（需要內插），要先 `::bigint` |

## 5. 轉型

| 從 → 到 | 情境 | 回歸測試 | 案例 | 備註 |
|---|---|---|---|---|
| `timestamptz → nanotimestamptz` | IMPLICIT | casts, arith | 2, 教 | 精確。因為是隱式，`clock_ns() - now()` 不會報錯（混用要靠慣例避免） |
| `nanotimestamptz → timestamptz` | ASSIGNMENT | casts | 教 | 向下取整到 µs |
| `bigint ↔ nanotimestamptz` | EXPLICIT | casts | 教 | 1970 起奈秒，超出 int64 報錯 |
| `nanotimestamptz8 → nanotimestamptz` | IMPLICIT | compact | 5 | |
| `nanotimestamptz → nanotimestamptz8` | ASSIGNMENT | compact | 15 | 越界報錯 |
| `nanotimestamptz8 ↔ timestamptz` | ASSIGNMENT | compact | — | 轉出時 floor |
| `bigint ↔ nanotimestamptz8` | EXPLICIT（WITHOUT FUNCTION） | compact | 7, 15 | 零成本 |
| `interval ↔ nanointerval` | ASSIGNMENT | interval | 10, 13, 15 | 含月份報錯；1 day = 24 h；轉出 floor 到 µs |
| `bigint ↔ nanointerval` | EXPLICIT | interval | 15 | |
| `timestamp ↔ nanotimestamp` | IMPLICIT／ASSIGNMENT | notz | — | |
| `date ↔ nanotimestamp` | IMPLICIT／ASSIGNMENT | notz | — | |
| `date ↔ nanotimestamptz` | ASSIGNMENT | notz | — | 依 session 時區 |
| `nanotimestamp ↔ nanotimestamptz` | IMPLICIT／ASSIGNMENT | notz | 9 | 依 session 時區 |
| `bigint ↔ nanotimestamp` | EXPLICIT | notz | — | |

沒有 `numeric → nanointerval` 轉型（刻意的），請用 `nanointerval_from_ns()`。

## 6. 運算子

| 物件 | 用途／應用 | 回歸測試 | 案例 | 已知限制／備註 |
|---|---|---|---|---|
| `= <> < <= > >=`（4 型別 × 6） | 比較、排序、索引 | basic, index, compact, notz, interval, coverage（其他 3 型別的 `<>`） | 全部 | |
| `ts - ts → nanointerval`（3 型別） | 時間差 | arith, compact, notz | 2, 4, 5, 9, 11, 14 | |
| `ts ± nanointerval`、`nanointerval + ts`（3 型別） | 固定奈秒加減 | arith, notz | 13, 教 | 越界報錯，不繞回 |
| `ts ± interval`（3 型別） | 日曆運算，依 session 時區 | arith, coverage（8 B 的 `-`）, notz | 13, 教 | |
| `interval + ts`（3 型別） | 交換律版本 | notz, coverage | — | |
| `nanointerval ± nanointerval`、一元 `-` | 長度加減 | interval, series | 13 | |
| `nanointerval * int4 \| int8 \| numeric`、反向 `int4 \| numeric * nanointerval` | 乘倍率 | interval, coverage（`bigint *`） | 13, 14 | smallint 會 operator is not unique |
| `nanointerval / int4 \| int8 \| numeric` | 除，四捨五入遠離 0 | interval, coverage（`/ bigint`） | 13 | |

## 7. 索引 opclass 與 GUC

| 物件 | 用途／應用 | 回歸測試 | 驗證 | 案例 | 已知限制／備註 |
|---|---|---|---|---|---|
| B-tree（4 型別，DEFAULT） | 範圍、排序、UNIQUE | index, compact, notz, interval, migrate | PG17/18；100 萬列大小與計畫在 PG18（教學 4.5） | 5, 6, 12, 教 | |
| hash（4 型別，DEFAULT） | 等值、hash join | index, compact, notz, interval, migrate | PG17/18 | 教 | 實測比 B-tree 大（32 MB vs 21 MB） |
| BRIN minmax（3 個時間型別） | 依時間追加的大表 | index, compact, notz | PG17/18 | 7, 教 | nanointerval 沒有 BRIN；minmax-multi、bloom 不支援 |
| 範圍型別的 GiST／B-tree／hash（內建 `range_ops`，0.3.0） | 時段不可重疊、範圍查詢 | range, examples | PG17/18 | 16, 教 | 0.3.0 起是正式功能（教學頁 4.5 原本用自訂 range 示範） |
| GUC `nanotime.clock_source`（realtime／tai） | 時鐘來源 | monotonic | PG17/18 | 10, 教 | 這台機器 TAI 偏移為 0，實際 37 秒差未驗證 |
| GUC `nanotime.debug_clock_offset_us` | 測試用：模擬時鐘倒退 | monotonic | PG17/18 | — | 限 superuser，不寫進設定檔範本 |

## 8. 案例頁與教學涵蓋

所有案例都在 PG 18.6 上實際執行；人物與部分資料為虛構或模擬。

| # | 案例 | 用到的功能 |
|---|---|---|
| 1 | 網購搶購 | `clock_ns_global()`、三種時鐘比較、`nanotime_clock_status()` |
| 2 | 外送與叫車 | `now()`／`clock_timestamp()` 對照 `now_ns()`／`statement_ns()`／`clock_ns()`、相減、`extract_ns`、`timezone()` |
| 3 | 線上遊戲 | `clock_ns_monotonic()`、local_bumps |
| 4 | 網站變慢了 | `nanointerval`、`nanointerval_from_ns` |
| 5 | 交易延遲 | `nanotimestamptz8`、`time_bucket_ns`、`percentile_disc`、B-tree 範圍查詢 |
| 6 | 分散式排序 | `clock_ns8_global()`、bumps、lead、commit 順序 |
| 7 | 工廠感測器 | hypertable、`nanotime_part8`、ts 索引、BRIN、`drop_chunks ::bigint`、保留策略、`nanotime_timescale_setup`／`nanotime_drop_chunks`（0.3.0，TimescaleDB 2.31.0） |
| 8 | timestamp9 搬家 | `nanotime_migrate_column`、dry_run、`nanotime_suspect_count`、new_default |
| 9 | 網路封包 | `nanotimestamp`、`abs(nanointerval)`（0.2.0）、`percentile_disc` 直接用在 nanointerval、`timezone()` |
| 10 | 科學實驗 | `nanotime.clock_source = tai`、閏秒、拒絕月份 |
| 11 | 咖啡店出餐 | `sum`／`avg`／`min`／`max`、`percentile_disc`、`time_bucket_ns`、視窗移動平均 |
| 12 | 客服時限 | nanointerval 比較、`FILTER`、部分索引 |
| 13 | 時間運算 | `ts ± nanointerval`、乘除與捨入、`least`、範圍錯誤、interval '1 month' 對照 |
| 14 | 心率缺口 | `lag()`、`sum`、`abs`、`generate_series` 格線（0.2.0）、`nanointerval_from_ns(double precision)` |
| 15 | 外部交換 | `::bigint`、`nanointerval_from_ns`（numeric／double）、`nanointerval_ns`、JSON、interval 互轉、NaN／Infinity 錯誤 |
| 16 | 共用儀器預約 | `nanotstzrange`、`EXCLUDE USING gist` + `btree_gist`、`@>`、`range_agg`、multirange 差集找空檔、奈秒邊界、GiST 索引（0.3.0） |
| 教 | 教學頁 | 型別、時鐘、分桶、date_trunc／extract_ns、索引支援矩陣與 100 萬列實測、TimescaleDB、遷移、常見錯誤、速查表 |

### 額外測試（[TESTING.md](TESTING.md)，已驗證，不必重跑）

| 測試 | 內容 | 環境 | 何時要重做 |
|---|---|---|---|
| timestamp9 1.4.0 行為紀錄（§3） | 邊界、繞回、取整 | PG18 | 不需要（對照組紀錄） |
| TimescaleDB 相容性（§4） | hypertable、chunk 排除、壓縮、drop_chunks、連續聚合不支援 | TimescaleDB 2.31.0、PG18 | 改分區函數或 TimescaleDB 大版本升級 |
| 效能基準（§5） | 10M／50M 列寫入、索引、查詢；時鐘每次呼叫成本 | PG18 | 改 I/O、比較函式、時鐘實作 |
| 16 B 佈局與 COPY（§6） | 佈局比較 | PG18 | 改儲存格式 |
| 遷移（§7） | 真實 timestamp9 20 萬列 + 邊界值、3 個索引、逐列比對 | PG18 | 改 `nanotime_migrate_column` |
| 嚴格遞增時鐘並行測試（§8） | 多連線 global 時鐘 | PG17/18 | 改 monotonic／global 實作 |
| 升級一致性 | 0.1.0 → 0.3.0、0.2.0 → 0.3.0 的 `\dx+` 與全新安裝相同（305 行；TimescaleDB 輔助函式的原始碼 md5 也相同） | CI（PG17/18）、本機 PG17.11／18.6（2026-10-26） | 每次改升級腳本（CI 自動檢查） |
| 文件範例一致性 | `docs/EXAMPLES.md` 與 `examples` 測試逐行一致 | CI「Docs examples」、`make check-docs` | 改 EXAMPLES 或 examples 測試（CI 自動） |

### CI

| Job | 內容 |
|---|---|
| PostgreSQL 17、PostgreSQL 18 | `-Werror` 建置、preload 下 `installcheck`、0.1.0／0.2.0→current 升級一致性、沒有 preload 的 `global` 測試 |
| TimescaleDB on PostgreSQL 17／18（optional） | `installcheck WITH_TIMESCALEDB=1` |
| Docs examples | `tools/check_examples.py` |

CI 的 `paths-ignore` 排除 `**.md` 與 `docs/**`，只改文件時不會觸發 CI（Docs examples 只在 EXAMPLES 相關檔案變動時觸發）。

## 9. 沒有回歸測試的物件（缺口）

原本列在這裡的 6 個運算子／聚合缺口（`interval + nanotimestamptz`／`nanotimestamptz8`、`nanotimestamptz8 - interval`、`bigint * nanointerval`、`nanointerval / bigint`、其他 3 型別的 `<>`、`percentile_disc` 直接用在 nanointerval）已在 0.2.0 由 `coverage` 測試補上（PG17.11／18.6 通過）。

目前剩下的都是無法或不適合放進回歸測試的項目：

| 物件 | 現況 | 建議 |
|---|---|---|
| 真實 timestamp9 遷移 | 回歸測試用 bigint domain 模擬；真實資料只在 PG18 手動測過 | CI 沒有 timestamp9 套件，維持手動 |
| `nanotime.clock_source = tai` 的實際偏移 | 機器 TAI 偏移為 0，只驗證了切換本身 | 需要設好 chrony／ptp4l 的環境 |
| `global_1.out`（沒有 preload） | 本機只在 PG18 產生；CI 兩版都跑 | — |

## 10. 已知限制與設計決策

- **nanointerval 不支援月、年**：長度不固定。日曆運算請用 `ts ± interval`（依 session 時區）。
- **單一時間點沒有 GiST／GIN opclass**（時段請用 0.3.0 的範圍型別，走內建 GiST `range_ops`），BRIN 只有 minmax（沒有 minmax-multi、bloom），nanointerval 沒有 BRIN。int8 的 opclass 也不能借給 `nanotimestamptz8` 用。
- **TimescaleDB 連續聚合不支援**這些型別（也不支援自訂分區函數）；需要時另存 bigint 欄位。`time_bucket` 不接受這些型別，請用 `time_bucket_ns` 或 `time_bucket(bigint, t::bigint)`。
- **`percentile_cont` 不支援 nanointerval**（需要內插）；`percentile_disc` 可以直接用。
- **`drop_chunks` 要 `::bigint`**：設了 `partition_func` 的 hypertable，`older_than` 必須是 bigint；沒設的 8 B hypertable 可直接給 `nanotimestamptz8`。0.3.0 的 `nanotime_drop_chunks` 會自動換算。
- **TimescaleDB 索引陷阱**：設了 `partition_func` 時預設索引建在 `nanotime_part8(ts)` 運算式上，以 `ts` 查詢用不到，請另建 `(ts DESC)`。0.3.0 的 `nanotime_timescale_setup` 會自動處理。
- **原生 8 B 維度的保留策略**：`add_retention_policy` 建得起來，但執行時報 `interval field value out of range`（TimescaleDB 2.31.0），要用保留策略請設 `nanotime_part8`。
- **隱式 `timestamptz → nanotimestamptz`**：方便沿用既有資料，但擴充套件不會阻止混用 `now()` 與奈秒欄位；這是使用慣例。
- **不帶型別的 `'1 day'`** 會被解析成內建 interval（日曆語意、µs 精度）；固定長度要寫 `::nanointerval`。
- **`smallint * nanointerval`** 會 operator is not unique，請先轉 int。
- **不支援 infinity**；不支援閏秒；`EXTRACT`／`AT TIME ZONE` 語法寫死在 PG 裡，改用 `extract_ns()`／`timezone()`。
- **越界一律報錯**，不繞回（與 timestamp9 的行為不同，見 TESTING §3）。
- **`nanointerval_from_ns(double precision)`** 超過 2^53 ns 失去精度；精確請用 bigint 或 numeric。
- **範圍型別是連續型、沒有 canonical 函式**（與 `tstzrange` 一致）：`[t, t+1ns]` 與 `[t, t+2ns)` 包含相同時間點但不相等，`[t, t+1ns]` 與 `[t+2ns, …)` 的 `-|-` 是 false；請一律用半開區間 `[)`。
- **subtype_diff 的單位是秒（float8）**，與 `tstzrange_subdiff` 相同；先以 int128 精確相減再轉換。
- **不提供 8 B 範圍型別**：`nanotimestamptz8` 會隱含轉成 `nanotimestamptz`，直接用 `nanotstzrange`。

## 11. 變更影響指南

| 改到 | 要重跑 | 不必重跑 |
|---|---|---|
| I/O（輸入解析、輸出格式、send/recv） | io, compact, notz, interval, examples；`make check-docs`；考慮 TESTING §5 COPY 數字 | 時鐘、遷移、TimescaleDB 實測 |
| 比較函式、hash、opclass | basic, index, compact, notz, interval, coverage, migrate；必要時重量教學 4.5 的大小 | 時鐘 |
| 算術、捨入、溢位（`nt_total`、`ni_make` 等） | arith, interval, agg, series, coverage, bucket, notz | 時鐘、遷移實測 |
| 聚合（sum/avg 狀態、combine、serialize） | agg（含平行與移動聚合）, coverage, examples | 其他 |
| `generate_series` 或其 support 函式 | series | 其他 |
| 時鐘（clock／monotonic／global、GUC） | clocks, monotonic, global（有 preload 與沒有 preload 兩次）, compact；TESTING §5 時鐘成本、§8 並行 | I/O、遷移 |
| 轉型 | casts, compact, notz, interval, migrate | 時鐘 |
| 分區函數、`ns()`、`nanotime_now_int8` | timescale（`WITH_TIMESCALEDB=1`）；TESTING §4 | 其他 |
| `nanotime_timescale_setup`／`nanotime_drop_chunks` | timescale（`WITH_TIMESCALEDB=1`，實際 TimescaleDB）、timescale_missing；升級一致性 | 時鐘、遷移、範圍型別 |
| 遷移程序／函式 | migrate, examples；真實 timestamp9 20 萬列（TESTING §7，PG18） | 其他 |
| 安裝／升級腳本 | 全部 `installcheck`（PG17、18，重啟叢集）、升級後 `\dx+` 與全新安裝一致 | — |
| 範圍型別或 subtype_diff | range, examples；升級一致性 | 時鐘、遷移、TimescaleDB |
| 只改文件 | `make check-docs`（改到 EXAMPLES 時） | 所有回歸測試 |

所有回歸測試都要在 PG 17 與 18 各跑一次；library 有 preload，安裝新的 `.so` 後要重啟叢集。

## 12. 維護規則

- **功能變更要在同一個 commit 更新這份文件**：新增或修改物件時，更新對應表格的「回歸測試」「驗證版本」「備註」欄；補上測試的缺口要從 §9 移除。
- 新增物件後，請核對 §1 的物件數量與 `\dx+ pg_nanotime` 的行數。
- 只寫實際執行過的結果；沒測過就寫「無」，不要推測。
