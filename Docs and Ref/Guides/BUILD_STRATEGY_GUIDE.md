# Build Strategy 完整指南

## 概述

Build Strategy 是 Sandbox 中用於處理不同類型代碼提交的構建策略系統。根據提交模式（CODE/ZIP）和執行模式（General/FunctionOnly/Interactive），Dispatcher 會選擇相應的 Build Strategy 來準備學生和教師的可執行檔案。

**相關流程圖**: [BUILD_STRATEGY_FLOW.html](../Flows/BUILD_STRATEGY_FLOW.html)

---

## Build Strategy 類型

### 策略對照表

| Build Strategy | 提交模式 | 執行模式 | 用途 |
|----------------|----------|----------|------|
| **compile** | CODE | General | 單檔程式直接編譯 |
| **makeNormal** | ZIP | General | ZIP 提交使用 Makefile 構建 |
| **makeFunctionOnly** | CODE | FunctionOnly | 函式題型（教師提供 Makefile） |
| **makeInteractive** | CODE/ZIP | Interactive | 互動題型（需編譯教師程式） |

---

## 核心組件

### 1. BuildPlan

**定義位置**: `dispatcher/build_strategy.py` L26-30

```python
@dataclass
class BuildPlan:
    needs_make: bool                          # 是否需要執行 make
    lang_key: Optional[str] = None            # 語言鍵（"c11"/"cpp17"/"python3"）
    finalize: Optional[Callable[[], None]] = None  # 後處理函數
```

**用途**: 封裝構建計劃，由策略函數返回給 Dispatcher

**欄位說明**:
- `needs_make`: 
  - `True`: Dispatcher 會創建 Build Job 執行 `make`
  - `False`: Python 代碼，跳過 make 直接執行
- `lang_key`: 傳遞給 `SubmissionRunner.build_with_make()` 選擇 Docker 鏡像
- `finalize`: make 成功後執行的回調函數，用於整理檔案（如 rename `a.out` → `main`）

---

### 2. BuildStrategyError

**定義**: `dispatcher/build_strategy.py` L15-16

```python
class BuildStrategyError(ValueError):
    """Raised when a build strategy cannot be applied."""
```

**觸發場景**:
- 缺少必要檔案（Makefile、main.py、teacher_file）
- 編譯失敗（教師程式）
- 產出檔案不符合要求（多個可執行檔、缺少 a.out）

**錯誤處理**: Dispatcher 會捕獲此異常並回報 CE（Compilation Error）

---

## 策略詳解

### compile - 單檔直接編譯

**使用場景**: CODE 模式提交單一 C/C++ 檔案

**流程**:
1. 學生上傳 `main.c` / `main.cpp`
2. Dispatcher 直接調用 `SubmissionRunner.compile()`
3. 生成可執行檔
4. 進入測資執行流程

**特點**:
- ✅ 最簡單的策略
- ✅ 無需 Makefile
- ✅ Python 直接執行不編譯
- ❌ 不支援多檔案專案

---

### makeNormal - ZIP 使用 Makefile

**使用場景**: ZIP 模式提交多檔案專案

**函數**: `prepare_make_normal()` (L33-40)

**流程**:

1. **檢查 Makefile**
   ```python
   _ensure_makefile(src_dir)  # 確保存在 Makefile
   ```

2. **返回 BuildPlan**
   ```python
   return BuildPlan(
       needs_make=True,
       lang_key=_lang_key(meta.language),
       finalize=_finalize_compiled_binary
   )
   ```

3. **執行 make** (由 Dispatcher 處理)
   - 在 Docker 容器中執行 `make`
   - 使用 lock 機制防止並發構建

4. **Finalize 步驟**
   ```python
   def _finalize_compiled_binary(src_dir, language):
       # 檢查 a.out 存在
       binary_path = src_dir / "a.out"
       if not binary_path.exists():
           raise BuildStrategyError("a.out not found after running make")
       
       # 確保只有一個可執行檔
       _ensure_single_executable(src_dir, allowed={"a.out"})
       
       # Rename a.out → main
       target = src_dir / "main"
       os.replace(binary_path, target)
       os.chmod(target, target.stat().st_mode | 0o111)
   ```

