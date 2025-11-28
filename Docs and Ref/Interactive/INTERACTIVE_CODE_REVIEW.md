# Interactive 模式代碼審查報告

**審查日期**: 2025-11-29  
**審查範圍**: `interactive_orchestrator.py`, `interactive_runner.py`  
**審查重點**: 業務邏輯、代碼質量、組織結構、流程設計、安全性

---

## 執行摘要

Interactive 模式實現整體功能完整，但存在**多處代碼質量和設計問題**。本次審查發現 **15 個需要改進的問題**，包括冗餘代碼、安全風險、不合理的職責劃分和流程設計缺陷。

### 優先級分佈

| 優先級 | 數量 | 類型 |
|--------|------|------|
| 🔴 高 | 4 | 安全風險、邏輯錯誤 |
| ⚠️ 中 | 7 | 代碼組織、冗餘代碼 |
| ℹ️ 低 | 4 | 代碼風格、可維護性 |

---

## 🔴 高優先級問題

### 問題 1: tmpdir 權限邏輯矛盾

**位置**: `interactive_orchestrator.py` L348-352

**問題描述**:
```python
# 預設 700，若需要 FIFO 且學生可寫才開到 711（學生可進入）
if args.pipe_mode == "fifo" and student_allow_write:
    os.chmod(tmpdir, 0o711)
else:
    os.chmod(tmpdir, 0o700)
```

**分析**:
1. **邏輯錯誤**: FIFO 模式下學生**不需要**進入 tmpdir，FIFO 檔案路徑由 sandbox_interactive 處理
2. **安全風險**: `0o711` 允許學生執行 tmpdir，可能枚舉檔案名
3. **與 L310-312 矛盾**: 已經有 FIFO fallback 邏輯，這裡不應該再調整權限

**影響**: 中等安全風險，學生可能訪問 tmpdir

**建議**:
```python
# tmpdir always 700 - student never needs direct access
os.chmod(tmpdir, 0o700)
```

---

### 問題 2: `_limit_fn` 未使用且職責不清

**位置**: `interactive_orchestrator.py` L52-64

**問題描述**:
```python
def _limit_fn(time_limit_ms: int, mem_limit_kb: int):
    def _apply():
        cpu_seconds = max(1, time_limit_ms // 1000)
        try:
            resource.setrlimit(resource.RLIMIT_CPU, (cpu_seconds, cpu_seconds))
        except Exception:
            pass
        # ...
    return _apply
```

**分析**:
1. **完全未使用**: 整個文件沒有調用此函數
2. **職責混亂**: 資源限制應由 `sandbox_interactive` 處理，不應在 orchestrator
3. **冗餘代碼**: 占用代碼空間，誤導閱讀

**影響**: 代碼混亂，誤導維護者

**建議**: 刪除此函數

---

### 問題 3: `_dir_size` 未使用

**位置**: `interactive_orchestrator.py` L162-170

**問題描述**:
```python
def _dir_size(path: Path) -> int:
    total = 0
    for p in path.rglob(\"*\"):
        try:
            if p.is_file():
                total += p.stat().st_size
        except Exception:
            continue
    return total
```

**分析**:
1. **未使用**: 整個文件沒有調用
2. **誤導性**: 看起來像是用於限制檔案大小，但實際沒有
3. **冗餘**: 可能是早期實現遺留

**影響**: 代碼冗餘，混淆意圖

**建議**: 刪除此函數，或實現檔案大小限制並使用它

---

### 問題 4: `seccomp=unconfined` 安全風險

**位置**: `interactive_runner.py` L60

**問題描述**:
```python
security_opt=[\"seccomp=unconfined\"],
```

**分析**:
1. **嚴重安全風險**: 完全禁用 Seccomp，學生可執行任意系統調用
2. **與設計矛盾**: 代碼中有 `SANDBOX_ALLOW_WRITE` 環境變數，暗示依賴 Seccomp，但這裡卻禁用
3. **應該使用自定義 profile**: 應該指定 Seccomp 配置文件路徑

**影響**: **嚴重安全風險**

**建議**:
```python
# 使用自定義 seccomp profile
security_opt=[\"seccomp=/path/to/interactive-seccomp.json\"],
```

或在容器內由 `sandbox_interactive` 應用 Seccomp。

---

## ⚠️ 中優先級問題

### 問題 5: Teacher/Student cwd 不一致

**位置**: `interactive_orchestrator.py` L464, L414

