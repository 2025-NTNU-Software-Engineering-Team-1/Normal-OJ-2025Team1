# Custom Scorer 完整代碼審查報告

## 1. 審查摘要
針對您的要求，我重新完整審視了 Custom Scorer 的實作，並與已運作的 Custom Checker 進行了詳細比對。

**審查結果：** ❌ **確認存在嚴重路徑處理錯誤**

## 2. 路徑錯誤確認與分析

### 2.1 Custom Checker 的正確模式 (參考標準)
```python
# custom_checker.py (Lines 57-76)
workdir = checker_path.parent / "work" / case_no  # WSL Path
workdir.mkdir(parents=True, exist_ok=True)

# ✅ 在路徑轉換前先完成所有檔案寫入
_copy_file(case_in_path, workdir / "input.in")
_copy_file(case_ans_path, workdir / "answer.out")
(workdir / "student.out").write_text(student_output)
shutil.copyfile(checker_path, workdir / "custom_checker.py")

# 轉換路徑給 Docker 使用
translator = PathTranslator()
host_workdir = translator.to_host(workdir)  # 轉為 Host Path

runner = CustomCheckerRunner(
    workdir=str(host_workdir),  # 傳遞 Host Path
    ...
)
result = runner.run()
```

**CustomCheckerRunner 不寫入任何檔案**，它只讀取已存在的檔案並執行 Python 腳本。

### 2.2 Custom Scorer 的錯誤模式 ❌
```python
# custom_scorer.py (Lines 48-63)
workdir = scorer_path.parent / "work"  # WSL Path
workdir.mkdir(parents=True, exist_ok=True)

# ✅ score.py 在轉換前寫入
local_scorer = workdir / "score.py"
shutil.copyfile(scorer_path, local_scorer)

# 轉換路徑給 Docker 使用
translator = PathTranslator()
host_workdir = translator.to_host(workdir)  # 轉為 Host Path

runner = CustomScorerRunner(
    workdir=str(host_workdir),  # 傳遞 Host Path (例如 D:\...\work)
    ...
)
result = runner.run(payload)  # ❌ Runner 會嘗試寫入檔案！
```

**CustomScorerRunner 會寫入檔案**：
```python
# custom_scorer_runner.py (Lines 37-38)
input_path = Path(self.workdir) / "scoring_input.json"  
# self.workdir 是 "D:\NOJ\Sandbox\submissions\123\scorer\work"
# 在 WSL 環境中，Path() 會錯誤解析這個 Windows 路徑
input_path.write_text(json.dumps(payload, ensure_ascii=False))
```

### 2.3 路徑錯誤的後果
在 WSL/Linux 環境中：
- `Path("D:\NOJ\...")` 會被視為相對路徑，反斜線 `\` 是檔案名的一部分
- 實際會在當前目錄下創建一個名為 `D:NOJ...work` 的奇怪目錄結構
- Docker 容器掛載的是正確的目錄 (`D:\NOJ\...`，從 Host 角度），但該目錄內**沒有** `scoring_input.json`
- 評分腳本執行失敗，回報 `FileNotFoundError`

## 3. 測試完整度分析

### 3.1 現有測試 (`test_dispatcher.py`)
```python
# Lines 394-444: test_run_custom_scorer_payload
monkeypatch.setattr(
    "dispatcher.dispatcher.run_custom_scorer",
    lambda **kwargs: {  # ❌ 完全 Mock 掉真實執行
        "status": "OK",
        "score": 77,
        ...
    },
)
```

**問題**：
- 測試完全繞過了 `run_custom_scorer` 和 `CustomScorerRunner.run` 的真實執行
- 路徑處理的邏輯未被執行，無法檢測到檔案寫入錯誤

### 3.2 Custom Checker 的測試對比
```python
# Lines 274-307: test_custom_checker_run
# ✅ 真實執行 Docker 容器
result = run_custom_checker_case(
    checker_path=checker_path,  # 真實路徑
    ...
)
# 實際啟動容器並驗證結果
assert result["status"] == "AC"
```

**差異**：Custom Checker 有真正的整合測試，而 Custom Scorer 只有單元測試 (Mock)。

## 4. 其他審查發現

### 4.1 後端與前端 ✅
- **後端 API**: `late-seconds` API 正確實作
- **資料模型**: `process_result` 正確處理 `scoring` 欄位
- **前端**: 支援上傳 `score.py`

### 4.2 配置
- Docker 映像檔名稱確認：`noj-custom-checker-scorer` (需驗證 `.config/submission.json`)

## 5. 修正建議

### 建議 1: 修改 CustomScorerRunner (推薦)
在 Runner **接收之前**寫入 `scoring_input.json`：
```python
# custom_scorer.py
workdir = scorer_path.parent / "work"
workdir.mkdir(parents=True, exist_ok=True)

# ✅ 在轉換前寫入所有檔案
local_scorer = workdir / "score.py"
shutil.copyfile(scorer_path, local_scorer)
input_file = workdir / "scoring_input.json"  # 新增
input_file.write_text(json.dumps(payload, ensure_ascii=False))  # 新增

translator = PathTranslator()
host_workdir = translator.to_host(workdir)

runner = CustomScorerRunner(..., workdir=str(host_workdir))
result = runner.run()  # 移除 payload 參數
```

相應修改 `CustomScorerRunner.run()` 簽名移除 `payload` 參數，改為直接讀取檔案。

### 建議 2: 新增整合測試
```python
def test_custom_scorer_integration(tmp_path):
    # 真實執行，不使用 Mock
    scorer_path = tmp_path / "score.py"
    scorer_path.write_text("import json\nprint(json.dumps({'score': 50}))")
    
    result = run_custom_scorer(
        scorer_path=scorer_path,
        payload={...},
        ...
    )
    assert result["score"] == 50
```

## 6. 結論
Custom Scorer 的核心邏輯與架構設計**正確**，但在路徑處理上與 Custom Checker 不一致，導致在 WSL 環境中會產生檔案寫入錯誤。修正方式明確且簡單，建議依照「建議 1」修改後進行實際測試驗證。