**注意**: 所有構建操作都在 `src/common` 目錄下進行。構建完成後，Dispatcher 會將此目錄的內容複製到各個 `src/cases/<case_no>` 目錄中進行執行。

**關鍵檢查**:
- ✅ Makefile 必須存在
- ✅ 編譯後必須產生唯一的 `a.out`
- ✅ 不允許多個可執行檔（安全考量）
- ✅ Python 只需 `main.py`，不需 make

---

### makeFunctionOnly - 函式題型

**使用場景**: 學生只寫函式，教師提供測試框架

**函數**: `prepare_function_only_submission()` (L54-85)

**流程**:

1. **讀取學生代碼**
   ```python
   student_path = _student_entry_path(src_dir, language)  # main.c/cpp/py
   student_code = student_path.read_text()
   ```

2. **下載教師 Makefile**
   ```python
   make_asset = meta.assetPaths.get("makefile")
   if not make_asset:
       raise BuildStrategyError("functionOnly mode requires makefile asset")
   archive = fetch_problem_asset(problem_id, "makefile")
   ```

3. **重置 src 目錄**
   ```python
   _reset_directory(src_dir)  # 清空所有檔案
   ```

4. **解壓教師 Makefile.zip**
   ```python
   with zipfile.ZipFile(io.BytesIO(archive)) as zf:
       zf.extractall(src_dir)
   ```

5. **插入學生代碼**
   ```python
   # C/C++: function.h
   # Python: student_impl.py
   template_name = ("function.h" if meta.language in (Language.C, Language.CPP) 
                     else "student_impl.py")
   template_path = src_dir / template_name
   template_path.write_text(student_code)
   ```

6. **執行 make + Finalize**
   - Build Job 執行 `make`
   - Finalize 檢查並 rename 可執行檔

**目錄結構範例**:

```
# 執行前（學生上傳）
src/common/
└── main.c  (學生的函式實作)

# 處理中（解壓教師 makefile.zip 後）
src/common/
├── Makefile         (教師提供)
├── test_main.c      (教師的測試框架)
├── function.h       (學生代碼插入此處)
└── ...

# 執行後（make 完成）
src/common/
├── main             (最終可執行檔)
└── ...
```

**安全機制**:
- ✅ `_reset_directory()` 防止學生上傳惡意 Makefile
- ✅ 教師完全控制構建流程
- ✅ 學生代碼被隔離在指定模板中

---

### makeInteractive - 互動題型

**使用場景**: 學生程式與教師程式互動

**函數**: `prepare_make_interactive()` (L43-51)

**流程**:

1. **準備教師檔案**
   ```python
   _prepare_teacher_artifacts(meta=meta, submission_dir=submission_dir)
   ```

   - **下載教師源碼** (由 Dispatcher 處理):
     ```python
     teacher_file = fetch_problem_asset(problem_id, "teacher_file")
     (teacher_dir / "main.{c,cpp,py}").write_bytes(teacher_file)
     ```

   - **編譯教師程式** (C/C++ only):
     ```python
     compile_res = SubmissionRunner.compile_at_path(
         src_dir=str(teacher_dir),
         lang=lang_key
     )
     if compile_res["Status"] != "AC":
         raise BuildStrategyError("teacher compile failed")
     ```

   - **創建執行檔連結**:
     ```python
     binary = teacher_dir / "Teacher_main"
     main_exec = teacher_dir / "main"
     os.link(binary, main_exec)  # 或 shutil.copy
     ```

2. **準備學生檔案**
   ```python
   return _build_plan_for_student_artifacts(
       language=meta.language,
       src_dir=submission_dir / "src"
   )
   ```

   - CODE 模式: 直接編譯 `main.c/cpp` 或使用 `main.py`
   - ZIP 模式: 使用 Makefile 構建

**目錄結構**:

```
submission_dir/
├── teacher/
│   ├── main.c           (教師源碼)
│   ├── Teacher_main     (編譯後的二進位)
│   └── main             (符號連結或複製)
└── src/
    └── common/          (構建目錄)
        ├── main.c       (學生源碼)
        ├── Makefile     (ZIP 模式才有)
        └── main         (編譯後或 rename 的可執行檔)
```

