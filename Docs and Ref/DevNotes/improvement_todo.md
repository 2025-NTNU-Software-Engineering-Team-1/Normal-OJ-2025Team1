# 系統改進待辦清單

**更新時間:** 2025-12-01  
**來源:** Code Review + 系統優化需求

---

## 🔴 高優先級 (必須修復)

**所有高優先級問題已修復!** ✅

---

## 🟡 中優先級 (建議修復)

### Custom Checker 改進

- [x] ~~增加 checker asset 存在性驗證~~ ✅ **已修復** (Line 25-34 in custom_checker.py)
- [x] ~~調整 Checker 時間限制~~ ✅ **已修復** (Line 36 in custom_checker_runner.py, 現為 5倍且最少5秒)
- [ ] **上傳時驗證 Python 語法**
  - **檔案:** `Back-End/mongo/problem/problem.py` (update_assets)
  - **改進:** 使用 `ast.parse()` 驗證 custom_checker.py 語法

### Backend 資料一致性

- [ ] **Interactive 模式強制禁用 customChecker**
  - **檔案:** `Back-End/mongo/problem/problem.py` (edit_problem 函數, around line 558-559)
  - **問題:** 當切換到 interactive 模式時,backend 不會自動將 customChecker 設為 false
  - **修正:** 
    ```python
    if 'executionMode' in pipeline:
        full_config['executionMode'] = pipeline['executionMode']
        if pipeline['executionMode'] == 'interactive':
            full_config['customChecker'] = False
    ```

### Redis 快取優化

- [ ] **Custom Checker 檔案快取優化**
  - **目標:** 減少重複下載 checker.py 的頻率
  - **實作位置:** `Sandbox/dispatcher/custom_checker.py`
  - **方案:**
    - 將 checker 檔案快取到 Redis (key: `checker:{problem_id}`, TTL: 1小時)
    - 檢查 Redis 快取，若存在且 ETag 匹配則直接使用
    - 否則從 Backend 下載並更新 Redis 快取
  - **預期效益:** 減少 Minio 請求次數，提升 submission 處理速度

- [ ] **Problem Meta 快取優化**
  - **目標:** 減少 `/api/problem/<id>/meta` 的重複請求
  - **實作位置:** `Sandbox/dispatcher/testdata.py` (fetch_problem_meta)
  - **方案:**
    - 快取 problem meta 到 Redis (key: `problem_meta:{problem_id}`, TTL: 10分鐘)
    - 當 problem 更新時清除對應快取
  - **預期效益:** 減少 Backend 負載，加快 meta 獲取速度

- [ ] **Testdata 快取策略**
  - **目標:** 優化測資檔案的快取機制
  - **實作位置:** `Sandbox/dispatcher/testdata.py`
  - **方案:**
    - 使用 Redis 儲存測資 checksum (key: `testdata_checksum:{problem_id}`)
    - 僅在 checksum 改變時重新下載測資
    - 實作 LRU 清理機制，避免佔用過多記憶體
  - **預期效益:** 減少測資下載次數，節省頻寬

---

## 🟢 低優先級 (可選改進)

### Code Quality

- [ ] **Frontend 檔案驗證增強**
  - **檔案:** `new-front-end/src/components/Problem/Admin/Sections/PipelineSection.vue:650-667`
  - **改進:** 增加 .py 副檔名檢查、空檔案檢查

- [ ] **抽象 Asset 管理邏輯**
  - **建議:** 建立 `AssetManager` 類別統一管理所有 asset 的上傳/下載/驗證
  - **影響範圍:** Backend `mongo/problem/problem.py`

- [ ] **Checker Docker Image 可配置化**
  - **檔案:** `Sandbox/dispatcher/dispatcher.py:66-67`
  - **改進:** 從 problem meta 讀取 checkerRuntime，支援多種語言的 checker

---

## 📊 測試補充

- [ ] **Custom Checker 單元測試**
  - **檔案:** `Sandbox/tests/test_dispatcher.py`
  - **需補充測試:**
    - `test_custom_checker_basic()` - AC case
    - `test_custom_checker_wa()` - WA case
    - `test_custom_checker_invalid_output()` - 無效 STATUS 格式
    - `test_custom_checker_timeout()` - Timeout 測試
    - `test_custom_checker_disabled_in_interactive()` - Interactive 模式禁用
    - `test_custom_checker_asset_not_found()` - Asset 不存在處理

- [ ] **Redis 快取測試**
  - 快取命中率測試
  - 快取過期測試
  - 快取失效測試 (problem 更新時)

---

## 📝 文檔更新

- [ ] **Guide 補充 Checker 資源限制說明**
  - **檔案:** `Docs and Ref/Guides/CHECKER_SCORING_GUIDE.md`
  - **補充內容:**
    - Checker 執行時間限制 (學生限制的 5 倍，最少 5 秒)
    - Checker 記憶體限制
    - Checker 失敗處理規則 (CE vs WA)
    - MESSAGE 輸出長度限制

- [ ] **新增 Redis 快取使用文檔**
  - 說明 Redis 快取的 key 命名規範
  - 快取 TTL 設定原則
  - 快取失效機制

---

## 🔄 進度追蹤

| 項目 | 狀態 | 負責人 | 預計完成 |
|------|------|--------|----------|
| Exit code 邏輯修正 | 待處理 | - | - |
| Interactive 模式強制禁用 | 待處理 | - | - |
| Redis Checker 快取 | 待處理 | - | - |
| Redis Meta 快取 | 待處理 | - | - |

---

**參考文檔:**
- [Custom Checker Code Review](./code_review_custom_checker.md)
- [CHECKER_SCORING_GUIDE.md](../Guides/CHECKER_SCORING_GUIDE.md)
