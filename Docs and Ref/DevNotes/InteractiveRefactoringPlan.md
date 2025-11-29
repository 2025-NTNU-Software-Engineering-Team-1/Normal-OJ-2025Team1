# Interactive架構重構實施計劃（修訂版）

## 目標

簡化Interactive submission的架構重構，保持現有BuildStrategy enum不變，僅在Sandbox的dispatcher和build_strategy層進行重構，實現：
1. 統一的teacher準備函式（合併`_ensure_teacher_source`和`_prepare_teacher_artifacts`的邏輯）
2. 在single function內處理zip/code模式區分
3. 嚴格的Makefile驗證（zip mode）

## User Review Required

> [!WARNING]
> **Strict Zip Validation Change**
> 
> Interactive + Zip模式若缺少Makefile（C/C++），將**直接CE**而非fallback到compile。
> - 這是行為改變，may reject previously "working" submissions
> - 需要在文檔和error message中明確說明

## 架構設計

### 當前問題

1. **Teacher準備邏輯分散**
   - `_ensure_teacher_source()` 和 `_prepare_teacher_artifacts()` 分別調用
   - 沒有統一的entry point

2. **Zip mode的fallback行為不明確**
   - `prepare_make_interactive()` 在zip缺少Makefile時靜默fallback

3. **Meta中有submissionMode但未充分利用**
   - 現在只靠檢查Makefile存在與否判斷

### 新設計

統一teacher準備 → 依meta.submissionMode區分zip/code → 嚴格驗證

---

## Proposed Changes

### Sandbox Components Only

#### [MODIFY] [build_strategy.py](file:///\\wsl.localhost\Ubuntu-20.04\home\camel0311\code\NOJ_Repo\Normal-OJ-2025Team1\Sandbox\dispatcher\build_strategy.py)

**1. 新增統一teacher準備函式（line 42之前）**

合併`_ensure_teacher_source`(line 271-298)和`_prepare_teacher_artifacts`(line 232-268)的邏輯：

```python
def prepare_interactive_teacher_artifacts(
    problem_id: int,
    meta: Meta,
    submission_dir: Path,
) -> None:
    """
    Prepare teacher artifacts for interactive mode.
    Combines _ensure_teacher_source and _prepare_teacher_artifacts logic.
    """
    # Determine teacher language
    teacher_lang_val = (meta.assetPaths or {}).get("teacherLang")
    teacher_lang_map = {"c": Language.C, "cpp": Language.CPP, "py": Language.PY}
    teacher_lang = teacher_lang_map.get(
        str(teacher_lang_val or "").lower(), Language(meta.language))
    
    # Check teacher_file exists
    teacher_path = meta.assetPaths.get("teacher_file") if getattr(
        meta, "assetPaths", None) else None
    if not teacher_path:
        raise BuildStrategyError("interactive mode requires Teacher_file")
    
    # Create teacher directory
    teacher_dir = submission_dir / "teacher"
    if teacher_dir.exists():
        shutil.rmtree(teacher_dir)
    teacher_dir.mkdir(parents=True, exist_ok=True)
    
    # Fetch and write teacher source
    data = fetch_problem_asset(problem_id, "teacher_file")
    ext = {Language.C: ".c", Language.CPP: ".cpp", Language.PY: ".py"}.get(teacher_lang)
    if ext is None:
        raise BuildStrategyError("unsupported teacher language")
    src_path = teacher_dir / f"main{ext}"
    src_path.write_bytes(data)
    
    # Re-resolve teacher language by checking actual files
    teacher_lang = _resolve_teacher_lang(meta=meta, teacher_dir=teacher_dir)
    
    # Python doesn't need compilation
    if teacher_lang == Language.PY:
        if not (teacher_dir / "main.py").exists():
            raise BuildStrategyError("teacher script missing")
        return
    
    # Compile C/C++
    compile_res = SubmissionRunner.compile_at_path(
        src_dir=str(teacher_dir.resolve()),
        lang=_lang_key(teacher_lang),
    )
    if compile_res.get("Status") != "AC":
        err_msg = compile_res.get("Stderr") or compile_res.get(
            "ExitMsg") or "teacher compile failed"
        raise BuildStrategyError(f"teacher compile failed: {err_msg}")
    
    binary = teacher_dir / "Teacher_main"
    if not binary.exists():
        raise BuildStrategyError("teacher binary missing after compile")
    
    # Create ./main symlink
    main_exec = teacher_dir / "main"
    if not main_exec.exists():
        try:
            os.link(binary, main_exec)
        except Exception:
            try:
                shutil.copy(binary, main_exec)
            except Exception:
                pass
    
    os.chmod(binary, binary.stat().st_mode | 0o111)
    if main_exec.exists():
        try:
            os.chmod(main_exec, main_exec.stat().st_mode | 0o111)
        except Exception:
            pass
```