**與 FunctionOnly 的區別**:
| 項目 | FunctionOnly | Interactive |
|------|--------------|-------------|
| 學生角色 | 實作函式 | 完整程式 |
| 教師角色 | 提供測試框架（Makefile.zip） | 提供互動程式（單檔） |
| 執行方式 | 單程式測資執行 | 雙程式管道通訊 |
| 目錄重置 | ✅ 重置 src | ❌ 不重置 |

---

## 構建流程

### 1. Strategy 選擇

**位置**: `dispatcher/dispatcher.py` `handle()` 方法

```python
# 根據 meta.buildStrategy 選擇
if meta.buildStrategy == BuildStrategy.COMPILE:
    # 直接編譯，不需 BuildPlan
    pass
elif meta.buildStrategy == BuildStrategy.MAKE_NORMAL:
    plan = prepare_make_normal(meta, submission_dir)
elif meta.buildStrategy == BuildStrategy.MAKE_FUNCTION_ONLY:
    plan = prepare_function_only_submission(problem_id, meta, submission_dir)
elif meta.buildStrategy == BuildStrategy.MAKE_INTERACTIVE:
    plan = prepare_make_interactive(meta, submission_dir)
```

### 2. Build Job 創建

**當 `plan.needs_make == True`**:

```python
if plan.needs_make:
    self.queue.put(job.Build(
        submission_id=submission_id,
        lang_key=plan.lang_key,
        submission_path=submission_path,
        finalize=plan.finalize
    ))
```

### 3. Build Queue 處理

**使用 Lock 機制防止並發構建**:

```python
# Dispatcher.run() 主循環
job = self.queue.get()

if isinstance(job, job.Build):
    # 獲取構建鎖
    with self.build_lock:
        result = SubmissionRunner.build_with_make(
            src_dir=str(job.submission_path / "src"),
            lang=job.lang_key
        )
        
        if result["Status"] == "AC":
            # 執行 finalize
            if job.finalize:
                job.finalize()
        else:
            # 構建失敗，清空該 submission 的所有任務
            self._clear_submission_tasks(job.submission_id)
            self.on_submission_complete(job.submission_id, CE_result)
```

### 4. Finalize 步驟

**作用**: 整理構建產物，確保符合執行要求

**常見操作**:
- ✅ 檢查必要檔案存在（a.out、main.py）
- ✅ Rename `a.out` → `main`
- ✅ 設置執行權限 (`chmod +x`)
- ✅ 驗證唯一可執行檔
- ❌ 產物不符合要求則拋出 `BuildStrategyError`

---

## Helper Functions

### _student_entry_path()

**作用**: 獲取學生入口檔案路徑

```python
def _student_entry_path(src_dir: Path, language: Language) -> Path:
    suffix = {Language.C: ".c", Language.CPP: ".cpp", Language.PY: ".py"}[language]
    return src_dir / f"main{suffix}"
```

### _ensure_makefile()

**作用**: 確保 Makefile 存在

```python
def _ensure_makefile(src_dir: Path):
    if not (src_dir / "Makefile").exists():
        raise BuildStrategyError("Makefile not found")
```

### _ensure_single_executable()

**作用**: 確保只有一個可執行檔

```python
def _ensure_single_executable(src_dir: Path, allowed: Iterable[str]):
    exec_files = [f for f in src_dir.iterdir() 
                  if f.is_file() and os.access(f, os.X_OK)]
    extras = [f for f in exec_files if f.name not in allowed]
    if extras:
        raise BuildStrategyError("only one executable allowed")
```

### _reset_directory()

**作用**: 清空目錄（FunctionOnly 使用）

```python
def _reset_directory(target: Path):
    for child in target.iterdir():
        if child.is_file():
            child.unlink()
        else:
            shutil.rmtree(child)
```

---

## 錯誤處理

### 常見錯誤

| 錯誤訊息 | 原因 | 解決方法 |
|---------|------|---------|
| `Makefile not found` | ZIP 提交缺少 Makefile | 確保上傳的 ZIP 包含 Makefile |
| `a.out not found after running make` | Makefile 未產生 a.out | 檢查 Makefile 構建目標 |
| `only one executable allowed` | ZIP 包含多個可執行檔 | 修改 Makefile 只產生 a.out |
| `teacher compile failed` | 教師程式編譯錯誤 | 檢查教師源碼語法錯誤 |
| `functionOnly mode requires makefile asset` | 題目缺少 makefile 資源 | 上傳教師 makefile.zip |

