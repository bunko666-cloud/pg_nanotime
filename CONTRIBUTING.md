# 參與開發 / Contributing

- 支援範圍：只支援 PostgreSQL 17 與 18。請不要加入舊版相容碼。
- 建置：PGXS。換 PG 版本前要先 `make clean`，因為 `.so` 依版本編譯。
- 測試：
  - 每個 PR 都要通過 `make installcheck`。
  - 改動時鐘相關功能時，有 preload 和沒有 preload 各跑一次（`global` 測試有兩份預期結果）。
  - TimescaleDB 相關改動請加跑 `WITH_TIMESCALEDB=1`。
- 新功能要附上 `test/sql/*.sql` 與 `test/expected/*.out`。更新 expected 檔前，請逐行檢查差異。
- `docs/EXAMPLES.md` 的內容取自 `test/sql/examples.sql` 與 `test/expected/examples.out`；修改實例時，兩邊要一起更新。
- 效能數字請寫進 `docs/TESTING.md`，並註明環境與執行次數。只放實際量測的數字，不放估算值。
- 程式風格：沿用 PostgreSQL 的 C 風格（tab 縮排、宣告放在區塊開頭），編譯時不能有警告（CI 用 `-Werror`）。
- 授權：送出的貢獻以 PostgreSQL License 授權。

English: PG 17/18 only. Every change must pass `make installcheck`, both with and without `shared_preload_libraries` when touching clocks. Add regression tests for new features, keep the build warning-free (CI uses `-Werror`), and report only measured numbers. Contributions are under the PostgreSQL License.
