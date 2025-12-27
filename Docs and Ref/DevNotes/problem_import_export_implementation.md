# 題目匯入/匯出實作規格 v1.1

更新日期：2025-01-01

## 1. 目標與範圍
本文件定義 Normal‑OJ 題目匯入/匯出之封裝格式、權限、驗證、雜湊與清理策略。匯入會建立新題目；允許只匯出/匯入部分組件。

## 2. 權限規則
- 匯出：僅 admin 或該題目 owner 可操作。
- 匯入：僅對目標課程具 MODIFY 權限者可操作。

## 3. 封裝格式
### 3.1 單題封裝
`problem_<id>.noj.zip`
```
problem_<id>.noj.zip
├── manifest.json
├── meta.json
├── testcase.zip
└── assets/
    ├── checker/custom_checker.py
    ├── makefile/makefile.zip
    ├── teacher/Teacher_file.<ext>
    ├── scoring/score.py
    ├── scoring/score.json
    ├── local_service/local_service.zip
    ├── resource_data/resource_data.zip
    ├── resource_data_teacher/resource_data_teacher.zip
    ├── network_dockerfile/Dockerfiles.zip
    └── trial/
        ├── public_testdata.zip
        └── ac_code.<ext 或 zip>
```

### 3.2 批次封裝
`problems_export.noj.zip`
```
problems_export.noj.zip
├── manifest.json
├── problem_<hash_or_id>/
│   ├── manifest.json
│   ├── meta.json
│   ├── testcase.zip
│   └── assets/...
└── ...
```

## 4. 路徑規則
- 所有路徑必須為相對路徑，禁止 `..` 或絕對路徑。
- `config.assetPaths` 必須指向封包內相對路徑。
- 建議使用固定映射路徑（如上方目錄結構）以確保一致性。

## 5. meta.json（題目主體設定）
### 5.1 來源
- 來源為編輯題目頁面顯示的 JSON（`GET /problem/manage/<id>` payload）。

### 5.2 必要欄位
`problemName, description, courses, tags, allowedLanguage, quota, type, status, testCase, canViewStdout, defaultCode, config, pipeline`

### 5.3 規則
- `courses` 保留作參考，但匯入時不得採用（以匯入參數 course 為準）。
- `submissionMode` 為棄用欄位：匯出不輸出；匯入若出現則忽略。
- API Key/憑證欄位一律剔除，不輸出也不進雜湊：
  - `config.aiVTuberApiKeys`
  - `config.aiChecker.apiKeyId`
  - 其他任何金鑰或憑證欄位
- `config.assetPaths` 必須改為封包內相對路徑。

## 6. manifest.json（索引與校驗）
### 6.1 單題 manifest
```
{
  "formatVersion": "1.1",
  "exportedAt": "2025-01-01T00:00:00Z",
  "exportedBy": "username",
  "sourceSystem": "Normal-OJ",
  "problemContentHash": "sha256:<hex>",
  "components": {
    "core.meta": { "included": true, "hash": "sha256:<hex>", "files": ["meta.json"] },
    "core.testcase": { "included": true, "hash": "sha256:<hex>", "files": ["testcase.zip"] },
    "assets.checker": { "included": false, "hash": null, "files": [] }
  },
  "files": {
    "meta.json": { "sha256": "<hex>", "size": 1234, "role": "core.meta" },
    "testcase.zip": { "sha256": "<hex>", "size": 4567, "role": "core.testcase" }
  },
  "redactions": [
    "config.aiVTuberApiKeys",
    "config.aiChecker.apiKeyId"
  ]
}
```

### 6.2 批次 manifest
```
{
  "formatVersion": "1.1",
  "exportedAt": "2025-01-01T00:00:00Z",
  "exportedBy": "username",
  "problemCount": 3,
  "problems": [
    { "problemContentHash": "sha256:<hex>", "folder": "problem_101", "originalId": 101, "name": "A" }
  ]
}
```

## 7. 組件（Component IDs）
- Core：`core.meta`, `core.testcase`, `core.default_code`
- Assets：`assets.checker`, `assets.makefile`, `assets.teacher_file`, `assets.scoring_script`, `assets.scoring_config`, `assets.resource_data`, `assets.resource_data_teacher`, `assets.network_dockerfile`, `assets.local_service`
- Trial：`trial.public_testdata`, `trial.ac_code`
- Analysis：`static_analysis`（若有外部規則檔）

## 8. 依賴規則（System Policy 驗證）
System policy 只做驗證，不覆寫 `meta.json`。
- `pipeline.customChecker=true` → 必須包含 `assets.checker`
- `pipeline.executionMode=functionOnly` → 必須包含 `assets.makefile`
- `pipeline.executionMode=interactive` → 必須包含 `assets.teacher_file`
- scoring script 啟用 → 必須包含 `assets.scoring_script`
- `config.trialMode=true` → 必須包含 `trial.public_testdata`
- 必須通過：單檔大小、總包大小、zip slip 防護、壓縮比限制

