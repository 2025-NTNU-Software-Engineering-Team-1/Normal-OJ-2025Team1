# Artifact 實作驗證報告

## 概述
本報告總結了根據 `Docs and Ref/Guides/ARTIFACT_GUIDE.md` 檢查目前 Artifact 實作的結果。

## 分析檔案
- **指南**: `Docs and Ref/Guides/ARTIFACT_GUIDE.md`
- **Sandbox**:
    - `Sandbox/dispatcher/artifact_collector.py`
    - `Sandbox/dispatcher/dispatcher.py`
- **Backend**:
    - `Back-End/model/submission.py` (API 路由)
    - `Back-End/mongo/submission.py` (邏輯)
    - `Back-End/mongo/engine.py` (資料模型)

## 發現

### 1. 結構與架構
實作遵循指南中描述的架構：
- **Sandbox** 使用 `ArtifactCollector` 收集產物。
- **Sandbox** 透過內部 API 將產物上傳至 Backend。
- **Backend** 將產物儲存在 MinIO 並在 MongoDB 中管理路徑。
- **Backend** 提供下載 API 供使用者使用。

### 2. 元件實作

#### Sandbox (`ArtifactCollector`)
- **已實作**: `collect_and_store_case_artifact` (實作為 `record_case_artifact`), `collect_and_store_binary` (實作為 `collect_binary`), `upload_all_artifacts` (實作為 `upload_all`)。
- **邏輯**: 基於快照的檔案收集已按描述實作。
- **限制**: 檔案大小限制 (`_CASE_FILE_LIMIT` 等) 已實作。

#### Dispatcher 整合
- **已實作**: `dispatcher.py` 初始化 `ArtifactCollector` 並在 `create_container` (針對案例產物) 和 `on_submission_complete` (針對二進位檔和上傳) 中呼叫它。
- **邏輯**: 根據提交的 meta 檢查 `should_collect_artifacts` 和 `should_collect_binary`。

#### Backend API
- **已實作**:
    - `PUT /submission/<id>/artifact/upload/case`
    - `PUT /submission/<id>/artifact/upload/binary`
    - `GET /submission/<id>/artifact/compiledBinary`
    - `GET /submission/<id>/artifact/zip/<taskIndex>`
- **邏輯**: 路由如預期映射到 `Submission` 方法。

#### Backend 邏輯 (`Submission` 類別)
- **已實作**: `set_case_artifact`, `set_compiled_binary`, `get_compiled_binary`, `build_task_artifact_zip`。
- **資料模型**: `output_minio_path`, `compiled_binary_minio_path` 欄位存在。

### 3. 差異與觀察

#### 輕微命名差異
- 指南使用 `collect_and_store_case_artifact`，實作使用 `record_case_artifact`。
- 指南使用 `collect_and_store_binary`，實作使用 `collect_binary`。
- 這些是表面上的差異，不影響功能。

#### 重複上傳 / 優化機會
- **觀察**:
    - 當提交完成時，Backend 的 `process_result` (透過 `PUT /complete` 呼叫) 會建立並上傳包含 `stdout` 和 `stderr` 的 zip 到 MinIO。
    - 隨後，如果 `artifactCollection` 包含 "zip"，Sandbox 的 `upload_all` 會呼叫 `PUT /artifact/upload/case`，這會上傳一個 *新* 的 zip (包含 `stdout`、`stderr` 和任何額外檔案) 到 *相同* 的 MinIO 路徑 (`output_minio_path`)。
- **影響**:
    - 這導致當啟用 "zip" 時，每個案例都會有兩次上傳。
    - 第二次上傳 (來自 Sandbox) 會覆蓋第一次上傳 (來自 Backend)。
    - 雖然功能正確 (最終的 zip 包含所有必要檔案)，但效率較低。
- **指南參考**: 指南提到：「ArtifactCollection 啟用 'zip' 且只需要 stdout/stderr 時，直接復用上述產物，Sandbox 不需重複打包/上傳。」
- **目前狀態**: 實作似乎 *沒有* 實作此優化。如果啟用 "zip"，Sandbox 總是會收集並上傳，無論是否發現額外檔案。

## 結論
Artifact 實作 **完整且在功能上與指南一致**。核心需求 (收集二進位檔、收集額外案例檔案、提供下載) 均已滿足。

唯一值得注意的發現是缺少「若無額外檔案則跳過上傳」的優化，這導致了重複上傳，但不會破壞功能。
