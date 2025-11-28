# Interactive 模式正確權限控制方案

## 📋 目標與原則

### 安全目標
1. ✅ **教師可讀寫** teacher 目錄（包括寫入 Check_Result）
2. ✅ **教師可讀取** 測資檔案（testcase.in）
3. ❌ **學生無法讀取** teacher 目錄（包括教師源碼、測資、Check_Result）
4. ⚙️ **學生權限**（預設完全禁止，可透過配置接口啟用）
   - **讀取**: 預設禁止，可配置啟用
   - **寫入**: 預設禁止（由 Seccomp 保證），可配置啟用
5. ✅ **教師可讀** 學生的 src 目錄（不可寫）

### 設計原則
- **最小權限原則**: 每個進程只獲得必要的權限
- **深度防禦**: 多層保護（UID 隔離 + Seccomp + 權限設置）
- **明確所有權**: 每個目錄和檔案都有明確的 owner
- **簡化清理**: 使用統一的 GID 方便 host 端清理

---

## 🔧 UID/GID 配置

### 配置參數

| 參數 | 值 | 說明 |
|------|-----|------|
| **TEACHER_UID** | 1450 | 教師進程的用戶 ID |
| **STUDENT_UID** | 1451 | 學生進程的用戶 ID |
| **SANDBOX_GID** | 1450 | 統一的組 ID（方便清理） |
| **STUDENT_ALLOW_READ** | false | 學生是否可讀取 src 目錄（預留接口） |
| **STUDENT_ALLOW_WRITE** | false | 學生是否可寫入 src 目錄（預留接口） |

### 配置來源

```python
# interactive_orchestrator.py
cfg = load_config()  # 從 .config/interactive.json 讀取
teacher_uid = int(cfg.get("teacherUid", 1450))
student_uid = int(cfg.get("studentUid", 1451))
sandbox_gid = int(cfg.get("sandboxGid", 1450))
```

### 配置檔案 (.config/interactive.json)

```json
{
  "teacherUid": 1450,
  "studentUid": 1451,
  "sandboxGid": 1450,
  "studentAllowRead": false,
  "studentAllowWrite": false,
  "outputLimitBytes": 67108864,
  "maxTeacherNewFiles": 500
}
```

**配置說明**:
- `studentAllowRead`: 控制學生是否可以讀取自己的 src 目錄
  - `false` (預設): 禁止讀取，由權限控制
  - `true`: 允許讀取（大部分場景需要）
- `studentAllowWrite`: 控制學生是否可以寫入自己的 src 目錄
  - `false` (預設): 完全禁止寫入，由 Seccomp 強制執行
  - `true`: 允許寫入，需配合環境變數 `SANDBOX_ALLOW_WRITE` 傳遞

---

## 📊 權限矩陣

### 目錄權限

| 路徑 | Owner | Group | Mode | 八進制 | 教師(1450) | 學生(1451) |
|------|-------|-------|------|--------|-----------|-----------|
| `/workspace/teacher/` | 1450 | 1450 | `drwx------` | 700 | ✅ rwx | ❌ --- |
| `/workspace/src/` | 1451 | 1450 | `drwxr-xr-x` | 755 | ✅ r-x | ✅ rwx |

### 文件權限

| 文件 | Owner | Group | Mode | 八進制 | 教師(1450) | 學生(1451) |
|------|-------|-------|------|--------|-----------|-----------|
| `teacher/main.c` | 1450 | 1450 | `-rw-------` | 600 | ✅ rw- | ❌ --- |
| `teacher/Teacher_main` | 1450 | 1450 | `-rw-------` | 600 | ✅ rw- | ❌ --- |
| `teacher/testcase.in` | 1450 | 1450 | `-rw-------` | 600 | ✅ rw- | ❌ --- |
| `teacher/Check_Result` | 1450 | 1450 | `-rw-------` | 600 | ✅ rw- | ❌ --- |
| `src/main.c` | 1451 | 1450 | `-rw-r--r--` | 644 | ✅ r-- | ✅ rw- |
| `src/a.out` | 1451 | 1450 | `-rwxr-xr-x` | 755 | ✅ r-x | ✅ rwx |

