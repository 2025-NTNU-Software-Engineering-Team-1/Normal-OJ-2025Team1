# Review Report: Resource Data 功能審查

## 總覽
目前的 uncommitted changes 在 Sandbox、Back-End 和 Frontend 中實作了「Resource Data」功能。此功能允許出題者上傳一個包含資源檔案的 zip 壓縮檔，並針對特定的測試案例（Test Case）將對應的檔案複製到執行環境中。

## 子模組分析

### 1. Sandbox (`Normal-OJ-2025Team1/Sandbox`)
**狀態:** `dispatcher/` 有未提交的變更，並新增了 `dispatcher/resource_data.py`。

*   **`dispatcher/resource_data.py` (新增):**
    *   實作 `prepare_resource_data` 以負責下載並解壓縮 zip 檔。
    *   實作 `copy_resource_for_case` 以複製符合 `{task_no:02d}{case_no:02d}_*` 命名規則的檔案到工作目錄，並移除檔名前綴。
    *   **觀察:** `copy_resource_for_case` 函式會在**每個**測試案例執行時，遍歷資源目錄中的**所有**檔案。
        *   *效能:* 如果資源 zip 包含非常大量的檔案，這可能會有效能疑慮。但在一般的題目設定下（數十個檔案），影響應可忽略。
    *   **錯誤處理:** 捕捉複製過程中的例外狀況並記錄為警告 (Warning)。

*   **`dispatcher/dispatcher.py`:**
    *   在 `handle` 方法（提交初始化）中整合了 `prepare_resource_data`。
    *   在 `create_container`（案例執行前）中呼叫 `copy_resource_for_case`。
    *   **關鍵觀察:** 對 `copy_resource_for_case` 的呼叫（約第 872 行）捕捉了例外狀況並記錄為 **警告 (Warning)**，但允許程式繼續執行。
        *   *風險:* 如果該資源檔案對測試案例至關重要（例如程式必須讀取的測資檔），使用者的程式極可能會失敗（RE 或 WA），且沒有明確的跡象顯示是環境設置失敗。建議考慮這是否應該導致系統錯誤 (System Error, SE) 或評判錯誤 (Judge Error, JE)。

*   **`dispatcher/meta.py` & `dispatcher/testdata.py`:**
    *   將 `exposeTestcase` 替換為 `resourceData` 旗標。如果 `exposeTestcase` 之前有被內部 API 使用或依賴，這可能是一個破壞性變更 (Breaking Change)，但對於這個新功能來說，這看起來是一個乾淨的替換。

### 2. Back-End (`Normal-OJ-2025Team1/Back-End`)
**狀態:** `model/` 和 `mongo/` 有未提交的變更。

*   **`model/problem.py` & `mongo/problem/problem.py`:**
    *   更新 Schema 以支援 `resourceData` 布林值和 `resource_data.zip` 資產。
    *   與 Sandbox 的變更保持一致。

### 3. Frontend (`Normal-OJ-2025Team1/new-front-end`)
**狀態:** `src/` 有未提交的變更，並新增了元件。

*   **`src/components/Problem/Admin/Sections/ResourceDataSection.vue` (新增):**
    *   提供啟用 `resourceData` 和上傳 zip 檔的介面。
    *   **驗證:** 實作了嚴格的用戶端驗證。它會解析 zip 結構並確保：
        1.  每個檔案都有有效的前綴 (`XXYY_`)。
        2.  題目中定義的每個測試案例在 zip 中都有對應的檔案。
    *   這種嚴格的驗證對於防止 Sandbox 中的執行期錯誤非常有幫助。

*   **整合:**
    *   更新 `AdminProblemForm.vue` 和 `PipelineSection.vue` 以包含新區塊並移除舊的 `exposeTestcase` 選項。

## 總結與建議

整體實作在各個 stack 中都很完整且一致。

**建議:**
1.  **Sandbox 錯誤處理:** 在 `dispatcher.py` 中，請考慮資源複製失敗是否應該視為硬性失敗 (Judge Error, JE) 而非僅是警告。如果因為複製錯誤導致資源遺失，學生的程式幾乎肯定會失敗，這可能會讓使用者感到困惑。
2.  **效能 (次要):** 如果預期會有極大的資源包，`copy_resource_for_case` 中的線性掃描可能需要優化（例如依前綴預先建立索引），但目前這可能屬於過早優化。
3.  **驗證:** 前端的驗證相當穩健。請確保 Backend/Sandbox 也能處理 zip 格式錯誤或惡意檔案的情況（Sandbox 已經透過 `zipfile` 和 `shutil` 處理，這點很好）。

**結論:** 程式碼看起來已準備好可以提交 (Commit)，取決於對 Sandbox 錯誤處理的決定。
