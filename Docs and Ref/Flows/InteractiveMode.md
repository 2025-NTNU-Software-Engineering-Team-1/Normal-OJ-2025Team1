# Interactive 執行模式架構文檔

## 概述

Interactive 模式是 Normal-OJ Sandbox 的三種執行模式之一（general / functionOnly / **interactive**），用於支援**互動式題目**。在此模式下，學生程式與教師程式透過管道（pipe）進行即時通訊，教師程式負責判題邏輯並產生最終判定結果。

## 核心概念

### 1. 雙程式架構
- **學生程式** (`/workspace/src`): 學生提交的程式碼
- **教師程式** (`/workspace/teacher`): 教師上傳的判題程式（`Teacher_file`）
- 兩程式在同一個 Docker 容器中執行，透過 FIFO 或 `/dev/fd` 進行 stdin/stdout 互聯

### 2. Build Strategy
Interactive 模式使用 `BuildStrategy.MAKE_INTERACTIVE` (值: 3)

## 配置參數

### Meta 欄位（`dispatcher/meta.py`）

```python
class Meta(BaseModel):
    language: Language                    # 學生程式語言
    executionMode: ExecutionMode          # 設為 INTERACTIVE
    buildStrategy: BuildStrategy          # 設為 MAKE_INTERACTIVE
    teacherFirst: bool = False            # 是否教師程式先執行
    assetPaths: Dict[str, str]            # 包含 teacher_file 和 teacherLang
```

#### 關鍵配置
- **`teacherFirst`**: 控制啟動順序
  - `False` (預設): 學生程式先啟動 → 延遲 50ms → 教師程式啟動
  - `True`: 教師程式先啟動 → 延遲 50ms → 學生程式啟動
  
- **`assetPaths`**:
  - `teacher_file`: MinIO 中教師檔案的路徑
  - `teacherLang`: 教師程式語言 (`"c"` / `"cpp"` / `"py"`)

## 執行流程

### Phase 1: 準備階段 (Dispatcher)

