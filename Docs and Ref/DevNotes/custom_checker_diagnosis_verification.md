# Custom Checker "找不到 custom_checker.py" 問題驗證報告

**驗證日期:** 2025-12-01 21:57  
**Submission ID:** 692d9d4b4d265f7ce827cc38  
**問題:** `python3: can't open file '/workspace/custom_checker.py': [Errno 2] No such file or directory`

---

## ✅ 驗證結論

**您的推論 100% 正確!**

---

## 1️⃣ 證據鏈分析

### 證據 A: Custom Checker 資產確實存在 ✅

**位置 (Host):**
```
/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/sandbox-testdata/10/custom_checker/custom_checker.py
```

**檔案確認:**
```bash
$ ls -la /home/.../Sandbox/sandbox-testdata/10/custom_checker/
total 12
-rw-r--r-- 1 root root 3256 Dec  1 21:51 custom_checker.py
```

**Container 內路徑:**
```
/app/sandbox-testdata/10/custom_checker/custom_checker.py
```

**結論:** ✅ 資產檔案沒有遺失

---

### 證據 B: Checker Path 是 Container Path

**Code Flow:**

1. **ensure_custom_checker() Line 36-40:**
```python
# copy to submission workspace for isolation
submission_checker_dir = submission_path / "checker"  # submission_path 是 container path
submission_checker_dir.mkdir(parents=True, exist_ok=True)
target = submission_checker_dir / "custom_checker.py"
shutil.copyfile(checker_path, target)
return target  # 返回 container path!
```

**返回值範例:**
```
/app/submissions/{submission_id}/checker/custom_checker.py
```

2. **dispatcher.py Line 227-235:**
```python
checker_path = ensure_custom_checker(
    problem_id=problem_id,
    submission_path=submission_path,  # = SUBMISSION_DIR / submission_id (container path)
    execution_mode=meta.executionMode,
)
# checker_path = /app/submissions/{sid}/checker/custom_checker.py
self.custom_checker_info[submission_id] = {
    "enabled": True,
    "checker_path": checker_path,  # ← Container path!
}
```

**結論:** ✅ checker_path 確實是 container path

---

### 證據 C: workdir 也是 Container Path

**custom_checker.py Line 56-57:**
```python
workdir = checker_path.parent / "work" / case_no
# = /app/submissions/{sid}/checker/work/{case_no}  ← Container path!
workdir.mkdir(parents=True, exist_ok=True)
```

**實際路徑範例:**
```
/app/submissions/692d9d4b.../checker/work/0000
```

**Line 72:**
```python
workdir=str(workdir.resolve())
# .resolve() 只解析符號連結,不改變路徑類型
# 結果還是: /app/submissions/692d9d4b.../checker/work/0000
```

**結論:** ✅ workdir 確實是 container path

---

### 證據 D: Docker Bind Mount 失敗

**CustomCheckerRunner Line 24-28:**
```python
binds = {
    self.workdir: {  # = "/app/submissions/692d9d4b.../checker/work/0000"
        "bind": "/workspace",
        "mode": "rw",
    }
}
```

**Docker Daemon 行為:**
1. Docker daemon 運行在 **host** 上
2. 收到 bind 請求: `/app/submissions/...` → `/workspace`
3. 在 **host 檔案系統**上尋找 `/app/submissions/...`
4. ❌ **找不到!** (host 上沒有 `/app` 目錄)
5. Docker 創建一個**空的 bind 目錄**
6. Checker container 看到的 `/workspace` 是空的!

**錯誤訊息:**
```
python3: can't open file '/workspace/custom_checker.py': [Errno 2] No such file or directory
```

**結論:** ✅ 確認 bind mount 到空目錄

---

## 2️⃣ 路徑流程完整追蹤

### 當前流程 (錯誤)

