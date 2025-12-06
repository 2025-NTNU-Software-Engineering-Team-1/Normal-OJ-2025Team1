# 靜態分析完整文檔

## 概述

靜態分析（Static Analysis, SA）是 Sandbox 在執行代碼前的安全檢查機制，用於檢測學生代碼是否使用了受限的庫函數、語法結構或非法操作。SA 支援 C/C++（使用 libclang）和 Python（使用 AST）。

**相關流程圖**: [STATIC_ANALYSIS_FLOW.html](../Flows/STATIC_ANALYSIS_FLOW.html)

---

## 支援語言

| 語言 | 分析工具 | 檢查項目 |
|------|---------|---------|
| **C/C++** | libclang | imports（#include）、functions、syntax patterns |
| **Python** | AST (ast module) | imports、functions、syntax patterns |

---

## 核心組件

### 1. StaticAnalyzer 類

**位置**: `dispatcher/static_analysis.py` L312-649

**主要方法**:

```python
class StaticAnalyzer:
    def __init__(self):
        self.result = AnalysisResult()
    
    def analyze(self, submission_id, language, rules, base_dir):
        """主要分析入口"""
    
    def analyze_zip_sources(self, source_dir, language, rules):
        """ZIP 模式專用：分析目錄中的所有源檔案"""
    
    def _analyze_python(self, source_path, rules, files):
        """Python AST 分析"""
    
    def _analyze_c_cpp(self, source_path, rules, files):
        """C/C++ libclang 分析"""
```

### 2. AnalysisResult 類

**位置**: `dispatcher/static_analysis.py` L212-309

**用途**: 封裝分析結果

```python
class AnalysisResult:
    def __init__(self, success=True, message="", rules="", facts="", violations=""):
        self._success = success      # 是否通過
        self._message = message      # 錯誤訊息
        self._rules = rules          # 應用的規則
        self._facts = facts          # 檢測到的事實
        self._violations = violations # 違規項目
    
    def is_success(self) -> bool
    def mark_skipped(self, msg: str)
    def good_look_output_rules(self, rules: dict)
    def good_look_output_facts(self, facts: dict)
    def good_look_output_violations(self, violations: dict)
```

---

## 分析流程

### 整體流程

**觸發位置**: `dispatcher/dispatcher.py` `handle()` 方法

```python
# 1. 獲取規則
rules_json = fetch_problem_rules(problem_id)

# 2. 執行靜態分析
success, sa_payload, fail_tasks = run_static_analysis(
    submission_id=submission_id,
    submission_path=submission_path,
    meta=meta,
    rules_json=rules_json,
    is_zip_mode=(meta.submissionMode == SubmissionMode.ZIP)
)

# 3. 處理結果
if not success:
    # SA 失敗，回報 CE
    self.on_submission_complete(submission_id, fail_tasks)
    return
```

### 詳細流程

#### 1. 規則獲取

**API**: `GET /problem/<id>/rules`

**返回格式**:
```json
{
  "libraryRestrictions": {
    "imports": {
      "blacklist": ["os", "subprocess"],
      "whitelist": []
    },
    "functions": {
      "blacklist": ["system", "exec"],
      "whitelist": []
    },
    "syntax": {
      "blacklist": [
        {"type": "ImportFrom", "module": "os"},
        {"type": "Call", "func": "eval"}
      ]
    }
  }
}
```

**特殊情況**:
- 404: 題目未設置規則，跳過 SA
- 規則為空: 跳過 SA

#### 2. 源檔案收集

**CODE 模式**:
```python
# 直接分析 main.c/cpp/py
source_path = submission_path / "src" / "common" / f"main.{ext}"
```

**ZIP 模式** (調用 `analyze_zip_sources`):

1. **檢查非法檔案**:
   ```python
   disallowed_exts = {".exe", ".so", ".dll", ".dylib", ".jar", ".class"}
   for item in source_dir.rglob("*"):
       if item.suffix.lower() in disallowed_exts:
           raise StaticAnalysisError(f"Disallowed file type: {item.suffix}")
   ```

2. **決定掃描策略**:
   - **有 Makefile**: 解析 Makefile 找出源檔案
     ```python
     sources = _collect_sources_from_makefile(source_dir, language)
     ```
   - **無 Makefile**: 掃描所有允許的副檔名
     ```python
     sources = _collect_sources_by_ext(source_dir, language)
     ```