### 權限說明

#### Teacher 目錄 (700)
```
drwx------
│││└─ Other: 無權限 (---)
││└── Group: 無權限 (---)
│└─── Owner: 讀寫執行 (rwx)
└──── 目錄標記 (d)
```

**效果**:
- **Owner (UID 1450)**: 可以讀取目錄（列出文件）、寫入（創建/刪除文件）、執行（cd 進入）
- **Student (UID 1451)**: 完全無法訪問（無法 `ls`、無法 `cd`、無法讀取文件）

#### Teacher 文件 (600)
```
-rw-------
│││└─ Other: 無權限 (---)
││└── Group: 無權限 (---)
│└─── Owner: 讀寫 (rw-)
└──── 普通文件標記 (-)
```

**效果**:
- **Owner (UID 1450)**: 可讀可寫
- **Student (UID 1451)**: 完全無法訪問

#### Student 目錄 (755)
```
drwxr-xr-x
│││└─ Other: 讀執行 (r-x)
││└── Group: 讀執行 (r-x)
│└─── Owner: 讀寫執行 (rwx)
└──── 目錄標記 (d)
```

**效果**:
- **Owner (UID 1451)**: 完全控制
- **Teacher (UID 1450)**: 可讀可執行（但不可寫）

---

## 🔨 實作步驟

### 步驟 1: 初始化時設置權限

**時機**: 在 `orchestrate()` 函數開始時，啟動子進程前

**代碼位置**: `interactive_orchestrator.py` L325-327

```python
def orchestrate(args: argparse.Namespace):
    # ... 前面的初始化代碼 ...
    
    # 讀取配置
    cfg = load_config()
    teacher_uid = int(cfg.get("teacherUid", 1450))
    student_uid = int(cfg.get("studentUid", 1451))
    sandbox_gid = int(cfg.get("sandboxGid", 1450))
    
    # ✅ 關鍵步驟：設置目錄權限
    _setup_secure_permissions(
        teacher_dir, 
        student_dir, 
        teacher_uid,
        student_uid, 
        sandbox_gid
    )
    
    # 之後的代碼...
```

### 步驟 2: 權限設置函數實現

```python
def _setup_secure_permissions(
    teacher_dir: Path,
    student_dir: Path,
    teacher_uid: int,
    student_uid: int,
    sandbox_gid: int
):
    """
    設置安全權限：
    - Teacher 目錄：700, owner=teacher_uid (學生無法訪問)
    - Student 目錄：755, owner=student_uid (教師可讀不可寫)
    """
    
    # ========== Teacher 目錄和文件 ==========
    try:
        # 遞迴處理所有目錄和文件
        for root, dirs, files in os.walk(teacher_dir):
            # 1. 設置目錄權限
            os.chown(root, teacher_uid, sandbox_gid)
            os.chmod(root, 0o700)  # drwx------
            
            # 2. 設置文件權限
            for filename in files:
                filepath = os.path.join(root, filename)
                try:
                    os.chown(filepath, teacher_uid, sandbox_gid)
                    os.chmod(filepath, 0o600)  # -rw-------
                except Exception as e:
                    # 個別文件失敗不影響整體
                    print(f"Warning: Failed to set permissions on {filepath}: {e}")
                    
    except Exception as e:
        # Teacher 權限設置失敗是嚴重問題，記錄但不中斷
        print(f"ERROR: Failed to secure teacher directory: {e}")
        # 可以選擇 raise 中斷執行，或繼續（降級安全性）
    
    # ========== Student 目錄和文件 ==========
    try:
        for root, dirs, files in os.walk(student_dir):
            # 1. 設置目錄權限
            os.chown(root, student_uid, sandbox_gid)
            os.chmod(root, 0o755)  # drwxr-xr-x
            
            # 2. 設置文件權限
            for filename in files:
                filepath = os.path.join(root, filename)
                try:
                    os.chown(filepath, student_uid, sandbox_gid)
                    # 可執行文件：755，普通文件：644
                    if os.access(filepath, os.X_OK):
                        os.chmod(filepath, 0o755)  # -rwxr-xr-x
                    else:
                        os.chmod(filepath, 0o644)  # -rw-r--r--
                except Exception as e:
                    print(f"Warning: Failed to set permissions on {filepath}: {e}")
                    
    except Exception as e:
        print(f"Warning: Failed to secure student directory: {e}")
```

