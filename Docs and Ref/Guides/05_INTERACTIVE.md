# Interactive Mode Guide

## 1. Overview

Interactive Mode is one of the three execution modes in Normal-OJ Sandbox (general / functionOnly / **interactive**), designed to support **interactive problems**. In this mode, the student's program and the teacher's program communicate in real-time via pipes, with the teacher's program responsible for judging logic and generating the final verdict.

## 2. Core Concepts

### Dual Program Architecture
- **Student Program** (`/workspace/src`): The code submitted by the student.
- **Teacher Program** (`/workspace/teacher`): The judging program uploaded by the teacher (`Teacher_file`).
- Both programs run in the same Docker container, communicating via FIFO or `/dev/fd` for stdin/stdout.

### Build Strategy
Interactive Mode uses `BuildStrategy.MAKE_INTERACTIVE` (Value: 3).

## 3. Configuration Parameters

### Meta Fields (`dispatcher/meta.py`)

```python
class Meta(BaseModel):
    language: Language                    # Student program language
    executionMode: ExecutionMode          # Set to INTERACTIVE
    buildStrategy: BuildStrategy          # Set to MAKE_INTERACTIVE
    teacherFirst: bool = False            # Whether teacher program runs first
    assetPaths: Dict[str, str]            # Contains teacher_file and teacherLang
```

#### Key Configurations
- **`teacherFirst`**: Controls startup order.
  - `False` (Default): Student program starts -> 50ms delay -> Teacher program starts.
  - `True`: Teacher program starts -> 50ms delay -> Student program starts.
  
- **`assetPaths`**:
  - `teacher_file`: Path to teacher file in MinIO.
  - `teacherLang`: Teacher program language (`"c"` / `"cpp"` / `"py"`).

## 4. Execution Flow

### Phase 1: Preparation (Dispatcher)

#### 1.1 Teacher_file Download & Preparation
- Parses teacher language.
- Downloads `teacher_file` from MinIO.
- Writes to `teacher/main.{c,cpp,py}`.

#### 1.2 Teacher Program Compilation
- **C/C++**: Compiled using `SubmissionRunner.compile_at_path`. Generates `Teacher_main` binary.
- **Python**: Uses `teacher/main.py` directly.

#### 1.3 Student Program Build
- **CODE Mode**:
  - C/C++: Compiles `src/common/main.{c,cpp}` -> `src/common/a.out`.
  - Python: Uses `src/common/main.py`.
- **ZIP Mode**:
  - Must include `Makefile`.
  - Runs `make` to generate `src/common/a.out`.

### Phase 2: Container Execution (InteractiveRunner)

#### 2.1 Startup Arguments
`InteractiveRunner` mounts `src/cases/<case_no>` to `/src` inside the container.

#### 2.2 Orchestrator Initialization
- Sets directory permissions (see Section 6).
- Injects testcase (`testcase.in`) if present.

### Phase 3: Pipe Communication

#### 3.1 Pipe Mode Selection
- **FIFO Mode** (Preferred): Uses named pipes (`s2t.fifo`, `t2s.fifo`).
- **devfd Mode** (Fallback): Uses `os.pipe()` and `/dev/fd/`.

#### 3.2 Sandbox Command Generation
Runs `sandbox_interactive` for both student and teacher processes with appropriate arguments.

### Phase 4: Execution & Monitoring

#### 4.1 Startup Order
Controlled by `teacherFirst` configuration.

#### 4.2 Watchdog Monitoring
Monitors processes with a deadline (Time Limit + 2s buffer). Kills all processes if timeout occurs.

### Phase 5: Result Judgment

#### 5.1 Sandbox Result Parsing
Parses status (AC/TLE/MLE/RE/OLE), execution time, and memory usage.

#### 5.2 Check_Result Parsing
Teacher program must write judgment result to `teacher/Check_Result`:
```
STATUS: AC
MESSAGE: All test cases passed
```

#### 5.3 Final Verdict Logic
Priority:
1. **Student Error** -> Student Status (CE/RE/TLE/MLE/OLE)
2. **Teacher Error** -> Teacher Status (CE/RE/TLE/MLE)
3. **Invalid Check_Result** -> `CE`
4. **Valid Check_Result** -> `AC` or `WA`

---

## 5. Permissions & Security

### Security Goals
1. ✅ **Teacher can read/write** teacher directory (including writing `Check_Result`).
2. ✅ **Teacher can read** testcase files (`testcase.in`).
3. ❌ **Student cannot read** teacher directory (source code, testdata, results).
4. ⚙️ **Student Permissions**:
   - **Read**: Default forbidden, configurable.
   - **Write**: Default forbidden (via Seccomp), configurable.
5. ✅ **Teacher can read** student's src directory (read-only).

### UID/GID Configuration

| Parameter | Value | Description |
|-----------|-------|-------------|
| **TEACHER_UID** | 1450 | Teacher process UID |
| **STUDENT_UID** | 1451 | Student process UID |
| **SANDBOX_GID** | 1450 | Unified Group ID |

### Permission Matrix

#### Directory Permissions
| Path | Owner | Group | Mode | Octal | Teacher(1450) | Student(1451) |
|------|-------|-------|------|-------|---------------|---------------|
| `/workspace/teacher/` | 1450 | 1450 | `drwx------` | 700 | ✅ rwx | ❌ --- |
| `/workspace/src/` | 1451 | 1450 | `drwxr-xr-x` | 755 | ✅ r-x | ✅ rwx |

#### File Permissions
| File | Owner | Group | Mode | Octal | Teacher(1450) | Student(1451) |
|------|-------|-------|------|-------|---------------|---------------|
| `teacher/main.c` | 1450 | 1450 | `-rw-------` | 600 | ✅ rw- | ❌ --- |
| `teacher/testcase.in` | 1450 | 1450 | `-rw-------` | 600 | ✅ rw- | ❌ --- |
| `teacher/Check_Result` | 1450 | 1450 | `-rw-------` | 600 | ✅ rw- | ❌ --- |
| `src/main.c` | 1451 | 1450 | `-rw-r--r--` | 644 | ✅ r-- | ✅ rw- |

### Implementation Details

#### Initialization
Permissions are set in `orchestrate()` before starting subprocesses. `_setup_secure_permissions` ensures strict 700/600 permissions for teacher files and 755/644 for student files.

#### Testcase Injection
When injecting `testcase.in`, permissions are explicitly set to `0o600` (Read/Write for Owner) and ownership to `TEACHER_UID`.

#### Environment Variables
- **Teacher**: `SANDBOX_ALLOW_WRITE=1` (Always allowed).
- **Student**: `SANDBOX_ALLOW_WRITE` is set only if configured (default off).

### Verification
- **Teacher Write**: Teacher process should be able to write to `Check_Result`.
- **Student Read**: Student process should get "Permission denied" when trying to access `/workspace/teacher`.
- **Student Write**: Student process should be blocked by Seccomp (or allowed if configured) when writing to `/workspace/src`.

## 6. Resource Limits

- **Time Limit**: Set via `RLIMIT_CPU`. Watchdog adds 2s buffer.
- **Memory Limit**: Set via `RLIMIT_AS`. Calculated independently for student and teacher.
- **Output Limit**: Default 64 MB (`outputLimitBytes`). Exceeding triggers `OLE`.
- **File Count**: Teacher limited to creating 500 new files.