3. **語言一致性檢查**:
   ```python
   # 如果題目是 C，不允許 .cpp 檔案
   # 如果題目是 Python，不允許 .c/.cpp 檔案
   ```

#### 3. 程式碼分析

##### Python 分析 (AST)

**函數**: `_analyze_python()` L433-487

**流程**:
```python
def _analyze_python(self, source_path, rules, files):
    # 1. 解析所有 Python 檔案
    for f in files:
        try:
            tree = ast.parse(f.read_text())
        except SyntaxError as e:
            self.result._success = False
            self.result._message = f"Syntax Error: {e}"
            return
    
    # 2. AST 遍歷收集事實
    for node in ast.walk(tree):
        # Import
        if isinstance(node, ast.Import):
            for alias in node.names:
                facts["imports"].add(alias.name)
        
        # ImportFrom
        if isinstance(node, ast.ImportFrom):
            facts["imports"].add(node.module)
        
        # Function Call
        if isinstance(node, ast.Call):
            if isinstance(node.func, ast.Name):
                facts["functions"].add(node.func.id)
    
    # 3. 檢查違規
    self._check_list_violations(facts["imports"], rules["imports"], "import")
    self._check_list_violations(facts["functions"], rules["functions"], "function")
    self._check_syntax_violations(facts, rules["syntax"], "syntax")
```

**AST 節點類型**:
- `ast.Import`: `import os`
- `ast.ImportFrom`: `from os import path`
- `ast.Call`: `print()`, `eval()`
- `ast.Name`: 變數名稱
- 其他: `ast.FunctionDef`, `ast.ClassDef`, etc.

##### C/C++ 分析 (libclang)

**函數**: `_analyze_c_cpp()` L489-567

**流程**:
```python
def _analyze_c_cpp(self, source_path, rules, files):
    if clang is None:
        # clang 未安裝，標記為 skip
        self.result.mark_skipped("libclang not available")
        return
    
    # 1. 初始化 libclang index
    index = clang.cindex.Index.create()
    
    # 2. 解析每個源檔案
    for f in files:
        tu = index.parse(
            str(f),
            args=detect_include_args()  # 自動檢測 include 路徑
        )
        
        # 3. 遍歷 AST
        for node in tu.cursor.walk_preorder():
            # Include Directive
            if node.kind == clang.cindex.CursorKind.INCLUSION_DIRECTIVE:
                header = node.spelling  # <stdio.h>
                facts["imports"].add(header)
            
            # Function Call
            if node.kind == clang.cindex.CursorKind.CALL_EXPR:
                func_name = node.spelling
                facts["functions"].add(func_name)
    
    # 4. 檢查違規
    self._check_list_violations(facts["imports"], rules["imports"], "include")
    self._check_list_violations(facts["functions"], rules["functions"], "function")
```

**libclang CursorKind**:
- `INCLUSION_DIRECTIVE`: `#include <...>`
- `CALL_EXPR`: 函式調用
- `FUNCTION_DECL`: 函式定義
- 其他: `VAR_DECL`, `IF_STMT`, etc.

#### 4. 違規檢查

```python
def _check_list_violations(self, used_items, rule_items, model, item_type):
    # 黑名單檢查
    if "blacklist" in rule_items:
        violations = used_items & set(rule_items["blacklist"])
        if violations:
            self.result._success = False
            self.result._violations[item_type] = list(violations)
    
    # 白名單檢查
    if "whitelist" in rule_items:
        violations = used_items - set(rule_items["whitelist"])
        if violations:
            self.result._success = False
            self.result._violations[item_type] = list(violations)
```

#### 5. 結果封裝

**函數**: `build_sa_payload()` L100-121

```python
def build_sa_payload(analysis_result, status: str):
    return {
        "status": status,  # "pass" / "fail" / "skip"
        "message": analysis_result._message,
        "rules": analysis_result._rules,
        "facts": analysis_result._facts,
        "violations": analysis_result._violations,
        "report": analysis_result.report_text()
    }
```

---

## Makefile 解析

**函數**: `_collect_sources_from_makefile()` L68-87

**策略**: 使用正則表達式提取源檔案名稱

```python
def _collect_sources_from_makefile(source_dir, language):
    makefile = source_dir / "Makefile"
    content = makefile.read_text()
    
    # 匹配模式：SOURCES = main.c utils.c
    # 或：a.out: main.c utils.c
    pattern = r'(\w+\.(c|cpp|py)\b)'
    matches = re.findall(pattern, content)
    
    # 收集檔案
    sources = []
    for match in matches:
        filename = match[0]
        filepath = source_dir / filename
        if filepath.exists():
            sources.append(filepath)
    
    return sources
```