**問題描述**:
```python
# Student cwd
procs[\"student\"] = subprocess.Popen(
    commands[\"student\"],
    cwd=Path(\"/src\"),  # 硬編碼路徑
    env=env_student,
    pass_fds=keep_fds,
)

# 但環境變數設置
env_student[\"PWD\"] = str(student_dir)  # /workspace/src
```

**分析**:
1. **不一致**: cwd 是 `/src`，但 `PWD` 環境變數是 `student_dir`
2. **混淆**: Teacher 使用 `teacher_dir`，Student 使用 `/src`，不對稱
3. **潛在問題**: 某些程式依賴 `PWD` 環境變數

**影響**: 可能導致路徑解析錯誤

**建議**:
```python
# 統一使用 student_dir
cwd=student_dir,
```

---

### 問題 6: 重複的 `_ensure_exec` 調用

**位置**: `interactive_orchestrator.py` L337-338

**問題描述**:
```python
if student_lang != \"python3\":
    _ensure_exec(student_entry, [student_dir / \"a.out\", student_entry])
    _ensure_exec(student_dir / \"a.out\", [student_entry])  # 重複？
```

**分析**:
1. **邏輯混亂**: 
   - L337: 確保 `main` 存在，從 `a.out` 或 `main` 複製
   - L338: 確保 `a.out` 存在，從 `main` 複製
   - 循環引用？
2. **可能是 workaround**: 處理 `a.out` 和 `main` 互換問題
3. **應該簡化**: 明確哪個是主檔案

**影響**: 代碼混亂，難以理解

**建議**: 釐清邏輯，使用單一入口點

---

### 問題 7: 異常捕獲過於寬泛

**位置**: 多處（L57, L62, L157, L201, etc.）

**問題描述**:
```python
except Exception:
    pass
```

**分析**:
1. **掩蓋錯誤**: 捕獲所有異常並靜默，難以調試
2. **無日誌**: 大部分地方沒有記錄異常
3. **不安全**: 可能掩蓋嚴重錯誤

**影響**: 調試困難，隱藏問題

**建議**:
```python
except Exception as exc:
    logger.warning(\"Operation failed: %s\", exc)
    # 或根據情況決定是否 raise
```

---

### 問題 8: 魔術數字過多

**位置**: `interactive_orchestrator.py` L378-391

**問題描述**:
```python
student_cmd_core = \" \".join([
    \"sandbox_interactive\",
    str(LANG_IDS[student_lang]),
    \"0\",  # ❓ 什麼意思？
    pipe_bundle[\"student\"][\"stdin\"],
    pipe_bundle[\"student\"][\"stdout\"],
    pipe_bundle[\"student\"].get(\"stderr\", str(tmpdir / \"student.err\")),
    str(args.time_limit),
    str(args.mem_limit),
    \"1\",  # ❓ 什麼意思？
    str(output_limit),
    \"10\",  # ❓ 什麼意思？
    str(stu_res),
])
```

**分析**:
1. **缺少說明**: `\"0\"`, `\"1\"`, `\"10\"` 沒有註釋
2. **難以維護**: 不知道這些參數的含義
3. **應該使用常量或註釋**: 提升可讀性

**影響**: 可維護性差

**建議**:
```python
# sandbox_interactive 參數定義
SANDBOX_UID_INDEX = 0  # 第2個參數
SANDBOX_RUN_MODE = \"1\"  # 1=run, 0=check
SANDBOX_UNKNOWN_PARAM = \"10\"  # TODO: clarify

student_cmd_core = [
    \"sandbox_interactive\",
    str(LANG_IDS[student_lang]),
    str(SANDBOX_UID_INDEX),  # UID index
    # ... 其他參數加註釋
]
```

---

### 問題 9: Kick logic 過於複雜且缺乏註釋

**位置**: `interactive_orchestrator.py` L485-514

**問題描述**:
```python
if kick_dup is not None:
    try:
        kick_dup = os.dup(kick_student_fd)
    except Exception:
        kick_dup = None
# ...
# if student already退出且 teacher 還在等，送一個換行解除阻塞
if (kick_dup is not None and \"student\" in procs
        and procs[\"student\"].poll() is not None
        and procs.get(\"teacher\") and procs[\"teacher\"].poll() is None):
    try:
        os.write(kick_dup, b\"\\n\")
    except Exception:
        pass
```

**分析**:
1. **複雜**: kick logic 的目的不明確
2. **註釋不足**: 為什麼要 `dup`？為什麼寫入換行？
3. **可能的 race condition**: 在沒有 lock 的情況下檢查和寫入

**影響**: 難以理解和調試

