# Interactive Mode Comprehensive Analysis

**文檔版本**: 1.0  
**分析日期**: 2025-11-30  
**範圍**: Frontend → Backend → Sandbox 完整數據流追蹤與架構分析

---

## 目錄

1. [執行概述](#執行概述)
2. [完整數據流追蹤](#完整數據流追蹤)
   - [2.1 Frontend → Backend 流程](#21-frontend--backend-流程)
   - [2.2 Backend → Sandbox 流程](#22-backend--sandbox-流程)
   - [2.3 Sandbox 內部執行流程](#23-sandbox-內部執行流程)
3. [提交模式與執行模式組合分析](#提交模式與執行模式組合分析)
   - [3.1 Interactive + CODE](#31-interactive--code)
   - [3.2 Interactive + ZIP](#32-interactive--zip)
   - [3.3 FunctionOnly + ZIP](#33-functiononly--zip)
   - [3.4 General + CODE/ZIP](#34-general--codezip)
4. [路徑處理問題分析](#路徑處理問題分析)
   - [4.1 PathTranslator 機制](#41-pathtranslator-機制)
   - [4.2 Interactive Mode 路徑映射](#42-interactive-mode-路徑映射)
   - [4.3 已知路徑問題](#43-已知路徑問題)
5. [安全性分析](#安全性分析)
   - [5.1 權限隔離機制](#51-權限隔離機制)
   - [5.2 Seccomp 沙盒保護](#52-seccomp-沙盒保護)
   - [5.3 資源限制](#53-資源限制)
   - [5.4 安全風險點](#54-安全風險點)
6. [架構問題與改進建議](#架構問題與改進建議)
   - [6.1 現存問題](#61-現存問題)
   - [6.2 改進建議](#62-改進建議)

---

## 1. 執行概述

Interactive 模式是 Normal-OJ 的三種執行模式之一（general / functionOnly / **interactive**），支援**雙程式互動式判題**：

- **學生程式**: 學生提交的解題程式碼
- **教師程式**: 教師上傳的判題程式 (`Teacher_file`)
- **通訊機制**: 透過 FIFO 或 `/dev/fd` 管道即時通訊
- **判題邏輯**: 教師程式產生 `Check_Result` 決定最終結果 (AC/WA)

---

## 2. 完整數據流追蹤

### 2.1 Frontend → Backend 流程

> **注意**: Frontend 代碼未在當前 workspace 中，以下為基於 Backend API 的推斷

#### 題目創建/編輯階段

**API Endpoint**: `POST /problem/{problem_id}/assets`

**請求參數**:
```json
{
  "files_data": {
    "Teacher_file": <BinaryFile>,  // .c / .cpp / .py
    "case": <TestCaseZip>,
    "checker.py": <CheckerFile>,
    "makefile.zip": <MakefileZip>,
    "score.py": <ScoringScript>
  },
  "meta": {
    "pipeline": {
      "executionMode": "interactive",
      "teacherFirst": false,
      "customChecker": false
    },
    "config": {
      "acceptedFormat": "code",  // or "zip"
      "assetPaths": {
        "teacherLang": "cpp"  // or "c", "py" (自動從檔名推斷)
      }
    }
  }
}
```

**Backend處理流程**:

[`problem.py#L215-L299`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Back-End/mongo/problem/problem.py#L215-L299)

```python
def update_assets(self, user, files_data, meta):
    # 1. Teacher_file 處理
    if files_data.get('Teacher_file'):
        file_obj = files_data['Teacher_file']
        stored_name = Path(file_obj.filename).name  # 保留原始檔名與副檔名
        path = self._save_asset_file(minio_client, file_obj, 
                                     'teacher_file', stored_name)
        
        # 2. 自動推斷 teacherLang
        ext = Path(file_obj.filename).suffix.lower().lstrip('.')
        ext_map = {'c': 'c', 'cpp': 'cpp', 'py': 'py'}
        if ext in ext_map:
            inferred_teacher_lang = ext_map[ext]
            current_config['assetPaths']['teacherLang'] = inferred_teacher_lang
    
    # 3. 驗證 Interactive 必要資產
    if execution_mode == 'interactive' and 'teacher_file' not in asset_paths:
        raise ValueError('interactive mode requires Teacher_file')
```

**MinIO 儲存路徑**: `problem/{problem_id}/teacher_file/{filename}`

**Metadata 儲存** (MongoDB):
```json
{
  "config": {
    "executionMode": "interactive",
    "teacherFirst": false,
    "acceptedFormat": "code",
    "assetPaths": {
      "teacher_file": "problem/123/teacher_file/judge.cpp",
      "teacherLang": "cpp"
    }
  }
}
```

#### 代碼提交階段

**API End點**: `POST /submission`

**請求數據**:
```json
{
  "problemId": 123,
  "languageType": 1,  // 0=C, 1=C++, 2=Python
  "code": "...",  // CODE 模式
  "code.zip": <BinaryFile>  // ZIP 模式
}
```

**Backend 處理**:

[`dispatcher.py#L193-L296`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/dispatcher.py#L193-L296)

1. 建立 submission 資料夾: `submissions/{submission_id}/`
2. 解壓學生 code 到 `src/` 子目錄
3. 構建 Meta 物件:
   ```python
   meta = Meta(
       language=Language(language_type),
       submissionMode=SubmissionMode.CODE or SubmissionMode.ZIP,
       executionMode=ExecutionMode.INTERACTIVE,
       buildStrategy=BuildStrategy.MAKE_INTERACTIVE,
       assetPaths=problem_config['assetPaths'],
       teacherFirst=problem_config.get('teacherFirst', False),
       tasks=tasks
   )
   ```
4. 發送到 Dispatcher 佇列

---

### 2.2 Backend → Sandbox 流程

#### Dispatcher 準備階段

[`dispatcher.py#L160-L191`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/dispatcher.py#L160-L191)

**BuildStrategy 選擇**:

```python
def _prepare_with_build_strategy(self, submission_id, problem_id, meta, submission_path):
    if meta.buildStrategy == BuildStrategy.MAKE_INTERACTIVE:
        # Interactive 模式特殊處理
        plan = prepare_make_interactive(
            problem_id=problem_id,
            meta=meta,
            submission_dir=submission_path,
        )
```

**Teacher_file 準備**:

[`build_strategy.py#L230-L296`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/build_strategy.py#L230-L296)

```python
def _prepare_teacher_artifacts(problem_id, meta, submission_dir):
    # 1. 從 assetPaths 取得 teacherLang
    teacher_lang_val = meta.assetPaths.get("teacherLang")
    teacher_lang_map = {"c": Language.C, "cpp": Language.CPP, "py": Language.PY}
    teacher_lang = teacher_lang_map.get(teacher_lang_val.lower())
    
    # 2. 從 MinIO 下載 teacher_file
    data = fetch_problem_asset(problem_id, "teacher_file")
    
    # 3. 寫入 teacher/main.{c,cpp,py}
    teacher_dir = submission_dir / "teacher"
    teacher_dir.mkdir(parents=True, exist_ok=True)
    ext = {Language.C: ".c", Language.CPP: ".cpp", Language.PY: ".py"}[teacher_lang]
    src_path = teacher_dir / f"main{ext}"
    src_path.write_bytes(data)
    
    # 4. C/C++ 編譯教師程式
    if teacher_lang != Language.PY:
        compile_res = SubmissionRunner.compile_at_path(
            src_dir=str(teacher_dir.resolve()),
            lang=_lang_key(teacher_lang),
        )
        if compile_res.get("Status") != "AC":
            raise BuildStrategyError(f"teacher compile failed")
        
        # 產生 Teacher_main 二進位檔
        # 建立 main 符號連結供 sandbox_interactive 使用
```

**學生程式準備**:

[`build_strategy.py#L65-L101`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/build_strategy.py#L65-L101)

```python
def prepare_make_interactive(problem_id, meta, submission_dir):
    # 1. 先準備 Teacher artifacts
    prepare_interactive_teacher_artifacts(...)
    
    # 2. 處理學生程式
    src_dir = submission_dir / "src"
    
    if meta.submissionMode == SubmissionMode.ZIP:
        if meta.language == Language.PY:
            # Python ZIP: 必須有 main.py
            if not (src_dir / "main.py").exists():
                raise BuildStrategyError("interactive zip requires main.py")
            return BuildPlan(needs_make=False)
        else:
            # C/C++ ZIP: 必須有 Makefile
            if not (src_dir / "Makefile").exists():
                raise BuildStrategyError("interactive zip requires Makefile")
            return BuildPlan(needs_make=True, ...)
    
    # CODE 模式: 直接編譯，不需 make
    return BuildPlan(needs_make=False)
```

**目錄結構**:
```
submissions/{submission_id}/
├── src/
│   ├── main.c/cpp/py  (CODE模式)
│   ├── Makefile       (ZIP模式,C/C++)
│   └── *.c/cpp/py     (ZIP模式其他檔案)
├── teacher/
│   ├── main.c/cpp/py  (原始碼)
│   ├── Teacher_main   (C/C++編譯後)
│   └── main           (符號連結)
└── testcase/
    ├── 1.in
    ├── 1.out
    └── ...
```

---

### 2.3 Sandbox 內部執行流程

#### InteractiveRunner 啟動

[`interactive_runner.py#L24-L131`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_runner.py#L24-L131)

```python
class InteractiveRunner:
    def run(self) -> dict:
        translator = PathTranslator()
        
        # 1. 路徑轉換
        submission_root = translator.working_dir / self.submission_id
        submission_root_host = translator.to_host(submission_root)
        teacher_dir_host = translator.to_host(submission_root / "teacher")
        student_dir_host = translator.to_host(submission_root / "src")
        testcase_dir_host = translator.to_host(submission_root / "testcase")
        
        # 2. Docker 容器配置
        binds = {
            str(student_dir_host): {"bind": "/src", "mode": "rw"},
            str(teacher_dir_host): {"bind": "/teacher", "mode": "rw"},
            str(testcase_dir_host): {"bind": "/workspace/testcase", "mode": "ro"},
            str(host_root): {"bind": "/app", "mode": "ro"},
        }
        
        # 3. 啟動 orchestrator
        command = [
            "python3", "/app/runner/interactive_orchestrator.py",
            "--workdir", "/workspace",
            "--teacher-dir", "/teacher",
            "--student-dir", "/src",
            "--student-lang", self.lang_key,  # "c11" / "cpp17" / "python3"
            "--teacher-lang", self.teacher_lang_key,
            "--time-limit", str(self.time_limit),
            "--mem-limit", str(self.mem_limit),
            "--pipe-mode", self.pipe_mode,  # "auto" / "fifo" / "devfd"
        ]
        if self.teacher_first:
            command.append("--teacher-first")
        if case_path_container:
            command += ["--case-path", case_path_container]
        
        # 4. 啟動容器並等待結果
        container = client.create_container(...)
        client.start(container)
        exit_status = client.wait(container)
        logs = client.logs(container).decode("utf-8")
```

#### Orchestrator 執行邏輯

[`interactive_orchestrator.py#L245-L579`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L245-L579)

**Phase 1: 權限設定**

```python
def _setup_secure_permissions(teacher_dir, student_dir, 
                              teacher_uid=1450, student_uid=1451,
                              sandbox_gid=1450, ...):
    # Teacher 目錄: 僅 teacher UID 可讀寫執行
    for root, dirs, files in os.walk(teacher_dir):
        os.chown(root, teacher_uid, sandbox_gid)
        os.chmod(root, 0o701)
        for f in files:
            fp = os.path.join(root, f)
            os.chown(fp, teacher_uid, sandbox_gid)
            mode = 0o700 if os.access(fp, os.X_OK) else 0o600
            os.chmod(fp, mode)
    
    # Student 目錄: student UID 擁有，但預設權限受限
    for root, dirs, files in os.walk(student_dir):
        os.chown(root, student_uid, sandbox_gid)
        os.chmod(root, 0o751)
        for f in files:
            fp = os.path.join(root, f)
            os.chown(fp, student_uid, sandbox_gid)
            mode = 0o555 if os.access(fp, os.X_OK) else 0o444  # 預設唯讀
            os.chmod(fp, mode)
```

**Phase 2: 管道建立**

```python
def _setup_pipes(tmpdir, mode):
    if mode == "devfd":
        # /dev/fd 模式 (Fallback)
        s2t_r, s2t_w = os.pipe()  # student → teacher
        t2s_r, t2s_w = os.pipe()  # teacher → student
        os.set_inheritable(s2t_r, True)
        os.set_inheritable(s2t_w, True)
        os.set_inheritable(t2s_r, True)
        os.set_inheritable(t2s_w, True)
        return {
            "mode": "devfd",
            "student": {
                "stdin": f"/dev/fd/{t2s_r}",
                "stdout": f"/dev/fd/{s2t_w}",
            },
            "teacher": {
                "stdin": f"/dev/fd/{s2t_r}",
                "stdout": f"/dev/fd/{t2s_w}",
            },
            "keep_fds": [s2t_r, s2t_w, t2s_r, t2s_w],
        }
    
    # FIFO 模式 (優先)
    s2t = tmpdir / "s2t.fifo"
    t2s = tmpdir / "t2s.fifo"
    os.mkfifo(s2t)
    os.mkfifo(t2s)
    # holder fds 防止 FIFO 在 open() 時阻塞
    holder = [
        os.open(s2t, os.O_RDWR | os.O_NONBLOCK),
        os.open(t2s, os.O_RDWR | os.O_NONBLOCK),
    ]
    return {
        "mode": "fifo",
        "student": {"stdin": str(t2s), "stdout": str(s2t)},
        "teacher": {"stdin": str(s2t), "stdout": str(t2s)},
        "holder": holder,
    }
```

**Phase 3: 啟動雙程序**

```python
# sandbox_interactive 命令格式:
# [lang_id, allow_net, stdin, stdout, stderr, time_ms, mem_kb, 
#  allow_write, output_limit, proc_limit, result_file]

student_cmd = [
    "sandbox_interactive",
    str(LANG_IDS[student_lang]),  # 0=C, 1=C++, 2=Python
    "0",  # allow_net
    pipe_bundle["student"]["stdin"],
    pipe_bundle["student"]["stdout"],
    str(tmpdir / "student.err"),
    str(time_limit),  # 毫秒
    str(mem_limit),   # KB
    "1",  # allow_write flag (實際由 env 控制)
    str(64 * 1024 * 1024),  # output_limit
    "10",  # proc_limit
    str(tmpdir / "student.result"),
]

# 環境變數控制實際權限
env_student["PWD"] = str(student_dir)
env_student["SANDBOX_UID"] = str(1451)
env_student["SANDBOX_GID"] = str(1450)
env_student.pop("SANDBOX_ALLOW_WRITE", None)  # 禁止寫檔

env_teacher["PWD"] = str(teacher_dir)
env_teacher["SANDBOX_UID"] = str(1450)
env_teacher["SANDBOX_ALLOW_WRITE"] = "1"  # 允許寫檔

# 啟動順序
if teacher_first:
    start_teacher()
    time.sleep(0.05)
    start_student()
else:
    start_student()
    time.sleep(0.05)
    start_teacher()
```

**Phase 4: 結果判定**

```python
# 優先順序:
# 1. 學生錯誤 (CE/RE/TLE/MLE/OLE)
# 2. 教師錯誤 (CE/RE/TLE/MLE)
# 3. Check_Result 無效 → CE
# 4. Check_Result 有效 → AC/WA

if student_status != "AC":
    final_status = student_status
elif teacher_status != "AC":
    final_status = teacher_status
else:
    check_status, msg = _parse_check_result(teacher_dir / "Check_Result")
    if check_status is None:
        final_status = "CE"  # Check_Result 不存在或格式錯誤
    else:
        final_status = check_status  # "AC" or "WA"

# 額外檢查: 教師新增檔案數量
teacher_new_files = _dir_file_count(teacher_dir) - teacher_files_before
if final_status == "AC" and teacher_new_files > 500:
    final_status = "CE"
    message = f"teacher created too many files ({teacher_new_files})"
```

**返回結果**:
```python
{
    "Status": "AC",  # or WA/CE/RE/TLE/MLE/OLE
    "Stdout": "",
    "Stderr": "All test cases passed",  # Check_Result MESSAGE
    "Duration": 123,  # 毫秒
    "MemUsage": 2048,  # KB
    "DockerExitCode": 0,
    "pipeMode": "fifo",  # or "devfd"
    "teacherStderr": "",
    "studentStderr": "",
    "studentResult": "...",  # sandbox_interactive 原始輸出
    "teacherResult": "...",
}
```

---

## 3. 提交模式與執行模式組合分析

### 3.1 Interactive + CODE

**適用場景**: 單檔互動題目（如猜數字、簡單對話）

**學生提交**: `main.c` / `main.cpp` / `main.py`

**處理流程**:
1. Backend 將 code 寫入 `src/main.{c,cpp,py}`
2. Sandbox 下載 Teacher_file 到 `teacher/main.{c,cpp,py}`
3. C/C++ 編譯 teacher → `teacher/Teacher_main` + `teacher/main`
4. C/C++ 編譯 student → `src/a.out` → `src/main`
5. Python 直接使用 `main.py`

**BuildPlan**:
- `needs_make`: `False` (直接編譯，不走 Makefile)
- `lang_key`: 學生語言（"c11" / "cpp17" / "python3"）

**限制**:
- ✅ 適合簡單單檔題目
- ❌ 不支援多檔案學生程式
- ❌ 不支援自訂編譯選項

---

### 3.2 Interactive + ZIP

**適用場景**: 複雜互動題目（多檔案、特殊編譯需求）

**學生提交**: `code.zip` 包含:
- C/C++: **必須** 有 `Makefile`，產生 `a.out`
- Python: **必須** 有 `main.py`

**處理流程**:
1. Backend 解壓 ZIP 到 `src/`
2. 驗證:
   - Python: 檢查 `main.py` 存在
   - C/C++: 檢查 `Makefile` 存在
3. C/C++ 執行 `make` 產生 `a.out` → 重命名為 `main`
4. 確保 `src/` 只有一個可執行檔 `a.out`

**BuildPlan**:
- `needs_make`: 
  - Python: `False`
  - C/C++: `True`
- `finalize`: `_finalize_compiled_binary`

**嚴格檢查**:
```python
# build_strategy.py#L218-L227
def _ensure_single_executable(src_dir, allowed={"a.out"}):
    exec_files = [item for item in src_dir.iterdir() 
                  if item.is_file() and os.access(item, os.X_OK)]
    extras = [item for item in exec_files if item.name not in allowed]
    if extras:
        raise BuildStrategyError(
            "only one executable named a.out is allowed in zip submissions"
        )
```

**限制**:
- ✅ 支援多檔案與自訂編譯
- ❌ **Makefile 必須存在** (C/C++)
- ❌ **不允許額外可執行檔** (防止 precompiled binaries)

---

### 3.3 FunctionOnly + ZIP

**適用場景**: 函數實作題（學生提供函數，系統提供測試框架）

**學生提交**: 
- C/C++: 實作 `function.h` 中宣告的函數
- Python: 實作 `student_impl.py` 中的函數

**處理流程**:
1. 讀取學生 code: `src/main.{c,cpp,py}`
2. 從 MinIO 下載 `makefile.zip` (包含完整測試框架)
3. 清空 `src/` 並解壓 `makefile.zip`
4. 將學生 code 寫入:
   - C/C++: `src/function.h`
   - Python: `src/student_impl.py`
5. 執行 `make` 產生 `a.out` → `main`

**BuildPlan**:
- `needs_make`: `True`
- `finalize`: `_finalize_function_only_artifacts`

**限制**:
- ✅ 適合函數實作題
- ❌ **必須** 上傳 `makefile.zip`
- ❌ 學生無法修改測試框架
- ❌ 不支援 Interactive 模式 (因為沒有 Teacher_file 概念)

---

### 3.4 General + CODE/ZIP

**適用場景**: 標準 I/O 題目

**與 Interactive 差異**:
- ❌ 無 Teacher_file
- ✅ 使用標準輸入/輸出
- ✅ 答案檢查由 Checker 或字串比對完成

**BuildStrategy**:
- CODE: `BuildStrategy.COMPILE`
- ZIP: `BuildStrategy.MAKE_NORMAL`

---

## 4. 路徑處理問題分析

### 4.1 PathTranslator 機制

[`path_utils.py`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/path_utils.py)

**目的**: 解決 WSL / Remote Docker 環境下的路徑映射問題

**配置範例**:
```json
{
  "path_mode": "wsl",
  "working_dir": "/home/user/sandbox/submissions",
  "host_root": "/mnt/wsl/sandbox",
  "wsl_distro": "Ubuntu-20.04"
}
```

**路徑轉換**:
```python
class PathTranslator:
    def to_host(self, container_path: Path) -> Path:
        if self.path_mode == "wsl":
            # /home/user/submissions/123 
            # → \\wsl$\Ubuntu-20.04\home\user\submissions\123
            relative = container_path.relative_to(self.working_dir)
            return self.host_root / relative
        return container_path
```

---

### 4.2 Interactive Mode 路徑映射

**容器內路徑** (orchestrator 視角):
```
/workspace/
├── teacher/         ← 從宿主機 bind mount
│   ├── main.c/cpp/py
│   ├── Teacher_main
│   └── Check_Result (輸出)
├── src/             ← 從宿主機 bind mount
│   ├── main.c/cpp/py
│   └── main (or a.out)
└── testcase/        ← 從宿主機 bind mount (ro)
    └── 1.in
```

**宿主機路徑** (InteractiveRunner 視角):

*Local Docker*:
```
/home/user/sandbox/submissions/abc123/
├── teacher/
├── src/
└── testcase/
```

*WSL Docker*:
```
\\wsl$\Ubuntu-20.04\home\user\sandbox\submissions\abc123\
├── teacher/
├── src/
└── testcase/
```

**Docker Bind Mount 配置**:
```python
binds = {
    str(student_dir_host): {"bind": "/src", "mode": "rw"},
    str(teacher_dir_host): {"bind": "/teacher", "mode": "rw"},
    str(testcase_dir_host): {"bind": "/workspace/testcase", "mode": "ro"},
}
```

---

### 4.3 已知路徑問題

#### 問題 1: Student cwd 不一致

**代碼位置**: [`interactive_orchestrator.py#L417`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L417)

```python
def start_student():
    procs["student"] = subprocess.Popen(
        commands["student"],
        cwd=Path("/src"),  # ← 硬編碼
        env=env_student,   # env["PWD"] = str(student_dir) ← 不一致
        pass_fds=keep_fds,
    )
```

**問題**: 
- `cwd` 設為 `/src` (容器內路徑)
- 但 `env["PWD"]` 設為 `student_dir` 變數值 (可能是其他路徑)

**影響**: 
- 部分程式依賴 `$PWD` 環境變數可能出錯
- 建議統一使用 `/src`

**修復建議**:
```python
env_student["PWD"] = "/src"  # 與 cwd 一致
```

#### 問題 2: testcase.in 清理邏輯不完善

**代碼位置**: [`interactive_orchestrator.py#L504-L511`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L504-L511)

```python
if case_local and case_local.exists():
    try:
        case_local.unlink()
    except Exception:
        try:
            os.chmod(case_local, 0o600)  # 僅修改權限但不刪除
        except Exception:
            pass
```

**問題**: 刪除失敗時僅修改權限，但不重試刪除或記錄日誌

**修復建議**:
```python
if case_local and case_local.exists():
    try:
        case_local.unlink()
    except Exception:
        try:
            os.chown(case_local, os.getuid(), os.getgid())  # 改變擁有者
            case_local.unlink()
        except Exception as exc:
            logger.warning("failed to remove testcase.in: %s", exc)
```

#### 問題 3: FIFO 權限可能導致學生端無法開啟

**代碼位置**: [`interactive_orchestrator.py#L266-L268`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/runner/interactive_orchestrator.py#L266-L268)

```python
# FIFO 需要學生端開啟寫入 FIFO，若禁用寫入則改用 devfd
if args.pipe_mode == "fifo" and not student_allow_write:
    args.pipe_mode = "devfd"
```

**說明**: 
- FIFO 需要雙方都能 `open()` 才能建立連接
- 若學生 seccomp 禁止 `open(O_WRONLY)`，會卡死
- 因此自動 fallback 到 `/dev/fd` 模式

**現狀**: ✅ 已有自動偵測與切換機制

---

## 5. 安全性分析

### 5.1 權限隔離機制

#### UID/GID 設計

**配置** (`.config/interactive.json`):
```json
{
  "teacherUid": 1450,
  "studentUid": 1451,
  "sandboxGid": 1450
}
```

**隔離策略**:

| 角色 | UID | GID | 可讀取 | 可寫入 |
|------|-----|-----|--------|--------|
| Teacher | 1450 | 1450 | teacher/, tmpdir/ | teacher/, tmpdir/ |
| Student | 1451 | 1450 | src/, (部分 teacher/) | **無** (seccomp阻止) |

**Teacher 目錄權限**:
```bash
drwx-----x  1450:1450  teacher/         # 0o701 (student 可進入但不可列舉)
-rw-------  1450:1450  teacher/main.c   # 0o600 (student 不可讀)
-rwx------  1450:1450  teacher/main     # 0o700 (student 不可執行)
```

**Student 目錄權限**:
```bash
drwxr-x--x  1451:1450  src/             # 0o751
-r--r-----  1451:1450  src/main.c       # 0o444 (唯讀)
-r-xr-x--x  1451:1450  src/main         # 0o555 (可執行唯讀)
```

**安全保證**:
- ✅ Student 無法讀取 Teacher 程式碼 (不同 UID)
- ✅ Student 無法修改自己的程式碼 (檔案權限 0o444)
- ✅ Teacher 可寫入判題結果 (`Check_Result`)

---

### 5.2 Seccomp 沙盒保護

**機制**: `sandbox_interactive` 使用 seccomp-bpf 限制系統呼叫

**Student 限制** (預設):
```c
// SANDBOX_ALLOW_WRITE 未設定時
blocked_syscalls = {
    open(O_WRONLY),   // 禁止寫入開檔
    open(O_RDWR),     // 禁止讀寫開檔
    creat,            // 禁止建立檔案
    write,            // 禁止寫入 (除 stdout/stderr)
    unlink,           // 禁止刪除檔案
    mkdir,            // 禁止建立目錄
    rmdir,            // 禁止刪除目錄
    // ... 等危險呼叫
}
```

**Teacher 限制** (SANDBOX_ALLOW_WRITE=1):
```c
允許:
  - open(O_WRONLY), creat, write
  - 建立 Check_Result 檔案
限制:
  - 網路呼叫 (socket, connect)
  - 特權呼叫 (setuid, setgid)
```

**測試驗證**:

[`test_interactive.py`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/tests/test_interactive.py)

- ✅ 學生寫檔被 seccomp 阻擋 (C/Python)
- ✅ 教師可寫檔

---

### 5.3 資源限制

#### 時間限制

**設定層級**:
1. **RLIMIT_CPU**: `sandbox_interactive` 設定 CPU 秒數上限
2. **Watchdog**: orchestrator 監控，時限 + 2 秒緩衝
3. **超時處理**: kill 雙方程序

```python
# orchestrator.py#L404
deadline = start_time + (args.time_limit / 1000.0) + 2.0

while time.time() < deadline:
    all_done = all(proc.poll() is not None for proc in procs.values())
    if all_done:
        break
    time.sleep(0.05)

# 超時則 kill
for proc in procs.values():
    if proc.poll() is None:
        proc.kill()
```

#### 記憶體限制

**設定**: `RLIMIT_AS` (Address Space)

**獨立計算**: 學生與教師各自限制，回傳 `max(teacher_mem, student_mem)`

**Docker 層級**: `mem_limit` 參數額外保護

#### 輸出限制

**預設**: 64 MB (`outputLimitBytes`)

**觸發**: 超過則 sandbox_interactive 回傳 `OLE` (Output Limit Exceeded)

#### 檔案限制

**單檔大小**: `RLIMIT_FSIZE`

**Teacher 新增檔案數**: 預設 500 個
```python
teacher_new_files = _dir_file_count(teacher_dir) - teacher_files_before
if final_status == "AC" and teacher_new_files > 500:
    final_status = "CE"
```

---

### 5.4 安全風險點

#### ⚠️ 風險 1: Teacher_file 注入攻擊

**場景**: 惡意教師上傳含惡意程式碼的 `Teacher_file`

**現有防護**:
- ✅ Teacher UID 隔離，學生無法讀取
- ✅ 網路限制 (network_mode="none")
- ✅ Docker 容器隔離

**殘留風險**:
- ❌ Teacher 程式仍可讀取測資檔案 (`testcase.in`)
- ❌ Teacher 可能透過 `Check_Result` 洩露測資內容

**建議**:
1. 限制 Teacher 輸出長度 (例如 MESSAGE 最多 1KB)
2. 驗證 `Check_Result` 格式，防止資訊洩露

#### ⚠️ 風險 2: Symlink 攻擊

**場景**: 學生 ZIP 包含符號連結，指向系統敏感檔案

**現有防護**:
- ✅ Docker 容器隔離，僅 bind mount 特定目錄
- ✅ 檔案權限限制

**殘留風險**:
- ZIP 解壓未檢查 symlink
- 可能指向 `/teacher/` 目錄

**建議**:
```python
# 解壓時檢查
import zipfile
with zipfile.ZipFile(zip_file) as zf:
    for info in zf.infolist():
        if info.is_symlink():  # Python 3.13+
            raise BuildStrategyError("symlinks not allowed in zip")
        zf.extract(info, src_dir)
```

#### ⚠️ 風險 3: 時序攻擊 (Race Condition)

**場景**: 學生程式在檢查時與執行時行為不同

**範例**:
```c
// 學生程式在靜態分析時正常
// 但執行時透過時序差異突破限制
```

**現有防護**:
- ✅ Seccomp 執行期保護
- ✅ 檔案權限唯讀

**殘留風險**:
- 靜態分析與實際執行環境可能不一致

**建議**: 無需額外處置，現有機制已足夠

#### ✅ 已修復: Seccomp Unconfined

**舊版問題**: [`INTERACTIVE_CODE_REVIEW.md#4`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Docs%20and%20Ref/Interactive/INTERACTIVE_CODE_REVIEW.md#L20)

```python
# 舊版 (危險)
host_config = {
    "security_opt": ["seccomp=unconfined"]  # 完全關閉 seccomp
}
```

**現狀**: ✅ 已移除，使用 `sandbox_interactive` 內建 seccomp

---

## 6. 架構問題與改進建議

### 6.1 現存問題

#### 問題 1: 教師語言推斷邏輯分散

**位置**:
- Backend: [`problem.py#L261-L270`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Back-End/mongo/problem/problem.py#L261-L270)
- Sandbox: [`build_strategy.py#L232-L244`](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/dispatcher/build_strategy.py#L232-L244)

**問題**: 
- Backend 從檔名推斷，存入 `assetPaths.teacherLang`
- Sandbox 也有 fallback 邏輯，從檔名再次推斷
- 邏輯重複，維護成本高

**建議**: 
- Backend 上傳時**強制**要求明確指定 `teacherLang`
- Sandbox 移除 fallback，直接讀取 `assetPaths.teacherLang`

#### 問題 2: BuildStrategy 與 ExecutionMode 耦合

**現狀**:
```python
class BuildStrategy(IntEnum):
    COMPILE = 1           # general + CODE
    MAKE_NORMAL = 2       # general + ZIP
    MAKE_INTERACTIVE = 3  # interactive + CODE/ZIP
```

**問題**:
- `ExecutionMode` (general/interactive/functionOnly) 與 `SubmissionMode` (CODE/ZIP) 決定 `BuildStrategy`
- 三者耦合，新增模式需同步修改

**建議**:
- 改為組合模式: `(ExecutionMode, SubmissionMode) → BuildHandler`
- 移除 `BuildStrategy` enum

```python
def get_build_handler(execution_mode, submission_mode):
    if execution_mode == ExecutionMode.INTERACTIVE:
        if submission_mode == SubmissionMode.ZIP:
            return InteractiveZipHandler()
        return InteractiveCodeHandler()
    elif execution_mode == ExecutionMode.FUNCTION_ONLY:
        return FunctionOnlyHandler()
    # ...
```

#### 問題 3: Meta 欄位命名不一致

**範例**:
- `assetPaths` (Backend 駝峰命名)
- `teacher_first` (Sandbox 蛇形命名)
- `teacherLang` (混合命名)

**影響**: 可讀性差，容易出錯

**建議**: 統一使用 snake_case (Python 慣例)

#### 問題 4: Interactive 錯誤回報不明確

**場景**: Teacher compile 失敗

**現狀回報**:
```
CE: teacher compile failed: /tmp/xyz: undefined reference to foo
```

**問題**: 
- 學生看不懂編譯錯誤訊息
- 應區分「學生錯誤」與「系統錯誤」

**建議**:
```python
if compile_res.get("Status") != "AC":
    # 記錄完整錯誤到 logs
    logger.error(f"Teacher compile failed: {err_msg}")
    # 回傳簡化訊息
    raise BuildStrategyError(
        "Interactive mode judge program failed to compile. "
        "Please contact course staff."
    )
```

#### 問題 5: Orchestrator 函數過大

**現狀**: `orchestrate()` 函數 300+ 行

**問題**: 
- 可讀性差
- 難以測試
- 修改風險高

**建議**: 拆分為:
```python
def orchestrate(args):
    config = load_config()
    paths = setup_paths(args, config)
    permissions = setup_permissions(paths, config)
    pipes = setup_pipes(paths, args.pipe_mode)
    testcase = inject_testcase(paths, args.case_path)
    procs = launch_processes(paths, pipes, args)
    results = wait_and_collect(procs, paths, config)
    return finalize_result(results, pipes, testcase)
```

---

### 6.2 改進建議

#### 建議 1: 統一路徑處理

**現狀**: PathTranslator 已重構，但 orchestrator 內仍有硬編碼路徑

**建議**: 
- Orchestrator 接收相對路徑配置
- 由 Runner 統一處理路徑轉換

```python
# InteractiveRunner 負責路徑
paths = PathConfig(
    student_dir="/src",
    teacher_dir="/teacher",
    testcase_dir="/workspace/testcase",
    tmpdir="/workspace/.tmp",
)

# Orchestrator 使用配置
def orchestrate(args, paths: PathConfig):
    student_dir = Path(paths.student_dir)
    teacher_dir = Path(paths.teacher_dir)
    # ...
```

#### 建議 2: 加強 Check_Result 驗證

**現狀**: 僅檢查 `STATUS: AC/WA`

**建議**: 
- 限制 MESSAGE 長度 (防止資訊洩露)
- 支援分數制 (partial credit)

```python
def _parse_check_result(path: Path):
    # ...
    if status not in ("AC", "WA", "PC"):  # Partial Credit
        return None, "Invalid STATUS"
    
    # 限制 MESSAGE 長度
    if len(message) > 1024:
        message = message[:1024] + "...(truncated)"
    
    # 支援 SCORE (0-100)
    score = 0
    for line in path.read_text().splitlines():
        if line.startswith("SCORE:"):
            score = int(line.split(":", 1)[1].strip())
    
    return status, message, score
```

#### 建議 3: 增加監控與日誌

**現狀**: 部分失敗僅回傳 CE，無詳細日誌

**建議**: 
- 所有 BuildStrategyError 記錄到 structured logs
- 加入 submission_id, problem_id 追蹤

```python
logger.error(
    "interactive teacher compile failed",
    extra={
        "submission_id": submission_id,
        "problem_id": problem_id,
        "teacher_lang": teacher_lang,
        "error": compile_res.get("Stderr"),
    }
)
```

#### 建議 4: 支援 Teacher_file 預編譯快取

**現狀**: 每次提交都重新下載並編譯 Teacher_file

**建議**: 
- 根據 `teacher_file` MinIO 路徑 + 版本號快取編譯結果
- 僅當 Teacher_file 更新時重新編譯

```python
cache_key = f"{problem_id}_{teacher_file_hash}"
cached_binary = redis.get(f"teacher_binary:{cache_key}")
if cached_binary:
    (teacher_dir / "Teacher_main").write_bytes(cached_binary)
else:
    compile_and_cache(...)
```

#### 建議 5: 測試覆蓋率提升

**現狀**: `test_interactive.py` 已有基本測試

**建議**: 新增:
- ✅ 多測資執行 (目前僅單測資)
- ✅ Teacher first vs Student first 同一題目測試
- ✅ 不同語言組合 (C student + Python teacher)
- ✅ 錯誤注入測試 (故意觸發 TLE/MLE/OLE)
- ✅ Symlink 攻擊測試
- ✅ Teacher MESSAGE 超長測試

---

## 總結

### 優點

1. ✅ **安全隔離健全**: UID/GID + Seccomp + Docker 三層防護
2. ✅ **錯誤處理完善**: Fail Fast + Logging 策略
3. ✅ **管道通訊穩定**: FIFO + devfd fallback 機制
4. ✅ **資源限制嚴格**: 時間/記憶體/輸出/檔案數多重限制
5. ✅ **測試覆蓋充足**: 涵蓋多數關鍵場景

### 待改進

1. ⚠️ **路徑硬編碼**: `cwd=/src` 與 `PWD` 不一致
2. ⚠️ **教師語言推斷**: Backend 與 Sandbox 邏輯重複
3. ⚠️ **BuildStrategy 耦合**: ExecutionMode/SubmissionMode/BuildStrategy 三者綁定
4. ⚠️ **錯誤訊息不明確**: Teacher 編譯失敗回報給學生
5. ⚠️ **Orchestrator 過大**: 300+ 行函數難以維護

### 安全風險

1. 🔒 **低風險**: Teacher_file 惡意程式碼 (已有網路隔離與容器保護)
2. 🔒 **低風險**: Symlink 攻擊 (建議加驗證)
3. 🔒 **中風險**: Check_Result 資訊洩露 (建議限制 MESSAGE 長度)

### 下一步行動建議

**優先級高**:
1. 修復 Student cwd 不一致問題
2. 改進 testcase.in 清理邏輯
3. 限制 Check_Result MESSAGE 長度

**優先級中**:
4. 重構 BuildStrategy 為組合模式
5. 統一命名規範 (snake_case)
6. 拆分 orchestrator 函數

**優先級低**:
7. 加入 Teacher_file 編譯快取
8. 提升測試覆蓋率
9. 增強監控與日誌

---

**文檔維護**: 請在架構變更時同步更新此文檔