**2. 重構 `prepare_make_interactive`（line 43-64）**

```python
def prepare_make_interactive(
    problem_id: int,
    meta: Meta,
    submission_dir: Path,
) -> BuildPlan:
    """
    Interactive mode handler - processes both zip and code submissions.
    """
    # Step 1: Prepare teacher (unified function)
    prepare_interactive_teacher_artifacts(
        problem_id=problem_id,
        meta=meta,
        submission_dir=submission_dir,
    )
    
    # Step 2: Check submission mode
    submission_mode = SubmissionMode(meta.submissionMode)
    src_dir = submission_dir / "src"
    language = Language(meta.language)
    
    if submission_mode == SubmissionMode.ZIP:
        # ZIP mode: strict validation
        if language == Language.PY:
            _ensure_main_python(src_dir)
            return BuildPlan(needs_make=False)
        
        # C/C++: must have Makefile
        _ensure_makefile(src_dir)
        return _build_plan_for_student_artifacts(
            language=language,
            src_dir=src_dir,
        )
    else:
        # CODE mode: direct compile
        return BuildPlan(needs_make=False)
```

**3. Import更新（line 9）**

```python
from .constant import Language, SubmissionMode  # 新增SubmissionMode
```

**4. (Optional) 移除或標記deprecated**

- `_ensure_teacher_source`(line 271-298) - 可移除
- `_prepare_teacher_artifacts`(line 232-268) - 可移除
- `prepare_interactive_compile`(line 67-77) - 可移除或標記deprecated

---

## Code Verification

### ✅ 所有驗證點都通過

- Meta.submissionMode 可用
- Helper functions全部存在
- 合併後的邏輯完整，無遺漏

---

## Testing Strategy

### Unit Tests (新增4個)

1. `test_prepare_interactive_teacher_artifacts_cpp_success` - C++ teacher準備成功
2. `test_interactive_zip_missing_makefile_raises_error` - Zip缺Makefile → CE  
3. `test_interactive_code_mode_success` - Code mode正常
4. `test_interactive_python_zip_success` - Python zip只需main.py

---

## Implementation Checklist

- [ ] 修改 `build_strategy.py`
  - [ ] 新增import `SubmissionMode`
  - [ ] 新增 `prepare_interactive_teacher_artifacts()`（合併邏輯）
  - [ ] 重構 `prepare_make_interactive()`
  - [ ] (Optional) 移除舊函式或標記deprecated

- [ ] 測試
  - [ ] 新增4個unit tests
  - [ ] 運行現有tests
  - [ ] Manual testing

- [ ] 文檔
  - [ ] 更新 INTERACTIVE_ARCHITECTURE.md

---

## Summary

**改動**: ~80 lines | **風險**: Low-Medium | **時間**: 1-2 hours

關鍵改進：
- ✅ 合併teacher準備邏輯（而非包裝）
- ✅ 使用meta.submissionMode明確判斷
- ✅ Zip mode嚴格驗證