### 步驟 3: 測資注入時設置權限

**時機**: 注入 `testcase.in` 時

**代碼位置**: `interactive_orchestrator.py` L409-424

**⚠️ 當前問題**: L418 權限設置為 `0o400`（只讀），應改為 `0o600`（可讀寫）

```python
# 注入測資
if args.case_path:
    env_teacher["CASE_PATH"] = args.case_path
    src_case = Path(args.case_path)
    
    if src_case.exists():
        case_local = teacher_dir / "testcase.in"
        
        try:
            # 1. 刪除舊文件（如果存在）
            if case_local.exists():
                case_local.unlink()
            
            # 2. 寫入測資內容
            case_local.write_bytes(src_case.read_bytes())
            
            # 3. ✅ 正確：設置為 600（owner 可讀寫）
            # ❌ 當前代碼為 0o400（只讀）- 需修復！
            os.chmod(case_local, 0o600)  # -rw------- (owner 可讀寫)
            os.chown(case_local, teacher_uid, sandbox_gid)
            
            print(f"Injected testcase: {case_local} (owner={teacher_uid}, mode=600)")
            
        except Exception as e:
            print(f"ERROR: Failed to inject testcase: {e}")
            case_local = None
```

### 步驟 4: 環境變數設置（含讀寫權限配置接口）

**代碼位置**: `interactive_orchestrator.py` L395-407

**當前實際代碼**:
```python
# L395-407 當前實際內容
env_student = os.environ.copy()
env_teacher = os.environ.copy()
env_student["PWD"] = str(student_dir)
env_teacher["PWD"] = str(teacher_dir)
env_student.pop("SANDBOX_ALLOW_WRITE", None)  # L401 禁止寫入
env_student["SANDBOX_UID"] = str(student_uid)
env_student["SANDBOX_GID"] = str(sandbox_gid)
env_teacher["SANDBOX_UID"] = str(teacher_uid)
env_teacher["SANDBOX_GID"] = str(sandbox_gid)
env_teacher["SANDBOX_ALLOW_WRITE"] = "1"  # L407 允許寫入
```

**建議修改後代碼（含配置接口）**:
```python
# 讀取配置
cfg = load_config()
student_allow_read = cfg.get("studentAllowRead", False)
student_allow_write = cfg.get("studentAllowWrite", False)

# Teacher 環境
env_teacher = os.environ.copy()
env_teacher["PWD"] = str(teacher_dir)
env_teacher["SANDBOX_ALLOW_WRITE"] = "1"       # ✅ 教師始終允許寫檔
env_teacher["SANDBOX_UID"] = str(teacher_uid)  # 1450
env_teacher["SANDBOX_GID"] = str(sandbox_gid)  # 1450

# Student 環境
env_student = os.environ.copy()
env_student["PWD"] = str(student_dir)

# ⚙️ 配置接口：根據設定決定學生讀寫權限
if student_allow_write:
    env_student["SANDBOX_ALLOW_WRITE"] = "1"   # ✅ 允許寫檔（需配置啟用）
else:
    env_student.pop("SANDBOX_ALLOW_WRITE", None)  # ❌ 禁止寫檔（預設）

if student_allow_read:
    env_student["SANDBOX_ALLOW_READ"] = "1"    # ✅ 允許讀檔（需配置啟用）
else:
    env_student.pop("SANDBOX_ALLOW_READ", None)  # ❌ 禁止讀檔（預設）

env_student["SANDBOX_UID"] = str(student_uid)  # 1451
env_student["SANDBOX_GID"] = str(sandbox_gid)  # 1450
```

