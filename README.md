# pg_nanotime

[![CI](https://github.com/bunko666-cloud/pg_nanotime/actions/workflows/ci.yml/badge.svg)](https://github.com/bunko666-cloud/pg_nanotime/actions/workflows/ci.yml)　原始碼：<https://github.com/bunko666-cloud/pg_nanotime>　授權：PostgreSQL License　[English](#english)

**讓 PostgreSQL 記錄到「奈秒」的時間。**

PostgreSQL 內建的時間最細只到微秒（百萬分之一秒）。對大多數應用已經夠用，但有些場景在一微秒內就會發生好幾件事：

- 交易系統一秒可能有上百萬筆報價，只記到微秒時，很多筆會「同一時間」，分不出先後。
- 量測網路或程式延遲時，差距常常只有幾百奈秒（1 奈秒 = 十億分之一秒），微秒精度會直接被四捨五入掉。
- 網路封包、感測器、科學儀器本身就輸出奈秒時間，存進資料庫時不該丟掉精度。

pg_nanotime 提供奈秒精度的時間型別，以及能自動填入「現在時間」的函式，還能保證時間嚴格遞增、絕不重複。它的靈感來自 [timestamp9](https://github.com/optiver/timestamp9)，並在此基礎上進一步發展。超出範圍時會明確報錯，不會悄悄算錯。只支援 PostgreSQL 17 與 18。

## 三步驟上手

**1. 安裝**（需要 PostgreSQL 開發套件與 C 編譯器，例如 Debian/Ubuntu 的 `postgresql-server-dev-18`）

```sh
git clone https://github.com/bunko666-cloud/pg_nanotime && cd pg_nanotime
make && sudo make install
```

**2. 在資料庫中啟用**

```sql
CREATE EXTENSION pg_nanotime;
```

**3. 建一張會自動記錄奈秒時間的表**

```sql
CREATE TABLE events (
  id   bigserial PRIMARY KEY,
  ts   nanotimestamptz NOT NULL DEFAULT clock_ns(),  -- 寫入時自動填入現在時間（奈秒）
  note text
);
INSERT INTO events(note) VALUES ('hello');
SELECT ts, note FROM events;   -- 例如 2026-10-23 09:00:00.123456789+08
```

## 該用哪一種型別？

| 型別 | 什麼時候用 | 大小 |
|---|---|---|
| `nanotimestamptz` | **預設選擇。**記錄「某個真實發生的時刻」，顯示時會換算成你的時區。年份範圍與 PostgreSQL 內建時間相同。 | 16 bytes |
| `nanotimestamptz8` | 資料量非常大（例如每天上億筆 tick），想省空間，或要搭配 TimescaleDB。範圍限於 1677–2262 年。 | 8 bytes |
| `nanotimestamp` | 不帶時區的「牆上時間」，例如排程表上的 09:00，不管在哪個時區都是 09:00。 | 16 bytes |
| `nanointerval` | 一段時間長度，例如延遲 `00:00:00.000041250`。兩個時間相減就會得到它。 | 16 bytes |

## 文件

- [使用指南（GUIDE）](docs/GUIDE.md)：依情境一步步說明，包含常見陷阱
- [實例集（EXAMPLES）](docs/EXAMPLES.md)：交易、撮合、封包、IoT、遷移的實際執行結果
- [技術文件（TECHNICAL）](docs/TECHNICAL.md)：完整功能、語意與設計細節
- [測試報告（TESTING）](docs/TESTING.md)：回歸測試、效能與相容性的實測數字
- [TimescaleDB 搭配使用（TIMESCALEDB）](docs/TIMESCALEDB.md)
- [CHANGELOG](CHANGELOG.md)、[CONTRIBUTING](CONTRIBUTING.md)

<a id="english"></a>
## 致謝與 AI 協作說明

本專案由 kanazawa bunko 主導與維護，並在 AI 助理 Grok Bot 的協助下開發。設計討論、程式碼、測試與文件都有 AI 參與；所有變更都經過 PostgreSQL 17 與 18 上的自動化測試驗證，並由維護者審核後才發佈。

## English

pg_nanotime adds nanosecond-precision timestamps to PostgreSQL 17 and 18. Built-in timestamps stop at microseconds, which is not enough for trading ticks, latency measurement, packet captures or sensor data. It provides `nanotimestamptz` (the default choice; 16 bytes, full range), `nanotimestamptz8` (8 bytes, 1677–2262, TimescaleDB-friendly), `nanotimestamp` (without time zone) and `nanointerval`. It also provides clock functions usable as `DEFAULT` (`clock_ns()`, `now_ns()`), and strictly increasing clocks (`clock_ns_monotonic()`, `clock_ns_global()`). It was inspired by timestamp9 and builds on that idea; out-of-range values raise errors instead of wrapping around. Quick start: `make && sudo make install`, then `CREATE EXTENSION pg_nanotime;`. The docs are in Traditional Chinese; the full English summary is in [docs/TECHNICAL.md](docs/TECHNICAL.md#english).

**Acknowledgements.** Maintained by kanazawa bunko and developed with the help of the AI assistant Grok Bot, which contributed to the design, code, tests and documentation. Every change is verified by the automated test suite on PostgreSQL 17 and 18 and reviewed by the maintainer before release.