**建議**: 添加詳細註釋說明此邏輯的目的和原理

---

### 問題 10: testcase.in 清理邏輯不合理

**位置**: `interactive_orchestrator.py` L543-550

**問題描述**:
```python
if case_local and case_local.exists():
    try:
        case_local.unlink()
    except Exception:
        try:
            os.chmod(case_local, 0o600)  # ❓ 為什麼？
        except Exception:
            pass
```

**分析**:
1. **邏輯不清**: 刪除失敗時 chmod，但不再嘗試刪除
2. **可能遺留檔案**: chmod 後不會清理，可能累積
3. **應該記錄**: 刪除失敗是重要錯誤

**影響**: 可能遺留測資檔案

**建議**:
```python
if case_local and case_local.exists():
    try:
        case_local.unlink()
    except PermissionError:
        try:
            os.chown(case_local, os.getuid(), os.getgid())
            case_local.unlink()
        except Exception as exc:
            logger.error(\"Failed to delete testcase.in: %s\", exc)
```

---

### 問題 11: tmpdir 清理失敗靜默

**位置**: `interactive_orchestrator.py` L593-600

**問題描述**:
```python
if not os.getenv(\"KEEP_INTERACTIVE_TMP\"):
    try:
        shutil.rmtree(tmpdir)
    except Exception:
        try:
            tmpdir.chmod(0o700)
        except Exception:
            pass
```

**分析**:
1. **邏輯同 testcase.in**: chmod 但不清理
2. **累積問題**: 失敗的 tmpdir 會累積
3. **應該告警**: tmpdir 清理失敗需要人工介入

**影響**: 磁碟空間浪費

**建議**: 記錄錯誤並考慮定期清理機制

---

## ℹ️ 低優先級問題

### 問題 12: 函數過大

**位置**: `interactive_orchestrator.py` `orchestrate()` L291-617

**問題描述**: 主函數 326 行，過於龐大

**分析**:
1. **職責混雜**: 配置、準備、執行、結果處理都在一個函數
2. **難以測試**: 單元測試困難
3. **應該拆分**: 至少分為 setup, execute, collect_results

**影響**: 可維護性和可測試性差

**建議**: 拆分為多個函數，每個職責明確

---

### 問題 13: 冗餘的路徑轉換

**位置**: `interactive_orchestrator.py` L295, L414, L415

**問題描述**:
```python
# L295
student_dir = Path(args.student_dir) if args.student_dir else workdir / \"src\"

# L414-415
env_student[\"PWD\"] = str(student_dir)  # Path -> str
env_teacher[\"PWD\"] = str(teacher_dir)
```

**分析**:
1. **頻繁轉換**: Path ↔ str 轉換多次
2. **應該統一**: 全部用 Path 或全部用 str
3. **建議**: 內部用 Path，輸出時才轉 str

**影響**: 代碼略顯累贅

---

### 問題 14: 命名不一致

**位置**: 多處

**問題描述**:
- `teacher_dir` vs `student_dir`
- `teacher_main` vs `student_entry`
- `stu_res` vs `teacher.result`

**分析**:
1. **不一致**: Teacher 叫 `teacher_main`，Student 叫 `student_entry`
2. **縮寫不一致**: `stu_res` vs 完整名稱
3. **應該統一**: 提升可讀性

**影響**: 可讀性略差

**建議**: 統一命名風格，如 `teacher_entry`, `student_entry`

---

### 問題 15: 缺少類型提示

**位置**: 多處函數

**問題描述**:
```python
def _setup_pipes(tmpdir: Path, mode: str):  # 缺少返回類型
    # ...
    return {  # dict 但沒有類型提示
        \"mode\": \"devfd\",
        # ...
    }
```

**分析**:
1. **缺少返回類型**: 多數函數沒有 `-> type` 標註
2. **dict 無類型**: 返回的 dict 應該用 TypedDict
3. **影響**: IDE 無法提供好的補全和檢查

**建議**: 添加完整類型提示

---

## 業務邏輯分析

### ✅ 合理的設計

1. **雙進程架構**: Teacher/Student 分離執行，設計合理
2. **FIFO fallback**: 自動 fallback 到 devfd，提升相容性
3. **權限隔離**: Teacher/Student 使用不同 UID，安全性好
4. **結果優先級**: Student 錯誤 > Teacher 錯誤 > Check_Result，邏輯清晰
5. **檔案數量限制**: 防止 Teacher 創建過多檔案，資源保護

### ⚠️ 需要改進的流程