**配置說明**:
- **預設情況**（`studentAllowRead=false`, `studentAllowWrite=false`）：
  - 學生**完全無法讀取** src 目錄
  - 學生**完全無法寫入** src 目錄
- **特殊場景**：
  - 一般題目需要讀取：設置 `studentAllowRead=true`
  - 需要生成輸出檔案的題目：設置 `studentAllowWrite=true`
- 此接口為後續模組（如檔案輸出題型）預留擴展點

### 步驟 5: 啟動子進程

```python
# Teacher 進程
procs["teacher"] = subprocess.Popen(
    commands["teacher"],
    cwd=teacher_dir,      # Teacher 工作目錄
    env=env_teacher,      # 包含 SANDBOX_UID=1450
    pass_fds=keep_fds,
)

# Student 進程
procs["student"] = subprocess.Popen(
    commands["student"],
    cwd=student_dir,      # Student 工作目錄（或 /src）
    env=env_student,      # 包含 SANDBOX_UID=1451
    pass_fds=keep_fds,
)
```

**重要**: `sandbox_interactive` 必須從環境變數讀取 `SANDBOX_UID` 並降權到對應的 UID。

---

## ✅ 驗證方法

### 驗證 1: 檢查目錄權限

```bash
# 在容器內執行
ls -la /workspace/teacher/
# 預期輸出：drwx------ 1450 1450 ... teacher

ls -la /workspace/src/
# 預期輸出：drwxr-xr-x 1451 1450 ... src
```

### 驗證 2: 檢查文件權限

```bash
ls -la /workspace/teacher/testcase.in
# 預期輸出：-rw------- 1450 1450 ... testcase.in

ls -la /workspace/teacher/Check_Result
# 預期輸出：-rw------- 1450 1450 ... Check_Result (如果創建)
```

### 驗證 3: 測試教師寫入

```bash
# 在教師進程中（UID 1450）
echo "STATUS: AC" > /workspace/teacher/Check_Result
echo $?
# 預期輸出：0 (成功)
```

### 驗證 4: 測試學生讀取

```bash
# 在學生進程中（UID 1451）
cat /workspace/teacher/testcase.in
# 預期輸出：Permission denied

ls /workspace/teacher/
# 預期輸出：Permission denied
```

### 驗證 5: 測試學生寫入（預設禁止）

```bash
# 在學生進程中（UID 1451），當 studentAllowWrite=false
touch /workspace/src/test.txt
# 預期輸出：Operation not permitted (被 Seccomp 阻止)
```

### 驗證 6: 測試學生寫入（配置允許）

```bash
# 在學生進程中（UID 1451），當 studentAllowWrite=true
echo "test" > /workspace/src/output.txt
echo $?
# 預期輸出：0 (成功)

ls -la /workspace/src/output.txt
# 預期輸出：-rw-r--r-- 1451 1450 ... output.txt
```

---

## 🧹 Host 端清理

### 問題

執行後，目錄和文件屬於 UID 1450/1451，host 上的普通用戶可能無權刪除。

### 解決方案

#### 方案 A: 修改權限後刪除

```python
def clean_data(submission_id: str):
    """清理提交數據"""
    submission_path = SUBMISSION_DIR / submission_id
    
    if not submission_path.exists():
        return
    
    try:
        # 1. 遞迴放寬所有權限
        for root, dirs, files in os.walk(submission_path, topdown=False):
            for name in files:
                try:
                    filepath = os.path.join(root, name)
                    os.chmod(filepath, 0o666)
                except:
                    pass
            for name in dirs:
                try:
                    dirpath = os.path.join(root, name)
                    os.chmod(dirpath, 0o777)
                except:
                    pass
        
        # 2. 刪除整個目錄
        os.chmod(submission_path, 0o777)
        shutil.rmtree(submission_path)
        
    except PermissionError:
        # Fallback: 使用特權容器清理
        logger().warning(f"Using container cleanup for {submission_id}")
        subprocess.run([
            "docker", "run", "--rm",
            "-v", f"{submission_path}:/cleanup",
            "alpine:latest",
            "rm", "-rf", "/cleanup"
        ], timeout=10)
```