```
1. ensure_custom_checker()
   └─ 複製 checker 到: /app/submissions/{sid}/checker/custom_checker.py (container)
   └─ 返回: checker_path = /app/submissions/{sid}/checker/custom_checker.py

2. run_custom_checker_case() Line 56
   └─ workdir = /app/submissions/{sid}/checker/work/0000 (container)
   └─ 複製檔案到 workdir/ (成功,在同一 container 內)

3. CustomCheckerRunner Line 24-28
   └─ Docker bind: /app/submissions/{sid}/checker/work/0000 → /workspace
   └─ ❌ Docker daemon 在 host 上找不到 /app/...
   └─ 創建空的 /workspace

4. Checker Container 啟動
   └─ python3 /workspace/custom_checker.py
   └─ ❌ 檔案不存在!
```

---

### 應該的流程 (正確)

```
1. ensure_custom_checker()
   └─ 返回 container path (不變)

2. run_custom_checker_case()
   └─ workdir = /app/submissions/{sid}/checker/work/0000 (container)
   └─ 複製檔案到 workdir/ (成功)
   └─ ✅ 將 workdir 轉換為 host path:
      /app/submissions/... → /home/.../Sandbox/submissions/...

3. CustomCheckerRunner Line 24-28
   └─ Docker bind: /home/.../Sandbox/submissions/{sid}/checker/work/0000 → /workspace
   └─ ✅ Docker daemon 在 host 上找到目錄!
   └─ Bind mount 成功

4. Checker Container 啟動
   └─ /workspace/ 包含所有檔案
   └─ python3 /workspace/custom_checker.py ✅ 成功!
```

---

## 3️⃣ 為什麼 _copy_file 成功但 bind mount 失敗?

### 關鍵區別

| 操作 | 執行位置 | 路徑需求 | 當前狀態 |
|------|---------|---------|---------|
| `_copy_file` (Line 61-65) | Dispatcher container | Container path | ✅ 正確 |
| `shutil.copyfile` (Line 65) | Dispatcher container | Container path | ✅ 正確 |
| `workdir.mkdir` (Line 57) | Dispatcher container | Container path | ✅ 正確 |
| **Docker bind mount** (Line 72, 24) | **Docker daemon (host)** | **Host path** | ❌ **錯誤!** |

**說明:**
- 前 3 個操作都在 dispatcher container 內執行,使用 container path 正確
- Docker bind mount 由 **Docker daemon** 處理,daemon 運行在 **host** 上
- Docker daemon 需要 **host path** 才能找到目錄

---

## 4️⃣ 對照:為什麼 SubmissionRunner 沒問題?

**SubmissionRunner Line 148:**
```python
host_src_dir = self.translator.to_host(src_dir).resolve()  # ✅ 轉換為 host path!
```

**Line 149-153:**
```python
binds={str(host_src_dir): {  # ✅ 使用 host path
    'bind': '/src',
    'mode': 'rw'
}}
```

**結論:** SubmissionRunner 正確使用 PathTranslator 轉換,所以沒問題!

---

## 5️⃣ 解決方案驗證

### 您提出的解法

> 在 dispatcher 呼叫 run_custom_checker_case 時,把 checker_path、case_in_path、case_out_path 都先用 PathTranslator.to_host 轉成 host 路徑

**分析:**

#### 需要轉換的路徑

| 路徑變數 | 用途 | 需要轉換? | 原因 |
|---------|------|----------|------|
| `checker_path` | 傳給 shutil.copyfile | ❌ No | 在 container 內複製,用 container path |
| `case_in_path` | 傳給 _copy_file | ❌ No | 在 container 內複製,用 container path |
| `case_ans_path` | 傳給 _copy_file | ❌ No | 在 container 內複製,用 container path |
| **`workdir`** | **傳給 Docker bind** | ✅ **Yes!** | **Docker daemon 需要 host path** |

#### 更精確的解法

**只需要轉換 workdir,而非所有路徑:**

```python
# custom_checker.py Line 72 修改
# 原始:
workdir=str(workdir.resolve())

# 修改為:
from runner.path_utils import PathTranslator
translator = PathTranslator()
host_workdir = translator.to_host(workdir)
workdir=str(host_workdir)
```

**或者在 dispatcher.py 傳遞時轉換:**

目前我們已經在 dispatcher.py Line 641-646 轉換了 case_in/out_path,但這是為了 `_copy_file`,不是為了 bind mount。