#### 1.1 Teacher_file 下載與準備
位置: [`dispatcher.py#L199-L224`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/dispatcher.py#L199-L224)

```python
def _prepare_teacher_file(self, problem_id, meta, submission_path):
    # 1. 解析教師語言
    teacher_lang_map = {"c": Language.C, "cpp": Language.CPP, "py": Language.PY}
    teacher_lang = teacher_lang_map.get(meta.assetPaths.get("teacherLang"))
    
    # 2. 從 MinIO 下載 teacher_file
    data = fetch_problem_asset(problem_id, "teacher_file")
    
    # 3. 寫入 teacher/main.{c,cpp,py}
    teacher_dir = submission_path / "teacher"
    ext = {Language.C: ".c", Language.CPP: ".cpp", Language.PY: ".py"}[teacher_lang]
    src_path = teacher_dir / f"main{ext}"
    src_path.write_bytes(data)
```

#### 1.2 教師程式編譯
位置: [`build_strategy.py#L180-L216`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/build_strategy.py#L180-L216)

**C/C++ 教師程式**:
```python
def _prepare_teacher_artifacts(meta, submission_dir):
    teacher_dir = submission_dir / "teacher"
    # 1. 編譯教師程式 (使用 SubmissionRunner.compile_at_path)
    compile_res = SubmissionRunner.compile_at_path(
        src_dir=str(teacher_dir.resolve()),
        lang=_lang_key(teacher_lang),
    )
    # 2. 產生 Teacher_main 二進位檔
    # 3. 建立 main 符號連結（供 sandbox_interactive 使用）
```

**Python 教師程式**:
- 直接使用 `teacher/main.py`，不需編譯

#### 1.3 學生程式建置
位置: [`build_strategy.py#L88-L102`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/build_strategy.py#L88-L102)

**CODE 模式**:
- C/C++: 直接編譯 `src/main.{c,cpp}` → `src/a.out`
- Python: 使用 `src/main.py`

**ZIP 模式**:
- 必須包含 `Makefile`
- 執行 `make` 產生 `src/a.out`
- Python: 產生 `src/main.py`

### Phase 2: 容器執行 (InteractiveRunner)

#### 2.1 啟動參數傳遞
位置: [`dispatcher.py#L511-L532`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/dispatcher.py#L511-L532)

```python
runner = InteractiveRunner(
    submission_id=submission_id,
    time_limit=time_limit,      # 毫秒
    mem_limit=mem_limit,         # KB
    case_in_path=case_in_path,   # 測資輸入檔路徑
    teacher_first=teacher_first, # 啟動順序
    lang_key=lang_key,           # "c11" / "cpp17" / "python3"
)
res = runner.run()
```

#### 2.2 Orchestrator 初始化
位置: [`interactive_orchestrator.py#L239-L283`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L239-L283)

**目錄權限設定**:
```python
# 允許 sandbox user (uid 1450) 寫入
_relax_dir_permissions(teacher_dir)  # teacher 可寫檔
_relax_dir_permissions(student_dir)  # student 目錄也需權限（但 seccomp 會阻止寫入）
```

**測資注入**:
```python
if case_in_path:
    case_local = teacher_dir / "testcase.in"
    case_local.write_bytes(src_case.read_bytes())
    # 執行後會自動刪除
```

### Phase 3: 管道通訊

#### 3.1 Pipe Mode 選擇
位置: [`interactive_orchestrator.py#L187-L236`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L187-L236)

**FIFO 模式** (優先嘗試):
```python
s2t = tmpdir / "s2t.fifo"  # student → teacher
t2s = tmpdir / "t2s.fifo"  # teacher → student
os.mkfifo(s2t)
os.mkfifo(t2s)
```

配置:
- Student stdin: `t2s.fifo`
- Student stdout: `s2t.fifo`
- Teacher stdin: `s2t.fifo`
- Teacher stdout: `t2s.fifo`

**devfd 模式** (Fallback):
```python
s2t_r, s2t_w = os.pipe()  # student → teacher pipe
t2s_r, t2s_w = os.pipe()  # teacher → student pipe
```

配置:
- Student stdin: `/dev/fd/{t2s_r}`
- Student stdout: `/dev/fd/{s2t_w}`
- Teacher stdin: `/dev/fd/{s2t_r}`
- Teacher stdout: `/dev/fd/{t2s_w}`

#### 3.2 Sandbox 命令生成
位置: [`interactive_orchestrator.py#L289-L320`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L289-L320)

```bash
# Student process
sandbox_interactive \
    <lang_id> \          # 0=C, 1=C++, 2=Python
    0 \                  # 固定參數
    <stdin_path> \       # FIFO 或 /dev/fd 路徑
    <stdout_path> \
    <stderr_path> \
    <time_limit_ms> \
    <mem_limit_kb> \
    1 \                  # 固定參數
    <output_limit_bytes> \
    10 \                 # 固定參數
    <result_file>

# Teacher process (相同格式，但參數不同)
```

#### 3.3 環境變數設定
位置: [`interactive_orchestrator.py#L321-L342`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L321-L342)

```python
# Student 環境
env_student["PWD"] = str(student_dir)
env_student.pop("SANDBOX_ALLOW_WRITE", None)  # 禁止寫檔

# Teacher 環境
env_teacher["PWD"] = str(teacher_dir)
env_teacher["SANDBOX_ALLOW_WRITE"] = "1"      # 允許寫檔
env_teacher["CASE_PATH"] = args.case_path     # 測資路徑
```

### Phase 4: 程式執行與監控

#### 4.1 啟動順序控制
位置: [`interactive_orchestrator.py#L365-L372`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L365-L372)

```python
if args.teacher_first:
    start_teacher()
    time.sleep(0.05)  # 50ms 延遲
    start_student()
else:
    start_student()
    time.sleep(0.05)
    start_teacher()
```

#### 4.2 Watchdog 監控
位置: [`interactive_orchestrator.py#L374-L393`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L374-L393)

```python
deadline = start_time + (time_limit_ms / 1000.0) + 2.0  # 時限 + 2 秒緩衝

while time.time() < deadline:
    all_done = all(proc.poll() is not None for proc in procs.values())
    if all_done:
        break
    time.sleep(0.05)

# 超時則 kill 所有程式
for proc in procs.values():
    if proc.poll() is None:
        proc.kill()
```

### Phase 5: 結果判定

#### 5.1 Sandbox 結果解析
位置: [`interactive_orchestrator.py#L62-L116`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L62-L116)

**Result 檔案格式**:
```
<status>           # "Exited Normally" / "TLE" / "MLE" / "RE" / "OLE"
<exit_info>        # 包含 "WEXITSTATUS() = <code>"
<time_ms>          # 執行時間（毫秒）
<mem_kb>           # 記憶體使用（KB）
```

**Status 映射**:
- `"Exited Normally"` → `AC`
- `"TLE"` → `TLE`
- `"MLE"` → `MLE`
- `"RE"` → `RE`
- `"OLE"` → `OLE` (Output Limit Exceeded)
- 其他 → `CE`

#### 5.2 Check_Result 解析
位置: [`interactive_orchestrator.py#L119-L131`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L119-L131)

教師程式必須在 `teacher/Check_Result` 寫入判定結果：

```
STATUS: AC
MESSAGE: All test cases passed
```

**STATUS 必須是以下之一**:
- `AC`: Accepted
- `WA`: Wrong Answer

#### 5.3 最終判定邏輯
位置: [`interactive_orchestrator.py#L431-L456`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L431-L456)

**優先順序**:
1. **學生程式錯誤** → 回傳學生狀態 (CE/RE/TLE/MLE/OLE)
2. **教師程式錯誤** → 回傳教師狀態 (CE/RE/TLE/MLE)
3. **Check_Result 無效** → `CE` (缺少或非法的 STATUS)
4. **Check_Result 有效** → 回傳 `AC` 或 `WA`

```python
if student_status != "AC":
    final_status = student_status
elif teacher_status != "AC":
    final_status = teacher_status
else:
    check_status, msg = _parse_check_result(teacher_dir / "Check_Result")
    if check_status is None:
        final_status = "CE"  # Check_Result 不存在或格式錯誤
    else:
        final_status = check_status  # "AC" 或 "WA"
```

#### 5.4 檔案數量檢查
位置: [`interactive_orchestrator.py#L453-L456`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L453-L456)

```python
teacher_new_files = _dir_file_count(teacher_dir) - teacher_files_before
if final_status == "AC" and teacher_new_files > max_new_files:
    final_status = "CE"
    message = f"teacher created too many files ({teacher_new_files})"
```

預設上限: `maxTeacherNewFiles = 500` (可在 `.config/interactive.json` 配置)

#### 5.5 返回結果
位置: [`interactive_orchestrator.py#L466-L480`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L466-L480)

```python
return {
    "Status": final_status,         # "AC" / "WA" / "CE" / "RE" / "TLE" / "MLE"
    "Stdout": "",                   # Interactive 模式不回傳 stdout
    "Stderr": message,              # 錯誤訊息或 Check_Result MESSAGE
    "Duration": duration_ms,        # 總執行時間
    "MemUsage": max(teacher_mem, student_mem),
    "DockerExitCode": 0,
    "pipeMode": pipe_mode,          # "fifo" 或 "devfd"
    "teacherStderr": teacher_err,   # 教師 stderr
    "studentStderr": student_err,   # 學生 stderr
    # ... 其他除錯資訊
}
```

## 資源限制

### 時間限制 (Time Limit)
- 設定在 `sandbox_interactive` 的 `RLIMIT_CPU`
- Watchdog 額外加 2 秒緩衝
- 超時會 kill 兩個程式

### 記憶體限制 (Memory Limit)
- 設定在 `sandbox_interactive` 的 `RLIMIT_AS`
- 學生與教師**各自獨立計算**
- 回傳結果取兩者最大值

### 輸出限制 (Output Limit)
- 預設：64 MB (`outputLimitBytes`)
- 超過會觸發 `OLE` 狀態

### 檔案大小限制
- `RLIMIT_FSIZE` 限制單一檔案寫入大小
- 教師程式最多新增 500 個檔案

### Seccomp 寫入保護
- **學生程式**: 禁止 `open(O_WRONLY)`, `creat`, `write` 等系統呼叫
- **教師程式**: `SANDBOX_ALLOW_WRITE=1` 允許寫檔（用於產生 `Check_Result`）

## 錯誤處理

### 常見錯誤場景

#### 1. 教師檔案缺失
```python
# dispatcher.py#L213
raise BuildStrategyError("interactive mode requires Teacher_file")
```

#### 2. 教師語言缺失
```python
# dispatcher.py#L207
raise BuildStrategyError("teacherLang missing in meta.assetPaths")
```

#### 3. 教師編譯失敗
```python
# build_strategy.py#L193-L196
if compile_res.get("Status") != "AC":
    raise BuildStrategyError(f"teacher compile failed: {err_msg}")
```

#### 4. Makefile 缺失 (ZIP 模式)
```python
# build_strategy.py#L132-L133
if not (src_dir / "Makefile").exists():
    raise BuildStrategyError("Makefile not found in submission directory")
```

#### 5. Check_Result 無效
```python
# interactive_orchestrator.py#L129-L130
if status not in ("AC", "WA"):
    return None, "Invalid Check_Result STATUS"
```

## 配置檔案

### `.config/interactive.json`
```json
{
  "outputLimitBytes": 67108864,   // 64 MB
  "maxTeacherNewFiles": 500
}
```

## 測試覆蓋

位置: `tests/test_interactive.py`

涵蓋場景:
- ✅ AC/WA 基本流程
- ✅ Check_Result 缺少或非法
- ✅ `teacherFirst` 切換
- ✅ FIFO → `/dev/fd` fallback
- ✅ 學生寫檔被 seccomp 阻擋 (C/Python)
- ✅ 教師可寫檔
- ✅ 師/生 TLE
- ✅ RLIMIT_FSIZE 觸發
- ✅ 大量檔案觸發 CE
3. **資源隔離**: 各自的時間/記憶體限制 + seccomp 保護
4. **靈活判題**: Check_Result 支援 AC/WA，教師程式完全控制判定邏輯
5. **錯誤優先**: 任一方錯誤覆蓋 Check_Result，確保系統穩定性
