# Resource Data 架構重構設計文件

> 日期: 2025-12-05
> 狀態: 待實作

## 概述

重構 resource_data 架構，實現：
- 集中解壓到 `sandbox-testdata/extracted/`
- 每個 Case 獨立 teacher 目錄，避免並發衝突
- 統一 teacher/src 結構
- 移除 Interactive 的 testcase 掛載

---

## 目錄結構

```
sandbox-testdata/{pid}/                    # 問題級別（Redis Lock 保護）
├── *.in, *.out                            # Testcase 檔案
├── checker/                               # Custom Checker
│   └── custom_checker.py
├── resource_data/
│   ├── resource_data.zip                  # 原始 zip
│   └── extracted/                         # ← 解壓後（新增）
│       ├── 0000_input.bmp
│       └── 0001_input.bmp
└── resource_data_teacher/
    ├── resource_data_teacher.zip          # 原始 zip
    └── extracted/                         # ← 解壓後（新增）
        ├── 0000_solution.bmp
        └── 0001_solution.bmp

submissions/{submission_id}/
├── testcase/                              # 從 sandbox-testdata 複製 .in/.out
│   ├── 0000.in
│   ├── 0000.out
│   └── ...
├── resource_data/                         # 從 extracted/ 複製（不再解壓）
│   ├── 0000_input.bmp
│   └── 0001_input.bmp
├── resource_data_teacher/                 # 從 extracted/ 複製（不再解壓）
│   ├── 0000_solution.bmp
│   └── 0001_solution.bmp
├── src/                                   # 學生結構
│   ├── common/                            # 學生代碼（編譯用）
│   │   └── main.py
│   └── cases/                             # 每個 Case 執行目錄
│       └── 0000/
│           ├── main.py                    # 複製自 common
│           └── input.bmp                  # 從 resource_data 複製（去前綴）
└── teacher/                               # Teacher 結構（與 src 相同）
    ├── common/                            # Teacher 程式（Interactive 編譯用）
    │   └── teacher_main (或 main.py)
    └── cases/                             # 每個 Case 獨立目錄
        └── 0000/
            ├── teacher_main               # 複製自 teacher/common
            ├── testcase.in                # 從 testcase/0000.in 複製
            └── solution.bmp               # 從 resource_data_teacher 複製（去前綴）
```

---

## 流程圖 1: Normal + Custom Checker 模式

```
[Submission 開始]
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 1. ensure_extracted_resource() [Redis Lock]             │
│    - 檢查 Redis checksum                                │
│    - 若需要則解壓 zip → sandbox-testdata/extracted/     │
│    - 若資源不存在，返回 None                             │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 2. file_manager.extract()                               │
│    - 複製 testcase/*.in/*.out（排除 checker/, resource_data*/ 子目錄）
│    - 複製學生代碼到 src/common/                          │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 3. prepare_resource_data()                              │
│    - 從 extracted/ 複製到 submission/resource_data/     │
│    - 從 extracted/ 複製到 submission/resource_data_teacher/
│    - 若資源不存在，跳過                                  │
└─────────────────────────────────────────────────────────┘
      │
      ▼
[每個 Case 並行執行] ← 無並發衝突（獨立目錄）
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 4. 建立 case_dir (src/cases/{case_no}/)                 │
│    - 複製 src/common/ 到 case_dir                       │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 5. copy_resource_for_case()                             │
│    - 從 submission/resource_data/ 複製到 case_dir       │
│    - 去前綴: 0000_input.bmp → input.bmp                 │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 6. [allowWrite] 設置權限                                │
│    - 所有者: 1450:1450                                  │
│    - 目錄: 755, 檔案: 644                               │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 7. 執行 Sandbox                                         │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 8. [Custom Checker] prepare_teacher_for_case()          │
│    - 建立 teacher/cases/{case_no}/                      │
│    - 複製 resource_data_teacher（去前綴）                │
│    - 不需要 teacher/common/                              │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 9. [Custom Checker] run_custom_checker_case()           │
│    - 掛載 teacher/cases/{case_no}/ → /workspace/teacher │
│    - 掛載 case_dir → /workspace/student                 │
└─────────────────────────────────────────────────────────┘
```

---

## 流程圖 2: Interactive 模式

```
[Submission 開始]
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 1-3. 同 Normal 模式                                     │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 4. prepare_interactive_teacher_artifacts()              │
│    - 建立 teacher/common/                               │
│    - 複製/編譯 Teacher 程式                              │
└─────────────────────────────────────────────────────────┘
      │
      ▼
[每個 Case 並行執行] ← 無並發衝突（獨立目錄）
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 5. 建立 case_dir (src/cases/{case_no}/)                 │
│ 6. copy_resource_for_case() → case_dir（去前綴）        │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 7. prepare_teacher_for_case()                           │
│    - 建立 teacher/cases/{case_no}/                      │
│    - 複製 teacher_main 從 teacher/common/               │
│    - 複製 testcase/{case_no}.in → testcase.in           │
│    - 複製 resource_data_teacher（去前綴）                │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 8. InteractiveRunner.run()                              │
│    Docker 掛載（簡化）:                                  │
│    - teacher/cases/{case_no}/ → /teacher                │
│    - src/cases/{case_no}/ → /src                        │
│    - ❌ 移除 testcase/ 掛載                              │
│    - CASE_PATH=/teacher/testcase.in                     │
└─────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────┐
│ 9. orchestrator (Docker 內)                             │
│    - _setup_secure_permissions() 設置權限               │
│      · teacher/: 1450:1450, 701/700/600                 │
│      · src/: 1451:1450, 根據 allow_write 設置            │
│    - 移除 testcase 複製邏輯（已在 Dispatcher 處理）       │
└─────────────────────────────────────────────────────────┘
```