### 調試技巧

1. **查看 Build Log**:
   ```python
   # Dispatcher 會記錄構建輸出
   logger().info(f"Build result: {result}")
   ```

2. **檢查目錄狀態**:
   ```bash
   # 構建失敗後檢查檔案
   ls -la submissions/<id>/src/
   ```

3. **手動測試 Makefile**:
   ```bash
   cd submissions/<id>/src
   make
   ls -la  # 檢查產物
   ```

---

## 測試

### 單元測試

**位置**: `tests/test_build_strategy.py`

```python
def test_prepare_make_normal():
    # 測試 ZIP 模式構建
    pass

def test_prepare_function_only():
    # 測試 FunctionOnly 模式
    pass

def test_prepare_interactive():
    # 測試 Interactive 模式的教師編譯
    pass
```

### 整合測試

**測試完整流程**:
1. 提交 → Strategy 選擇 → Build Job → Finalize → Execute

---

## 最佳實踐

### 1. Makefile 規範

**學生 Makefile（ZIP 模式）**:
```makefile
CC = gcc
CFLAGS = -Wall -O2

all: a.out

a.out: main.c
	$(CC) $(CFLAGS) main.c -o a.out

clean:
	rm -f a.out *.o
```

**教師 Makefile（FunctionOnly）**:
```makefile
CC = gcc
CFLAGS = -Wall -O2

all: a.out

a.out: test_main.c function.h
	$(CC) $(CFLAGS) test_main.c -o a.out

clean:
	rm -f a.out *.o
```

### 2. 教師檔案命名

- ✅ C: `main.c`
- ✅ C++: `main.cpp`
- ✅ Python: `main.py`
- ❌ 不要使用其他名稱（會導致自動推斷失敗）

### 3. Python 模板

**FunctionOnly Python 範例**:

```python
# student_impl.py (學生提交)
def solve(a, b):
    return a + b

# main.py (教師提供的測試框架)
from student_impl import solve

def test():
    assert solve(1, 2) == 3
    print("All tests passed")

if __name__ == "__main__":
    test()
```

---

## 與其他模組的整合

### Dispatcher

```python
# handle() 方法
plan = self._prepare_with_build_strategy(submission_id, meta)
if plan and plan.needs_make:
    self.queue.put(job.Build(...))
```

### SubmissionRunner

```python
# build_with_make() 方法
result = SubmissionRunner.build_with_make(
    src_dir=str(submission_path / "src"),
    lang="cpp17"
)
```

### Static Analysis

- FunctionOnly: SA 在 `prepare_` 前執行（學生原始碼）
- ZIP/Interactive: SA 在解壓後執行（所有源碼）

---

## 相關文檔

- [CONFIG_REFERENCE.md](./CONFIG_REFERENCE.md) - 配置參數說明
- [02_STATIC_ANALYSIS.md](./02_STATIC_ANALYSIS.md) - 靜態分析流程
- [BUILD_STRATEGY_FLOW.html](../Flows/BUILD_STRATEGY_FLOW.html) - 流程圖
- [05_INTERACTIVE.md](./05_INTERACTIVE.md) - Interactive 模式詳解
- [04_FUNCTION_ONLY.md](./04_FUNCTION_ONLY.md) - FunctionOnly 流程

---

## 總結

Build Strategy 系統提供了靈活且安全的代碼構建機制：

1. **compile**: 最簡單，適合單檔提交
2. **makeNormal**: 支援複雜專案，使用學生 Makefile
3. **makeFunctionOnly**: 教師控制構建，學生只寫函式
4. **makeInteractive**: 需編譯教師程式，支援互動評測

關鍵設計：
- ✅ BuildPlan 抽象化構建流程
- ✅ Lock 機制防止並發構建衝突
- ✅ Finalize 步驟確保產物一致性
- ✅ 嚴格的錯誤檢查保證安全性