1. **權限設置時機**: 應該在容器內設置，而非 host 端
2. **資源限制**: 應統一由 sandbox_interactive 處理
3. **錯誤處理**: 過於寬泛，應該更精確
4. **臨時檔案清理**: 失敗處理不當

---

## 安全性評估

### 已實施的安全機制

| 機制 | 實施狀態 | 效果 |
|------|---------|------|
| UID/GID 隔離 | ✅ 完整 | 防止檔案訪問 |
| tmpdir 權限 | ✅ 已修正 | 防止學生訪問 |
| 檔案權限控制 | ✅ 完整 | 雙重防護 |
| 檔案數量限制 | ✅ 完整 | 防止資源耗盡 |
| 輸出限制 | ✅ 完整 | 防止 OLE |

### 安全風險

| 風險 | 嚴重性 | 現狀 | 建議 |
|------|--------|------|------|
| Seccomp 禁用 | 🔴 高 | 完全禁用 | 啟用自定義 profile |
| tmpdir 711 權限 | ⚠️ 中 | 條件性開放 | 移除此邏輯 |
| 異常靜默 | ⚠️ 中 | 普遍存在 | 添加日誌 |
| 測資洩露 | ℹ️ 低 | 清理邏輯有缺陷 | 改進清理 |

---

## 代碼組織建議

### 當前結構

```
interactive_orchestrator.py (675 lines)
├── Config loading (30 lines)
├── Helper functions (180 lines)
├── orchestrate() (326 lines)  ← 過大
└── main() (35 lines)
```

### 建議重構

```
interactive_orchestrator.py
├── config.py
│   └── load_config()
├── permissions.py
│   ├── setup_teacher_permissions()
│   ├── setup_student_permissions()
│   └── setup_tmpdir_permissions()
├── pipes.py
│   ├── setup_fifo_pipes()
│   └── setup_devfd_pipes()
├── execution.py
│   ├── prepare_environment()
│   ├── start_processes()
│   ├── monitor_processes()
│   └── collect_results()
└── main.py
    └── orchestrate()  (協調各模組)
```

**優點**:
- 職責清晰
- 易於測試
- 易於維護
- 易於擴展

---

## 修正優先級

### 立即修正 (P0)

1. ✅ **移除 `seccomp=unconfined`**: 嚴重安全風險
2. ✅ **移除 tmpdir 711 邏輯**: 安全漏洞
3. ✅ **刪除未使用函數**: `_limit_fn`, `_dir_size`

### 短期修正 (P1)

4. ✅ **統一 Student cwd**: 修正路徑不一致
5. ✅ **改進異常處理**: 添加日誌
6. ✅ **修正測資清理**: 改進清理邏輯
7. ✅ **添加參數註釋**: 魔術數字問題

### 長期改進 (P2)

8. ⚠️ **重構 orchestrate()**: 拆分函數
9. ⚠️ **添加類型提示**: 完整類型標註
10. ⚠️ **統一命名風格**: 提升可讀性

---

## 測試建議

### 當前測試覆蓋

根據 `INTERACTIVE_MODE_FLOW.md` L390-401，測試覆蓋：
- ✅ AC/WA 基本流程
- ✅ Check_Result 處理
- ✅ 師/生 TLE
- ✅ FIFO fallback
- ✅ Seccomp 測試

### 建議補充測試

1. **權限測試**:
   - tmpdir 訪問測試
   - testcase.in 讀取權限測試
   - 跨用戶檔案訪問測試

2. **錯誤恢復測試**:
   - tmpdir 清理失敗處理
   - testcase.in 清理失敗處理
   - FIFO 創建失敗處理

3. **邊界測試**:
   - 大量檔案創建
   - 極大輸出
   - 極限資源使用

---

## 總結

### 整體評價

| 維度 | 評分 | 說明 |
|------|------|------|
| 功能完整性 | ⭐⭐⭐⭐⭐ | 功能完整，符合需求 |
| 安全性 | ⭐⭐⭐ | 有隔離機制，但 Seccomp 禁用是隱患 |
| 代碼質量 | ⭐⭐⭐ | 冗餘代碼和魔術數字較多 |
| 可維護性 | ⭐⭐ | 函數過大，職責混雜 |
| 可測試性 | ⭐⭐ | 大函數難以單元測試 |

### 關鍵建議

1. **立即**: 修復 Seccomp 和 tmpdir 權限問題
2. **短期**: 改進異常處理和代碼註釋
3. **長期**: 重構代碼結構，提升可維護性

### 下一步行動

建議創建 **Implementation Plan** 按優先級修正問題，並在修正後更新本報告。