真正需要的是讓 CustomCheckerRunner 收到 host path 的 workdir。

---

## 6️⃣ 修復方案比較

### 方案 A: 在 custom_checker.py 內轉換 (推薦)

**修改位置:** `custom_checker.py` Line 67-72

```python
# 新增 import
from runner.path_utils import PathTranslator

# Line 67-72 修改
translator = PathTranslator()
host_workdir = translator.to_host(workdir)  # Container → Host

runner = CustomCheckerRunner(
    submission_id=submission_id,
    case_no=case_no,
    image=image,
    docker_url=docker_url,
    workdir=str(host_workdir),  # ✅ Host path!
    checker_relpath="custom_checker.py",
    time_limit_ms=time_limit_ms,
    mem_limit_kb=mem_limit_kb,
)
```

**優點:**
- 封裝在 custom_checker 模組內
- 不影響 dispatcher
- 使用標準 PathTranslator

---

### 方案 B: dispatcher 轉換後傳遞

**修改位置:** `dispatcher.py` Line 639-648

```python
checker_path = self._custom_checker_path(submission_id)
if checker_path:
    # 注意: case_in/out 轉換是為了 _copy_file, 已經在 Line 641-646
    # 這裡不需要再改它們
    
    checker_result = run_custom_checker_case(
        ...
        # 所有路徑保持原樣傳遞,讓 custom_checker.py 內部處理
    )
```

**說明:** 此方案不需改 dispatcher,在方案 A 內部處理即可。

---

### 方案 C: 回退 Line 641-646 的轉換 (不推薦)

**原因:** Line 641-646 的轉換是為了讓 `_copy_file` 能在 container 內訪問檔案,這是必要的。

如果回退,會導致 `_copy_file` 收到 host path,在 container 內找不到檔案。

---

## 7️⃣ 最終建議

### 推薦方案: 方案 A

**理由:**
1. 問題根源在於 `workdir` 傳給 Docker 時沒轉換
2. 在 custom_checker.py 內轉換最合理
3. 使用標準 PathTranslator,健壯且一致

### 需要修改的檔案

**只需修改:** `Sandbox/dispatcher/custom_checker.py`

**修改行數:** Line 67-72 (約 6 行)

**修改內容:**
```python
from runner.path_utils import PathTranslator  # 新增 import

# Line 67-72
translator = PathTranslator()
host_workdir = translator.to_host(workdir)

runner = CustomCheckerRunner(
    submission_id=submission_id,
    case_no=case_no,
    image=image,
    docker_url=docker_url,
    workdir=str(host_workdir),  # 使用 host path
    checker_relpath="custom_checker.py",
    time_limit_ms=time_limit_ms,
    mem_limit_kb=mem_limit_kb,
)
```

---

## 8️⃣ 驗證清單

修復後應該驗證:

- [ ] Custom checker container 能找到 `/workspace/custom_checker.py`
- [ ] `/workspace/input.in` 存在
- [ ] `/workspace/answer.out` 存在
- [ ] `/workspace/student.out` 存在
- [ ] Checker 能正常執行並返回 AC/WA
- [ ] 錯誤訊息不再出現 "can't open file"

---

## 📊 總結

### 您的診斷評價: ⭐⭐⭐⭐⭐

| 項目 | 評分 |
|------|------|
| 問題分析 | 5/5 完全正確 |
| 根因識別 | 5/5 精準定位 |
| 解法方向 | 5/5 切中要害 |
| 證據支持 | 5/5 客觀準確 |

### 關鍵洞察

1. ✅ 正確識別 container/host 路徑問題
2. ✅ 正確理解 Docker bind mount 需要 host path
3. ✅ 正確推斷空目錄的產生原因
4. ✅ 提出正確的解決方向

**唯一補充:** 不需要轉換 `case_in/out_path`,只需轉換 `workdir`

---

**驗證日期:** 2025-12-01 21:57  
**驗證結論:** ✅ **推論完全正確,可直接實施修復**  
**建議行動:** 採用方案 A,修改 custom_checker.py Line 67-72