#### 方案 B: 統一 GID 清理

由於所有文件都屬於 `sandbox_gid=1450`，可以：

1. Host 上創建 group 1450
2. 將清理用戶加入該 group
3. 確保 group 有寫權限（teacher 600 → 660, student 644 → 664）

**不推薦**，因為會降低安全性。

---

## 🎯 完整實現清單

### 必須修改的地方

#### 1. ⚠️ 刪除或註釋 `_relax_dir_permissions()` 調用

**當前代碼問題** (L323-324):
```python
# ❌ 當前仍在調用（需移除）
_relax_dir_permissions(teacher_dir)  # L323
_relax_dir_permissions(student_dir)  # L324

# ✅ 應該只保留嚴格權限設置 (L325-327)
_setup_secure_permissions(teacher_dir, student_dir, teacher_uid,
                          student_uid, sandbox_gid)
```

**說明**: 先調用 `_relax_dir_permissions` 放寬權限，再調用 `_setup_secure_permissions` 設置嚴格權限，這個順序會導致權限設置混亂。

#### 2. 修改 testcase.in 權限 (L418)

```python
# ❌ 當前代碼（錯誤）
os.chmod(case_local, 0o400)  # 只讀 - 教師可能無法使用！

# ✅ 應修改為
os.chmod(case_local, 0o600)  # 可讀寫
```

**影響**: 當前的 `0o400` 只允許 owner 讀取，教師無法修改測資檔案。

#### 3. 確認 chown 順序 (L420)

```python
# ✅ 確保在 chmod 之後 chown
os.chmod(case_local, 0o600)
os.chown(case_local, teacher_uid, sandbox_gid)
```

#### 4. 刪除重複的 `_secure_directories()` 函數

只保留 `_setup_secure_permissions()`，刪除 `_secure_directories()`。

### 可選改進

1. **添加權限驗證**: 在設置後驗證權限是否正確
2. **詳細日誌**: 記錄所有權限操作
3. **錯誤處理**: 權限設置失敗時的降級策略

---

## 📖 常見問題

### Q1: 為什麼教師還是無法寫入 Check_Result？

**檢查清單**:
1. ✅ Teacher 目錄 owner 是 1450？（`ls -ln /workspace/teacher`）
2. ✅ Teacher 目錄權限是 700？（`ls -la /workspace/teacher`）
3. ✅ 教師進程的有效 UID 是 1450？（在教師進程中執行 `id -u`）
4. ✅ `SANDBOX_ALLOW_WRITE=1` 環境變數已設置？

### Q2: 為什麼學生還是能讀取 teacher 目錄？

**檢查清單**:
1. ❌ 確認學生進程的有效 UID 是 1451 而非 1450
2. ❌ 確認 teacher 目錄權限是 700 而非 755
3. ❌ 確認沒有符號連結指向 teacher 目錄

### Q3: Host 無法刪除提交目錄？

**解決方法**:
```bash
# 臨時方案：手動修改權限
sudo chmod -R 777 /path/to/submission_dir
sudo rm -rf /path/to/submission_dir

# 長期方案：使用清理容器
docker run --rm -v /path/to/submission_dir:/cleanup alpine rm -rf /cleanup
```

---

## 🎉 總結

### 核心要點

1. **雙 UID 隔離**: Teacher=1450, Student=1451
2. **Teacher 目錄 700**: 只有 owner 可訪問
3. **Teacher 文件 600**: 只有 owner 可讀寫
4. **testcase.in 必須 600**: 不是 400（只讀）
5. **環境變數傳遞 UID**: `SANDBOX_UID` 給 sandbox_interactive

### 安全保障

- **Layer 1**: UID 隔離（1450 vs 1451）
- **Layer 2**: 文件權限（700/600 vs 755/644）
- **Layer 3**: Seccomp 禁止學生寫入
- **Layer 4**: 執行後清除 testcase.in

這套方案確保教師可以正常工作，同時學生無法訪問敏感資料！