## 9. Checksum 與穩定雜湊
- 所有檔案使用 SHA‑256。
- `meta.json` checksum 使用 canonical JSON（UTF‑8、key 排序、無空白、統一 LF）。
- `component hash` = 組件 ID + 組件 payload + 相關檔案 checksum → SHA‑256。
- `problemContentHash` = 所有內容組件 hash（排序後）→ SHA‑256。
- 排除欄位（不進 content hash）：
  `problemName/exportedAt/exportedBy/owner/courses/status/tags/ACUser/submitter/submitCount/trialSubmissionCount` + 所有被剔除金鑰欄位。

## 10. 匯出流程
1) 權限檢查（admin/owner）。
2) 取 edit page JSON 作為 `meta.json`，剔除金鑰欄位、忽略 submissionMode。
3) 下載 testcase/資產，依固定相對路徑寫入 zip。
4) 計算檔案 checksum、component hash、problemContentHash。
5) 生成 `manifest.json`。

## 11. 匯入流程與清理
1) 解壓至 staging；路徑/大小檢查。
2) 解析 manifest/meta；schema 驗證；忽略 submissionMode。
3) 逐檔 checksum 驗證。
4) 依賴規則驗證；不符則該題 abort。
5) 上傳檔案至 MinIO staging prefix。
6) 建立 Problem、套用 meta、再 commit 到正式路徑。
7) 失敗時刪 staging、回滾 DB。

## 12. 批次語義
- 逐題處理、逐題回報。
- 單題失敗不影響其他題。

## 13. 錯誤處理
- 匯出：缺權限、資料不完整、資產缺失需明確錯誤。
- 匯入：manifest 格式錯誤、checksum 不符、依賴違反、大小超限皆視為該題失敗。

## 14. 安全
- API Key 一律剔除，不進封包也不進雜湊。
- 防止 zip slip 與 zip bomb。
- 不支援的 formatVersion 必須回傳明確錯誤。

## 15. 實作步驟（Implementation Steps）
### 15.1 共用工具與資料結構
1) 建立 canonical JSON 與 SHA‑256 計算工具（支援 stream）。
2) 定義 component schema 與檔案路徑映射表。
3) 定義 manifest/meta 驗證器與錯誤碼對應表。

### 15.2 匯出流程實作
1) 權限檢查（admin/owner）。
2) 讀取 edit page JSON → 生成 `meta.json`（剔除金鑰欄位、忽略 submissionMode）。
3) 依 component 選擇收集 testcase/資產，轉為相對路徑。
4) 以 streaming 方式打包 ZIP（避免整檔載入記憶體）。
5) 計算檔案 checksum、component hash、problemContentHash。
6) 生成 `manifest.json` 並封裝輸出。

### 15.3 匯入流程實作
1) 權限檢查（course MODIFY）。
2) 解壓至 staging，執行路徑/大小/壓縮比驗證。
3) 解析 `manifest.json`/`meta.json`，驗證 schema，忽略 submissionMode。
4) 逐檔 checksum 驗證。
5) 驗證依賴規則與 system policy（不覆寫 meta）。
6) 上傳至 MinIO staging prefix。
7) 建立 Problem，套用 meta/pipeline/config 與 assets。
8) commit 到正式路徑；失敗即清除 staging 並回滾 DB。

### 15.4 批次作業
1) 逐題處理，獨立 staging。
2) 單題失敗不影響其他題；回傳 per‑problem 成功/失敗。

### 15.5 測試與驗證
1) 單題：正常流程、缺資產、checksum 不符、大小超限。
2) 批次：部分成功/部分失敗。
3) 安全：zip slip、zip bomb、防止金鑰匯出。

## 16. 實作計畫（Milestones）
### M1：基礎工具與驗證
- 完成 canonical JSON、checksum、component 解析與 schema 驗證。
- 定義固定相對路徑映射與欄位剔除清單。

### M2：匯出功能
- 新增單題/批次匯出 API（權限與 streaming ZIP）。
- 產出 `meta.json` + `manifest.json`。

### M3：匯入功能
- 新增單題/批次匯入 API（staging/清理/回滾）。
- 完成依賴檢查與 system policy 驗證。

### M4：前端串接
- 匯出：單題/批次下載與組件選擇。
- 匯入：預覽、檢核結果、逐題回報。

### M5：測試與優化
- 單元/整合測試覆蓋（含大檔與安全案例）。
- 性能與記憶體壓力測試。
