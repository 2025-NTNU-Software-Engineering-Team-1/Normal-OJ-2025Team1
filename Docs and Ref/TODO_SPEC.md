# Normal-OJ 待實作功能規格書

**版本:** 1.1
**更新時間:** 2025-12-03
**來源:** TODO.md + FILE_CONTROL_GUIDE.md + improvement_todo.md + 系統分析

本文檔彙總所有待實作功能，並依優先級和類別分類整理。

---

## 📋 目錄

- [高優先級功能](#高優先級功能)
- [中優先級功能](#中優先級功能)
- [低優先級功能](#低優先級功能)
- [功能分類索引](#功能分類索引)

---

## 高優先級功能

### 🔴 P0: 核心功能缺口

#### 1. 測資檔案存取功能 (File I/O Enhancement)

**問題描述:**  
學生程式目前無法直接讀取測資檔案，限制了「讀檔題」的出題靈活性。

**當前限制:**

```
學生程式可見路徑：
/src/              ← 工作目錄
/testdata/in       ← 僅當前測資（stdin重定向）

無法存取：
submissions/<id>/testcase/  ← 完整測資目錄（未 mount）
```

**實作需求:**

1. **Mount 完整測資目錄**
   - 位置: `Sandbox/runner/sandbox.py`
   - 修改 Docker volume 配置，新增:
     ```python
     volume = {
         self.src_dir: {'bind': '/src', 'mode': 'rw'},
         self.testdata_dir: {'bind': '/testdata', 'mode': 'ro'},  # 新增
         self.stdin_path: {'bind': '/testdata/in', 'mode': 'ro'}
     }
     ```

2. **題目配置新增選項**
   - Backend `config.fileSystemAccessRestriction` 新增:
     ```json
     {
       "allowRead": true,
       "allowWrite": false,
       "allowReadTestdata": false  // 新增：是否允許讀取完整測資目錄
     }
     ```

3. **安全性考量**
   - ⚠️ **風險**: 學生可能遍歷所有測資反推答案
   - **緩解方案**:
     - 預設 `allowReadTestdata=false`
     - 文檔明確標注風險
     - 建議僅在「資料處理題」使用

**相關文檔:**  
- [FILE_CONTROL_GUIDE.md](./Guides/FILE_CONTROL_GUIDE.md#測資檔案存取限制當前未實作功能)

**優先級理由:**  
影響出題靈活性，多位教師反映此需求。

---

#### 2. Interactive Mode - Teacher 寫入 Student 目錄

**問題描述:**  
文檔中聲稱 Teacher 可寫入 Student 目錄，但實際權限設定為 `0o751` (rwxr-x--x)，Group 只有 `r-x` 權限，**無法寫入**。

**當前狀態:**

```python
# runner/interactive_orchestrator.py:176-179
dir_mode = 0o751  # rwxr-x--x
for root, dirs, files in os.walk(student_dir):
    os.chown(root, student_uid, sandbox_gid)
    os.chmod(root, dir_mode)  # Teacher 以 Group 身份只有 r-x
```

**實作選項:**

**方案 A: 開放 Group 寫入權限**
```python
dir_mode = 0o771  # rwxrwx--x
```
- ✅ 允許 Teacher 準備資料檔案供 Student 使用
- ❌ 安全疑慮：Teacher 可修改 Student 程式碼

**方案 B: 建立共享目錄**
```python
shared_dir = workdir / "shared"
shared_dir.mkdir()
os.chown(shared_dir, teacher_uid, sandbox_gid)
os.chmod(shared_dir, 0o771)  # Teacher 可寫，Student 可讀
```
- ✅ 隔離權限，降低風險
- ✅ 明確語意（shared 目錄）
- ❌ 需調整 Docker mount

**方案 C: 僅允許 Teacher 通過 pipe 傳遞資料**
```
維持現狀，更新文檔移除錯誤說明
```
- ✅ 最安全
- ❌ 限制題型設計

**建議:** 採用**方案 B**，新增 `/workspace/shared` 目錄。

**相關文檔:**  
- [FILE_CONTROL_GUIDE.md](./Guides/FILE_CONTROL_GUIDE.md#interactive-mode-特殊機制)

---

#### 3. Custom Checker 讀取學生輸出檔案

**問題描述:**  
當學生程式將結果寫入檔案（而非 stdout）時，Custom Checker 無法讀取該檔案進行驗證。

**當前限制:**

```python
# dispatcher/custom_checker.py
# Checker 只接收三個檔案：
# - input: 測資輸入
# - output: 學生 stdout
# - answer: 標準答案

# 無法讀取學生寫入的其他檔案！
```

**實作需求:**

1. **Mount 學生工作目錄**
   - 位置: `Sandbox/dispatcher/custom_checker_runner.py`
   - 修改 Docker volume:
     ```python
     volumes = {
         input_file: {'bind': '/judge/input.txt', 'mode': 'ro'},
         output_file: {'bind': '/judge/output.txt', 'mode': 'ro'},
         answer_file: {'bind': '/judge/answer.txt', 'mode': 'ro'},
         submission_src_dir: {'bind': '/student', 'mode': 'ro'},  # 新增
     }
     ```

2. **更新 Checker 呼叫介面**
   ```python
   # 新參數: /student 目錄路徑
   cmd = ['python3', '/judge/custom_checker.py', 
          '/judge/input.txt', 
          '/judge/output.txt', 
          '/judge/answer.txt',
          '/student']  # 新增
   ```

3. **文檔範例**
   ```python
   # custom_checker.py
   import sys
   import os
   
   def check(input_path, output_path, answer_path, student_dir):
       # 讀取學生寫入的檔案
       result_file = os.path.join(student_dir, 'result.txt')
       if not os.path.exists(result_file):
           return 'WA', 'Missing result.txt'
       
       with open(result_file) as f:
           student_result = f.read()
       # ... 驗證邏輯
   
   if __name__ == '__main__':
       input_path, output_path, answer_path, student_dir = sys.argv[1:5]
       status, msg = check(input_path, output_path, answer_path, student_dir)
       print(f'STATUS:{status}')
       print(f'MESSAGE:{msg}')
   ```

**相關文檔:**  
- [CHECKER_SCORING_GUIDE.md](./Guides/CHECKER_SCORING_GUIDE.md)

---

#### 4. `allowRead` 標誌尚未落地（新增）

**現況：**
- 前後端已提供 `allowRead` 配置並與 Resource Data（學生端）做校驗，但沙盒層尚未實際阻擋/允許讀檔。
- Normal 模式：`SANDBOX_ALLOW_READ` 未被 C Sandbox 使用；目前學生仍可讀取 `/src` 下所有檔案（包含自帶資源）。
- Interactive 模式：orchestrator 只在環境變數中留存 `SANDBOX_ALLOW_READ`，但 C sandbox_interactive 未實作；學生可讀 `/src` 內容。

**待辦重點：**
1. **Normal Sandbox**  
   - 以 seccomp + 路徑過濾或 mount namespace 控制讀檔範圍，讓 `allowRead=false` 時阻擋 `fopen/open` 除 stdin 以外的檔案；同時避免影響 `/proc` 最小存取需求。
2. **Interactive Sandbox**  
   - sandbox_interactive 需接受 `SANDBOX_ALLOW_READ` 或其他旗標，並限制學生僅能讀 `/src`（必要時允許 `/workspace/testcase` 由 orchestrator 控制），避免讀取老師或其他測資檔案。
3. **測試**  
   - 增加 Normal / Interactive 兩套禁止讀檔的整合測試：試讀 `resource data`、`/workspace/testcase`、`/teacher` 時應 RE/CE；stdin 仍可讀。
4. **文件**  
   - 更新 FILE_CONTROL_GUIDE，說明 `allowRead` 對 Resource Data 的關聯與安全風險，並標註目前預設行為（未實作前為全開）。

**優先級理由：** 安全與題型控制風險，目前 UI 允許配置但沙盒未強制，需要落地以避免行為落差。

---

### 🟡 P1: Interactive 產物修正

#### 4. Interactive Mode 測資清理問題 (Completed)

**狀態:** ✅ 已完成

#### 5. Interactive Mode 測資目錄暴露問題

**問題描述:**  
互動模式下，學生與老師共用同一 Docker 容器／同一 mount namespace。容器建立時會把整個 `submissions/<id>/testcase` 綁到容器 `/workspace/testcase`（唯讀），但學生 sandbox 也能直接 `open()` 所有 `.in/.out`，看到完整測資。實際上學生只需接收老師程式輸出，不需要直接讀 testcase 檔案。

**潛在解法（需選擇其一實作）：**
1. **拆容器**：學生、老師各自使用不同 Docker 容器。學生容器不掛 testcase；老師/ orchestrator 容器保留 testcase 掛載。
2. **分 mount namespace**：在同一容器內，學生 sandbox 先 `unshare(CLONE_NEWNS)`，在學生 namespace 中 `umount /workspace/testcase`，老師/ orchestrator 保留原掛載。
3. **不掛 testcase 給學生**：容器仍掛 `/workspace/testcase` 給 orchestrator/老師，學生 sandbox 僅掛 `/src`，由 orchestrator 將當前 case 的資料透過管線或複製餵給學生 stdin，不讓學生看到整個 testcase 目錄。

**注意事項：**
- 不影響 stdin：即使 umount 測資路徑，stdin 已由 orchestrator 綁定，可照常讀取。
- Teacher 資源/測資仍需可讀；老師側掛載不能被拔除。
- 選案後需更新文檔與測試覆蓋，評估對現有互動流程兼容性。

**實作細節:**
- `Sandbox/runner/interactive_orchestrator.py` 已實作 `finally` 區塊清理 `testcase.in`。
- 包含權限變更後的強制刪除邏輯。

---

## 中優先級功能

### 🔵 P2: 功能增強

#### 5. 網路控制完整實作

**狀態:** 部分實作（Backend schema 已完成，Sandbox 未串接）

**當前狀況:**

- ✅ Backend `config.networkAccessRestriction` schema 已定義
- ✅ C-Sandbox `allow_network_access` 參數已存在
- ❌ Sandbox Dispatcher 未讀取並傳遞參數
- ❌ Local Service 未實作

**實作需求:**

1. **Dispatcher 讀取配置**
   ```python
   # dispatcher/meta.py
   class Meta(BaseModel):
       networkAccessRestriction: Optional[dict] = None
   
   # dispatcher/dispatcher.py
   allow_network = meta.networkAccessRestriction.get('allowNetwork', False) \
       if meta.networkAccessRestriction else False
   ```

2. **傳遞參數到 Sandbox**
   ```python
   # runner/sandbox.py
   self.allow_network = allow_network
   command_sandbox = ' '.join([
       'sandbox',
       # ... 其他參數 ...
       '1' if self.allow_network else '0',  # 第11個參數
       # ...
   ])
   ```

3. **Local Service 管理器**
   - 位置: 新增 `Sandbox/dispatcher/local_service_manager.py`
   - 功能:
     - 解壓教師提供的 `local_service.zip`
     - 啟動 server (Python/Node.js/Binary)
     - 管理生命週期（超時自動關閉）
     - 提供 whitelist/blacklist 控制

**相關文檔:**  
- [NETWORK_CONTROL_GUIDE.md](./Guides/NETWORK_CONTROL_GUIDE.md)
- [Sandbox/TODO.md](../../Sandbox/TODO.md#3-網路控制防火牆--local-service)

---

#### 6. 自訂計分腳本 (Custom Scoring) (Completed)

**狀態:** ✅ 已完成

**實作細節:**
- `Sandbox/runner/custom_scorer_runner.py` 已實作。
- `Sandbox/dispatcher/dispatcher.py` 已整合 `run_custom_scorer`。
- 支援 `lateSeconds` 和 `breakdown` 輸出。

---

#### 7. Artifact Collection 自動化 (Partial)

**狀態:** 🟡 部分完成

**已實作:**
- `Sandbox/dispatcher/artifact_collector.py` 模組已存在。
- `dispatcher.py` 中已整合 Binary Collection (`collect_binary`, `upload_binary_only`)。

**待實作:**
- Testcase Output Collection 尚未完全整合。
- Frontend 下載介面。

**相關文檔:**  
- [ARTIFACT_GUIDE.md](./Guides/ARTIFACT_GUIDE.md)
- [Sandbox/TODO.md](../../Sandbox/TODO.md#8-artifact)

---

#### 8. Trial Submission (試做模式)

**狀態:** Schema 已定義，Pipeline 未實作

**實作需求:**

1. **Backend API**
   - `POST /problem/<id>/trial` - 建立試做請求
   - `PUT /trial/<id>/upload` - 上傳試做程式碼
   - `GET /trial/<id>/result` - 取得試做結果

2. **公開測資管理**
   - `PUT /problem/<id>/public-testdata` - 上傳公開測資
   - `PUT /problem/<id>/ac-code` - 上傳 AC 標準程式

3. **Sandbox 整合**
   - Dispatcher 識別 trial submission
   - 使用公開測資執行
   - 與 AC code 輸出比對
   - 返回詳細 diff

4. **Quota 控制**
   - Redis 記錄試做次數
   - 限制每題每日試做次數（可配置）

**相關文檔:**  
- [Sandbox/TODO.md](../../Sandbox/TODO.md#10-trial-submission--test-mode)

---

## 低優先級功能

### 🟢 P3: 優化與改進

#### 9. Static Analysis 報告下載

**問題描述:**  
SA 報告目前僅回傳文字，未上傳到 MinIO 供前端下載。

**實作需求:**

```python
# dispatcher/static_analysis.py
def analyze_submission(...):
    # ... 執行分析 ...
    
    if violations:
        report_path = submission_dir / 'static_analysis_report.txt'
        report_path.write_text(report_content)
        
        # 上傳到 MinIO
        upload_url = upload_to_minio(report_path, f'sa_reports/{submission_id}.txt')
        
        return {
            'status': 'failed',
            'message': summary,
            'reportPath': upload_url  # 新增
        }
```

**Backend 處理:**

```python
# model/submission.py
def process_result(self, tasks, staticAnalysis=None):
    if staticAnalysis:
        self.sa_status = staticAnalysis['status']
        self.sa_message = staticAnalysis['message']
        self.sa_report_path = staticAnalysis.get('reportPath')  # 新增欄位
```

---

#### 10. Redis 快取優化 (Partial)

**狀態:** 🟡 部分完成

**已實作:**
- `Sandbox/dispatcher/asset_cache.py` 已實作 Asset (Checker, Scorer, Makefile, Resource) 的 Checksum 快取與自動更新。

**待實作:**
- Problem Meta 快取。
- Testdata Checksum 快取 (目前整合在 Asset Cache 中，需確認是否足夠)。

**預期效益:**
- 減少 Backend API 請求 60%+
- 減少 MinIO 下載次數 40%+
- 提升 submission 處理速度 15%+

---

#### 11. Frontend 功能增強

**位置:** `new-front-end/src/pages/course/[name]/problem/[id]/edit.vue`

**實作項目:**

1. **題目編輯頁資料帶入**
   - ✅ Config/Pipeline 自動帶入
   - ❌ Asset 上傳狀態顯示（待實作）
   - ❌ 測資下載按鈕（待實作）

2. **Asset 上傳提示**
   ```vue
   <div v-if="problem.assetPaths?.checker">
     ✅ Custom Checker uploaded: custom_checker.py
     <button @click="downloadAsset('checker')">Download</button>
   </div>
   ```

3. **測資管理**
   ```vue
   <button @click="downloadTestdata">
     📥 Download Current Testdata ({{ problem.testcaseCount }} cases)
   </button>
   ```

**相關文檔:**  
- [Sandbox/TODO.md](../../Sandbox/TODO.md#問題編輯頁courseproblemidedit資料帶入)

---

#### 12. Code Quality 改進

**項目清單:**

- [ ] **Checker 上傳時語法驗證**
  ```python
  # Back-End/mongo/problem/problem.py
  def update_assets(self, files_data, meta):
      if 'custom_checker.py' in files_data:
          try:
              ast.parse(files_data['custom_checker.py'].read())
          except SyntaxError as e:
              raise ValueError(f'Invalid Python syntax: {e}')
  ```

- [ ] **Interactive 模式自動禁用 customChecker**
  ```python
  # Back-End/mongo/problem/problem.py (edit_problem)
  if pipeline.get('executionMode') == 'interactive':
      full_config['customChecker'] = False
  ```

- [ ] **抽象 Asset 管理邏輯**
  - 建立 `AssetManager` 類別
  - 統一處理 asset 上傳/下載/驗證/快取

**相關文檔:**  
- [DevNotes/improvement_todo.md](./DevNotes/improvement_todo.md)

---

## 功能分類索引

### 📂 按類別分類

#### File I/O & Permissions
- [P0-1] 測資檔案存取功能
- [P0-2] Interactive Mode Teacher 寫入
- [P0-3] Custom Checker 讀取學生檔案

#### Interactive Mode
- [P0-2] Teacher 寫入 Student 目錄
- [Completed] 測資清理問題

#### Custom Checker & Scoring
- [P0-3] Checker 讀取學生輸出檔案
- [Completed] 自訂計分腳本

#### Network & Security
- [P2-5] 網路控制完整實作

#### Artifact & Analytics
- [Partial] Artifact Collection 自動化
- [P3-9] Static Analysis 報告下載

#### Testing & Trial
- [P2-8] Trial Submission

#### Performance
- [Partial] Redis 快取優化

#### Frontend
- [P3-11] Frontend 功能增強

#### Code Quality
- [P3-12] Code Quality 改進

---

### 📊 按優先級分類

| 優先級 | 功能數量 | 預估工時 |
|--------|----------|----------|
| P0 (高) | 3 項 | 40 hrs |
| P1 (中高) | 0 項 | 0 hrs |
| P2 (中) | 2 項 | 40 hrs |
| P3 (低) | 4 項 | 30 hrs |
| **總計** | **9 項** | **110 hrs** |

---

## 實作優先級建議

### Phase 1: 核心功能修復 (P0)
**預估: 2 週**

1. Interactive Mode Teacher 寫入修正
2. Custom Checker 讀取學生檔案
3. 測資檔案存取功能（需安全評估）

### Phase 2: Interactive 穩定性 (P1)
**預估: 3 天**

4. 測資清理問題修復

### Phase 3: 功能增強 (P2)
**預估: 3 週**

5. 網路控制完整實作
6. 自訂計分腳本
7. Artifact Collection 自動化
8. Trial Submission

### Phase 4: 優化與改進 (P3)
**預估: 2 週**

9. Static Analysis 報告下載
10. Redis 快取優化
11. Frontend 功能增強
12. Code Quality 改進

---

## 參考文檔

### Guides
- [FILE_CONTROL_GUIDE.md](./Guides/FILE_CONTROL_GUIDE.md)
- [NETWORK_CONTROL_GUIDE.md](./Guides/NETWORK_CONTROL_GUIDE.md)
- [CHECKER_SCORING_GUIDE.md](./Guides/CHECKER_SCORING_GUIDE.md)
- [ARTIFACT_GUIDE.md](./Guides/ARTIFACT_GUIDE.md)

### DevNotes
- [improvement_todo.md](./DevNotes/improvement_todo.md)

### Source
- [Sandbox/TODO.md](../../Sandbox/TODO.md)

---

**維護者:** 2025 NTNU Software Engineering Team 1  
**最後更新:** 2025-12-03