**侷限性**:
- 只能處理簡單的 Makefile
- 不支援變數展開（`$(SRC)`）
- 不支援條件編譯（`ifdef`）

**Fallback**: 若解析失敗或結果為空，回退到按副檔名掃描

---

## 錯誤處理

### Skip 場景

SA 會跳過（不回報錯誤）的情況：

1. **libclang 未安裝**:
   ```python
   if clang is None:
       result.mark_skipped("libclang not available")
   ```

2. **題目未設置規則**:
   ```python
   if rules_json is None or not rules_json:
       return (True, build_sa_payload(result, "skip"), None)
   ```

3. **解析 Makefile 失敗但有 fallback**:
   ```python
   sources = _collect_sources_from_makefile(...)
   if not sources:
       sources = _collect_sources_by_ext(...)  # 不視為錯誤
   ```

### Fail 場景

SA 會回報失敗（CE）的情況：

1. **語法錯誤**:
   ```python
   except SyntaxError as e:
       result._success = False
       result._message = f"Syntax Error: {e}"
   ```

2. **違規檢測**:
   ```python
   if violations:
       result._success = False
       result._violations[item_type] = list(violations)
   ```

3. **非法檔案類型** (ZIP 模式):
   ```python
   if item.suffix.lower() in disallowed_exts:
       raise StaticAnalysisError(f"Disallowed file type: {item.suffix}")
   ```

4. **語言不一致** (ZIP 模式):
   ```python
   if language == Language.C and any(f.suffix == ".cpp" for f in sources):
       raise StaticAnalysisError("C problem cannot contain .cpp files")
   ```

### CE Task 生成

**函數**: `build_sa_ce_task_content()` L130-146

```python
def build_sa_ce_task_content(meta: "Meta", stderr: str):
    """為所有 testcase 生成 CE 結果"""
    tasks = []
    for task in meta.tasks:
        cases = []
        for case in task["caseCount"]:
            cases.append({
                "Status": "CE",
                "Stdout": "",
                "Stderr": stderr,
                "Duration": 0,
                "MemUsage": 0
            })
        tasks.append({"cases": cases})
    return tasks
```

---

## 報告格式

### 報告範例

```
========== Static Analysis Report ==========

Rules Applied:
  imports:
    blacklist: os, subprocess, socket
  functions:
    blacklist: system, exec, eval

Detected Facts:
  imports: math, random
  functions: print, input, range

Violations Found:
  ❌ Forbidden import detected: os
  ❌ Forbidden function detected: eval

Analysis Result: FAILED
============================================
```

### 報告生成

**方法**: `AnalysisResult.report_text()`

```python
def report_text(self):
    lines = ["=" * 50]
    lines.append("Static Analysis Report")
    lines.append("=" * 50)
    
    if self._rules:
        lines.append("\nRules Applied:")
        lines.append(self.good_look_output_rules(self._rules))
    
    if self._facts:
        lines.append("\nDetected Facts:")
        lines.append(self.good_look_output_facts(self._facts))
    
    if self._violations:
        lines.append("\nViolations Found:")
        lines.append(self.good_look_output_violations(self._violations))
    
    lines.append(f"\nResult: {'PASS' if self._success else 'FAIL'}")
    lines.append("=" * 50)
    
    return "\n".join(lines)
```

---

## 配置與使用

### Backend 配置

**API**: `GET /problem/<id>/rules`

**Response**:
```json
{
  "libraryRestrictions": {
    "imports": {
      "blacklist": ["os", "sys"],
      "whitelist": []
    },
    "functions": {
      "blacklist": ["system", "eval"],
      "whitelist": ["print", "input", "len"]
    },
    "syntax": {
      "blacklist": [
        {"type": "ImportFrom", "module": "os"},
        {"type": "Exec"}  
      ]
    }
  }
}
```

### Dispatcher 使用

```python
# dispatcher.py
from dispatcher.static_analysis import run_static_analysis

# 獲取規則
rules_json = fetch_problem_rules(problem_id)

# 執行 SA
success, payload, fail_tasks = run_static_analysis(
    submission_id=submission_id,
    submission_path=Path(f"submissions/{submission_id}"),
    meta=meta,
    rules_json=rules_json,
    is_zip_mode=True
)

# 處理結果
if not success:
    # 回報 CE
    self.on_submission_complete(submission_id, fail_tasks)
```