---

## 權限設計

### Normal 模式

| 場景 | case_dir 所有者 | 權限 |
|------|----------------|------|
| allowWrite=true | 1450:1450 | 目錄 755, 檔案 644 |
| allowWrite=false | root:root | 預設（保持現狀） |

### Interactive 模式（Orchestrator 設置）

| 目錄 | 所有者 | 權限 | 說明 |
|------|--------|------|------|
| teacher/cases/{case_no}/ | 1450:1450 | 701 | Student 無法讀取 |
| teacher/ 內的檔案 | 1450:1450 | 700/600 | Student 無法存取 |
| src/cases/{case_no}/ | 1451:1450 | 751 | Student 可執行 |
| src/ 內的檔案 | 1451:1450 | 根據 allow_write | 755/644 或 555/444 |

---

## 並發安全

| 資源 | 保護機制 |
|------|---------|
| sandbox-testdata/extracted/ | Redis Lock |
| submission/resource_data/ | 只讀，無並發問題 |
| submission/resource_data_teacher/ | 只讀，無並發問題 |
| src/cases/{case_no}/ | 每個 Case 獨立目錄 |
| teacher/cases/{case_no}/ | 每個 Case 獨立目錄 |

---

## Redis Cache Keys

| Key | 用途 | TTL |
|-----|------|-----|
| `problem-{pid}-checksum` | testdata checksum | 600s |
| `problem-{pid}-resource_data-checksum` | resource zip checksum | 600s |
| `problem-{pid}-resource_data-extracted` | 解壓狀態 checksum | 600s |
| `problem-{pid}-resource_data_teacher-checksum` | teacher zip checksum | 600s |
| `problem-{pid}-resource_data_teacher-extracted` | teacher 解壓狀態 | 600s |
| `problem-{pid}-{asset_type}-extract-lock` | 解壓操作鎖 | 60s |

---

## 兼容性

### Rejudge 兼容性
- Rejudge 是重新提交，會重建 submission 目錄
- 新架構不影響過往 submission

### 邊界情況處理

| 情況 | 處理方式 |
|------|---------|
| 沒有 resource_data | `prepare_resource_data()` 返回 None，跳過 |
| 沒有 resource_data_teacher | `prepare_teacher_for_case()` 只處理 testcase |
| extracted/ 不存在 | `ensure_extracted_resource()` 自動解壓 |
| Custom Checker 無 teacher | 直接建立 teacher/cases/{case_no}/，不需要 common/ |

---

## 修改清單

### 1. [asset_cache.py](../Sandbox/dispatcher/asset_cache.py)
- 新增 `ensure_extracted_resource(problem_id, asset_type)` 函數
- 使用 Redis Lock 保護解壓操作
- 檢查 checksum 決定是否需要重新解壓

### 2. [file_manager.py](../Sandbox/dispatcher/file_manager.py)
- 修改 `extract()`: 排除 checker/, resource_data*/ 子目錄
```python
shutil.copytree(testdata, testcase_dir,
                ignore=shutil.ignore_patterns('checker', 'resource_data*', 'chaos'))
```

### 3. [resource_data.py](../Sandbox/dispatcher/resource_data.py)
- 修改 `prepare_resource_data()`: 從 extracted/ 複製而非解壓
- 修改 `copy_resource_for_case()`: 從 submission/resource_data/ 讀取
- 新增 `prepare_teacher_for_case()`: 建立 teacher/cases/{case_no}/

### 4. [dispatcher.py](../Sandbox/dispatcher/dispatcher.py)
- 整合新流程
- 調用 `ensure_extracted_resource()` 確保解壓
- 傳遞 teacher/cases/{case_no}/ 給 runner

### 5. [interactive_runner.py](../Sandbox/runner/interactive_runner.py)
- 接收 `teacher_case_dir` 參數
- 移除 testcase/ 掛載
- 修改 CASE_PATH 為 `/teacher/testcase.in`

### 6. [custom_checker.py](../Sandbox/dispatcher/custom_checker.py)
- 使用 teacher/cases/{case_no}/ 作為掛載來源

### 7. [interactive_orchestrator.py](../Sandbox/runner/interactive_orchestrator.py)
- 移除 testcase 複製邏輯（第 394-410 行）
- `_setup_secure_permissions()` 處理新的目錄結構

---

## 實作順序

1. `ensure_extracted_resource()` - Redis Lock 保護的解壓函數
2. `file_manager.extract()` - 排除子目錄
3. `prepare_resource_data()` - 從 extracted 複製
4. `prepare_teacher_for_case()` - 建立 teacher/cases/{case_no}/
5. `dispatcher.py` - 整合新流程
6. `interactive_runner.py` - 修改掛載
7. `custom_checker.py` - 使用新路徑
8. `orchestrator.py` - 移除冗餘邏輯