---

## 最佳實踐

### 1. 規則設計

**黑名單優先**:
```json
{
  "imports": {
    "blacklist": ["os", "subprocess", "socket"],
    "whitelist": []
  }
}
```

**白名單嚴格**:
```json
{
  "functions": {
    "blacklist": [],
    "whitelist": ["print", "input", "int", "str", "len", "range"]
  }
}
```

### 2. Syntax 模式匹配

**Python AST 類型**:
```json
{
  "syntax": {
    "blacklist": [
      {"type": "Exec"},           // exec()
      {"type": "Global"},         // global keyword
      {"type": "ImportFrom", "module": "os"}  // from os import ...
    ]
  }
}
```

**C/C++ 不支援 syntax 檢查**（libclang 限制）

### 3. Makefile 編寫規範

**推薦格式**:
```makefile
# 明確列出源檔案
SOURCES = main.c utils.c helper.c

# 或使用目標依賴
a.out: main.c utils.c
	gcc -o a.out main.c utils.c
```

**避免**:
```makefile
# ❌ 使用變數（SA 無法解析）
SRC = $(wildcard *.c)

# ❌ 條件編譯
ifdef DEBUG
    SOURCES = debug.c
endif
```

---

## 限制與已知問題

### 1. libclang 依賴

**問題**: 若容器未安裝 libclang，C/C++ SA 會 skip

**影響**: 無法檢測 C/C++ 違規

**解決方法**:
- 在 Docker 鏡像中安裝 `libclang-dev`
- 或接受 skip 狀態（不強制執行 SA）

### 2. Makefile 解析限制

**問題**: 只能處理簡單的 Makefile

**Fallback**: 掃描所有允許的副檔名

### 3. Python Sandbox 限制

**問題**: SA 只能靜態分析，無法防止運行時行為

**例如**:
```python
# SA 可檢測
import os
os.system("rm -rf /")

# SA 無法檢測
exec("import os; os.system('rm -rf /')")
getattr(__import__('os'), 'system')('rm -rf /')
```

**解決方法**: 結合 Seccomp 和容器隔離

### 4. 性能考量

**大型 ZIP**:
- 多個源檔案增加分析時間
- 建議限制 ZIP 大小（≤ 1GB）和檔案數量（≤ 100）

---

## 測試

### 單元測試

**位置**: `tests/test_static_analysis.py`

```python
def test_python_ast_analysis():
    # 測試 Python AST 解析
    pass

def test_c_cpp_libclang_analysis():
    # 測試 C/C++ libclang 解析
    pass

def test_makefile_parsing():
    # 測試 Makefile 解析
    pass

def test_zip_mode_analysis():
    # 測試 ZIP 模式完整流程
    pass
```

### 整合測試

**測試場景**:
1. ✅ 黑名單違規檢測
2. ✅ 白名單通過檢測
3. ✅ Syntax 違規檢測
4. ✅ 多檔案 ZIP 分析
5. ✅ libclang 缺失 fallback
6. ✅ 語言不一致拒絕

---

## 相關文檔

- [CONFIG_REFERENCE.md](./CONFIG_REFERENCE.md) - 配置參數
- [BUILD_STRATEGY_GUIDE.md](./BUILD_STRATEGY_GUIDE.md) - Build Strategy
- [STATIC_ANALYSIS_FLOW.html](../Flows/STATIC_ANALYSIS_FLOW.html) - 流程圖
- [SA_FAILURE_FLOW.md](../Flows/SA_FAILURE_FLOW.md) - SA 失敗流程

---

## 總結

靜態分析系統提供了代碼執行前的安全防護：

✅ **多語言支援**: C/C++ (libclang) + Python (AST)  
✅ **靈活規則**: 黑名單/白名單/語法模式  
✅ **ZIP 模式**: Makefile 解析 + 多檔案掃描  
✅ **容錯機制**: libclang 缺失時 skip，不阻斷流程  
✅ **詳細報告**: 提供完整的規則、事實、違規信息  

關鍵設計：
- 🔒 **安全優先**: 在執行前攔截危險代碼
- 🚀 **性能優化**: AST 遍歷比執行快數倍
- 🛡️ **深度防禦**: SA + Seccomp + 容器隔離三層保護
- 📊 **可觀測性**: 詳細的分析報告幫助調試
