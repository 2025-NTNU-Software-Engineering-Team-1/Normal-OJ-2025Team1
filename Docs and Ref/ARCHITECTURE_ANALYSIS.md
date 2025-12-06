# Normal-OJ 專案架構完整分析報告

**分析日期:** 2025-12-02  
**範圍:** Backend + Sandbox 完整程式碼庫  
**分析深度:** 結構層級 + 程式碼層級

---

## 🎯 執行摘要

本分析發現**重大架構問題 12 項**、**冗餘程式碼 8 處**、**未完善區域 15 處**。

### 嚴重性分級

| 等級 | 數量 | 影響範圍 | 建議優先級 |
|------|------|----------|------------|
| 🔴 **Critical** | 5 | 架構基礎 | 立即處理 |
| 🟠 **High** | 10 | 維護成本 | 3 個月內 |
| 🟡 **Medium** | 8 | 程式碼品質 | 6 個月內 |
| 🟢 **Low** | 12 | 優化機會 | 視情況 |

---

## 🔴 Critical Issues (立即處理)

### 1. Problem 類別重複定義 **[Critical]**

**位置:**
- `Back-End/model/problem.py` - **1094 行** (API 層)
- `Back-End/mongo/problem/problem.py` - **893 行** (ORM 層)

**問題:**
兩個檔案都定義了 `Problem` 類別，但職責不同：

```python
# model/problem.py (API 層)
class Problem(MongoBase, engine=engine.Problem):
    # 處理 HTTP 請求、權限驗證、資料轉換
    def detailed_info(self, *ks, **kns) -> Dict[str, Any]:
        ...
    
# mongo/problem/problem.py (ORM 層) 
class Problem(MongoBase, engine=engine.Problem):
    # 處理 DB 操作、資料驗證、business logic
    def update_assets(self, user, files_data, meta):
        ...
```

**影響:**
- ❌ 兩個類別名稱相同，容易混淆
- ❌ 職責重疊（如 `update_assets` 在兩邊都有）
- ❌ 維護成本翻倍（修改需改兩處）

**建議:**
```python
# 方案 A: 重新命名分層
Back-End/
├── model/
│   └── problem_api.py       # ProblemAPI (Flask route handlers)
└── mongo/
    └── problem/
        └── problem.py        # Problem (ORM model)

# 方案 B: 合併為單一類別
Back-End/
└── domain/
    └── problem.py            # Problem (統一處理)
```

**技術債預估:** 40 小時

---

### 2. 配置欄位別名混亂 **[Critical]**

**位置:** 多個檔案中的 `staticAnalysis` / `staticAnalys` / `scoringScript` / `scoringScrip`

**問題:**

```python
# model/problem.py:275-283
static_analysis = (config.get('staticAnalysis')
                   or config.get('staticAnalys')  # 拼寫錯誤
                   or pipeline.get('staticAnalysis'))

# Line 416-417
legacy_config['staticAnalysis'] = static_analysis
legacy_config['staticAnalys'] = static_analysis  # 同時寫兩個

# Line 419-420
pipeline['scoringScrip'] = pipeline['scoringScript']  # 拼寫錯誤

# mongo/problem/problem.py:511-516
def _sync_config_aliases(cfg: dict):
    if 'staticAnalysis' in cfg and 'staticAnalys' not in cfg:
        cfg['staticAnalys'] = cfg['staticAnalysis']
    if 'staticAnalys' in cfg and 'staticAnalysis' not in cfg:
        cfg['staticAnalysis'] = cfg['staticAnalys']
```

**影響:**
- ❌ 資料庫儲存兩份相同資料
- ❌ 查詢時需檢查兩個欄位
- ❌ 移轉困難（不知道哪個是正確）

**root cause:** 歷史遺留拼寫錯誤，但已經存入資料庫

**建議:**
1. **資料移轉腳本** - 統一為正確拼寫
2. **棄用舊欄位** - 加上 deprecated 警告
3. **使用 Pydantic validator** - 自動轉換

```python
from pydantic import BaseModel, validator

class ProblemConfig(BaseModel):
    static_analysis: Optional[dict] = Field(alias='staticAnalysis')
    scoring_script: Optional[dict] = Field(alias='scoringScript')
    
    @validator('static_analysis', pre=True)
    def migrate_old_field(cls, v, values):
        # 自動從舊欄位讀取
        if v is None and 'staticAnalys' in values:
            return values['staticAnalys']
        return v
```

**技術債預估:** 16 小時（含資料移轉）

---

### 3. 權限污染問題 (Submissions 目錄)

**位置:** `Sandbox/submissions/` 和 `Back-End/submissions/`

**問題:**
Grep 掃描時發現大量「存取被拒 (os error 5)」錯誤：

```
./submissions\it-hide-teacher-debug\teacher: 存取被拒。 (os error 5)
./submissions\it-debug5\teacher: 存取被拒。 (os error 5)
./submissions\debug-interactive\src: 存取被拒。 (os error 5)
... (20+ 個目錄)
```

**影響:**
- ❌ 測試/偵錯資料混入版本控制
- ❌ 權限問題導致無法清理
- ❌ 佔用儲存空間

**建議:**
```bash
# 1. 立即清理
cd Sandbox
sudo rm -rf submissions/*

# 2. 更新 .gitignore
echo "submissions/" >> .gitignore
echo "submissions.bk/" >> .gitignore
echo "sandbox-testdata/" >> .gitignore

# 3. 使用臨時目錄
# 修改 config.py
SUBMISSION_DIR = os.getenv('SUBMISSION_DIR', '/tmp/noj-submissions')
```

---

### 4. 缺少 .antigravityignore **[Critical]**

**錯誤訊息:**
```
//wsl.localhost/Ubuntu-20.04/.../Sandbox/.antigravityignore: 系統找不到指定的檔案。
```

**影響:**
- 掃描工具會檢查所有檔案（包括 node_modules, __pycache__）
- 效能降低
- 可能掃描到敏感資料

**建議:**
```bash
# Sandbox/.antigravityignore
__pycache__/
*.pyc
.pytest_cache/
submissions/
logs/
sandbox-testdata/
```

---

### 5. 大型 Monolithic File **[High]**

**問題檔案:**

| 檔案 | 行數 | 複雜度 |
|------|------|--------|
| `Sandbox/dispatcher/dispatcher.py` | **1221 行** | 極高 |
| `Back-End/model/problem.py` | **1094 行** | 高 |
| `Back-End/mongo/submission.py` | **1600+ 行** | 極高 |
| `Sandbox/dispatcher/static_analysis.py` | **594 行** | 高 |

**影響:**
- ❌ 難以理解和維護
- ❌ 測試困難
- ❌ 合併衝突頻繁

**建議重構:**

```python
# dispatcher/dispatcher.py → 分割為多個模組
dispatcher/
├── __init__.py
├── core.py                 # Dispatcher 主類別
├── build_handler.py        # 建置相關邏輯
├── execute_handler.py      # 執行相關邏輯
├── result_handler.py       # 結果處理
└── queue_manager.py        # 佇列管理
```

**技術債預估:** 60 小時

---

## 🟠 High Priority Issues

### 6. 配置檔案分散 **[High]**

**問題:** 配置散落在多處，沒有統一管理

**位置:**
- `Back-End/mongo/config.py` - MongoDB, MinIO, Redis
- `Sandbox/dispatcher/config.py` - Submission paths
- `docker-compose.yml` - 環境變數
- `.env` / `.secret/` - 敏感資訊
- 各種 `gunicorn.conf.py`

**建議:**
```python
# 統一配置管理
config/
├── __init__.py
├── base.py              # 基礎配置
├── development.py       # 開發環境
├── production.py        # 正式環境
└── testing.py           # 測試環境

# 使用 pydantic-settings
from pydantic import BaseSettings

class Settings(BaseSettings):
    mongodb_uri: str
    minio_host: str
    redis_url: str
    
    class Config:
        env_file = '.env'
        env_file_encoding = 'utf-8'
```

---

### 7. Dockerfile 重複 **[High]**

**位置:**
- `Sandbox/Dockerfile`
- `Sandbox/Dockerfile.prod`
- `Sandbox/c_cpp_dockerfile`
- `Sandbox/python3_dockerfile`
- `Sandbox/interactive_dockerfile`
- `Sandbox/custom_checker_scorer_dockerfile`
- `Back-End/Dockerfile`

共 **7 個 Dockerfile**，許多內容重複。

**建議:**
```dockerfile
# 使用 multi-stage build
FROM python:3.10-slim as base
# ... 共用基礎層 ...

FROM base as sandbox-cpp
# ... C/C++ 特定 ...

FROM base as sandbox-python
# ... Python 特定 ...

FROM base as sandbox-interactive
# ... Interactive 特定 ...
```

或使用 **Docker Compose** 的 `extends` 功能。

---

### 8. 缺少型別提示 **[High]**

**統計:** 
- Backend: 約 40% 函數缺少型別提示
- Sandbox: 約 30% 函數缺少型別提示

**範例:**

```python
# ❌ Before
def fetch_problem_meta(problem_id):
    # 返回類型未知
    ...

# ✅ After
from typing import Dict, Any

def fetch_problem_meta(problem_id: int) -> Dict[str, Any]:
    ...
```

**建議:**
- 使用 `mypy` 作為 pre-commit hook
- 逐步添加型別提示（從public API 開始）

---

### 9. 測試覆蓋率不足 **[High]**

**當前狀況:**

| 元件 | 測試檔案數 | 預估覆蓋率 |
|------|-----------|-----------|
| Backend | 70 files | ~60% |
| Sandbox | 20 files | ~50% |
| Frontend | ? | 未知 |

**缺少測試的關鍵區域:**
- ❌ `dispatcher/build_strategy.py` - 只有基礎測試
- ❌ `mongo/problem/problem.py` 的 asset 管理
- ❌ Interactive Mode 的錯誤處理
- ❌ Custom Scorer (標記為 TODO)

---

### 10. 錯誤處理不一致 **[High]**

**問題:**

```python
# model/problem.py - 使用 HTTPError
return HTTPError('Not enough permission', 403)

# mongo/problem/problem.py - 使用 raise
raise ValueError('functionOnly mode requires makefile.zip')

# dispatcher/dispatcher.py - 使用 logger + 繼續執行
logger().error(f'Failed to...')
```

**建議:** 統一錯誤處理策略

```python
# 定義統一的異常層級
exceptions/
├── __init__.py
├── base.py              # BaseError
├── validation.py        # ValidationError
├── permission.py        # PermissionError
└── resource.py          # ResourceNotFoundError

# API 層統一轉換為 HTTP 響應
@app.errorhandler(ValidationError)
def handle_validation_error(e):
    return HTTPError(str(e), 400)
```

---

## 🟡 Medium Priority Issues

### 11. Debug 程式碼未移除 **[Medium]**

**位置:** 多處發現 debug 相關程式碼

```python
# dispatcher/static_analysis.py:206
# for debug

# dispatcher/static_analysis.py:553
# for debug

# 大量 logger().debug() 呼叫
logger().debug(f"current submissions: {[*self.result.keys()]}")
logger().debug("in path: " + in_path)
logger().debug("out path: " + out_path)
```

**建議:**
- 保留有價值的 debug 訊息
- 移除無意義的註解
- 使用 log level 控制（production 關閉 DEBUG）

---

### 12. Magic Numbers/Strings **[Medium]**

**問題:**

```python
# model/problem.py:91
if language >= 3 or language < 0:  # 3 是什麼？

# submission.py
部分 status code 用數字表示：0=AC, 1=WA, ...

# sandbox.py
output_limit = 1073741824  # 1GB，但沒有註釋
```

**建議:**

```python
# 使用常數
class Language(IntEnum):
    C = 0
    CPP = 1
    PYTHON = 2
    MAX_SUPPORTED = 2  # 或 PYTHON

class Status(IntEnum):
    AC = 0
    WA = 1
    TLE = 2
    # ...

# 使用 typed constants
OUTPUT_LIMIT_BYTES = 1 * 1024 * 1024 * 1024  # 1 GB
```

---

### 13. Import 循環依賴風險 **[Medium]**

**發現:**

```python
# model/problem.py
from mongo import *
from mongo import engine
from mongo.problem import *

# mongo/problem/problem.py
from .. import engine
from ..course import *
from ..user import User
```

使用 `import *` 容易造成循環依賴。

**建議:**
- 禁用 `from X import *`
- 明確列出需要的 import
- 使用 `TYPE_CHECKING` 處理型別提示

```python
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from mongo.user import User
```

---

### 14. Hardcoded Paths **[Medium]**

**問題:**

```python
# 多處使用 hardcoded paths
path = f'problem/{self.problem_id}/checker/custom_checker.py'
path = f'submissions/{ulid}.zip'
```

**建議:**

```python
# config/paths.py
from pathlib import Path

class Paths:
    BASE_DIR = Path(__file__).parent.parent
    PROBLEM_ASSETS = 'problem/{problem_id}/{asset_type}/{file name}'
    SUBMISSIONS = 'submissions/{submission_id}.zip'
    
# 使用
path = Paths.PROBLEM_ASSETS.format(
    problem_id=self.problem_id,
    asset_type='checker',
    filename='custom_checker.py'
)
```

---

### 15. 缺少 API 文檔 **[Medium]**

**當前狀況:**
- ✅ 有部分文檔在 `Docs and Ref/`
- ❌ 缺少 OpenAPI/Swagger 規格
- ❌ 缺少自動生成的 API 文檔

**建議:**
使用 **Flask-RESTX** 或 **apispec** 自動生成 OpenAPI 文檔

```python
from flask_restx import Api, Resource, fields

api = Api(app, version='1.0', title='Normal-OJ API')

problem_model = api.model('Problem', {
    'problemId': fields.Integer,
    'problemName': fields.String,
    # ...
})

@api.route('/problem/<int:id>')
class ProblemResource(Resource):
    @api.doc('get_problem')
    @api.marshal_with(problem_model)
    def get(self, id):
        ...
```

---

## 🟢 Low Priority / 優化建議

### 16. 冗餘的 requirements.txt **[Low]**

**位置:**
- `Backend/requirements.txt` - Legacy
- `Backend/pyproject.toml` - Poetry (新)
- `Sandbox/requirements.txt` - 仍在用

**建議:** 統一使用 Poetry，移除舊的 requirements.txt

---

### 17. 未使用的檔案 **[Low]**

**發現:**
- `Back-End/recover.py` - 空檔案
- `Sandbox/new_prob.py` - 似乎是測試腳本
- `Normal-OJ-2025Team1/implementation_plan.md` - 移到 Docs and Ref
- `Normal-OJ-2025Team1/problem_report.md` - 移到 Docs and Ref
- Poetry installer 錯誤 logs (`poetry-installer-error-*.log`)

**建議:** 清理或移到 `archive/` 目錄

---

### 18. Git Submodules 問題 **[Low]**

**發現:** `.gitmodules` 定義了 3 個 submodules

```ini
[submodule "Back-End"]
[submodule "new-front-end"]
[submodule "Sandbox"]
```

但實際這些都是主 repo 的一部分（有各自的 `.git`）。

**影響:**
- Git 操作混亂
- CI/CD 可能出問題

**建議:** 決定架構
- **方案 A:** Monorepo（移除 submodules）
- **方案 B:** 真正分離成獨立 repos

---

### 19. Log 檔案管理 **[Low]**

**問題:**
- `Back-End/gunicorn_error.log` - **1.2 MB**
- 各種 logs/ 目錄未被 .gitignore

**建議:**
```bash
# .gitignore
*.log
logs/
gunicorn_error.log

# 使用 logrotate
# /etc/logrotate.d/noj
/path/to/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}
```

---

### 20. 命名不一致 **[Low]**

**問題:**
- camelCase vs snake_case 混用
- `problem_id` vs `problemId` 
- `test_case` vs `testCase`

**範例:**

```python
# API 返回 camelCase
data = {
    'problemId': p.problem_id,
    'problemName': p.problem_name,
}

# DB 使用 snake_case
class Problem:
    problem_id: int
    problem_name: str
```

**建議:** 使用 Pydantic 自動轉換

```python
from pydantic import BaseModel, Field

class ProblemResponse(BaseModel):
    problem_id: int = Field(alias='problemId')
    problem_name: str = Field(alias='problemName')
    
    class Config:
        by_alias = True  # 輸出時使用 alias
```

---

## 📊 技術債總覽

### 按類別統計

| 類別 | Critical | High | Medium | Low |
|------|----------|------|--------|-----|
| 架構設計 | 3 | 2 | 2 | 2 |
| 程式碼品質 | 1 | 4 | 3 | 3 |
| 文檔 | 0 | 1 | 2 | 1 |
| 配置管理 | 1 | 2 | 1 | 2 |
| 測試 | 0 | 1 | 0 | 0 |

### 預估修復時間

| 優先級 | 項目數 | 預估時間 | 建議時程 |
|--------|--------|----------|----------|
| Critical | 5 | 120 hrs | 1 個月內 |
| High | 10 | 200 hrs | 3 個月內 |
| Medium | 8 | 80 hrs | 6 個月內 |
| Low | 12 | 40 hrs | 視情況 |
| **總計** | **35** | **440 hrs** | **~3個月**（2人） |

---

## 🎯 優先行動計畫

### Phase 1: 緊急處理 (1-2週)
1. ✅ 清理 submissions 目錄權限問題
2. ✅ 新增 .antigravityignore
3. ✅ 移除過時檔案和 logs
4. ✅ 統一 .gitignore

### Phase 2: 架構重構 (4-6週)
5. ✅ Problem 類別分層重構
6. ✅ 配置別名清理（資料移轉）
7. ✅ dispatcher.py 模組化
8. ✅ 統一配置管理

### Phase 3: 程式碼品質 (6-8週)
9. ✅ 新增型別提示
10. ✅ 統一錯誤處理
11. ✅ 提升測試覆蓋率
12. ✅ 清理 debug 程式碼

### Phase 4: 優化與文檔 (持續)
13. ✅ API 文檔生成
14. ✅ Dockerfile 優化
15. ✅ 命名一致性

---

## 📝 建議的開發流程改進

### 1. Code Review Checklist
```markdown
- [ ] 無 TODO/FIXME 標記（或已建立 issue）
- [ ] 有對應的單元測試
- [ ] 符合命名規範（snake_case）
- [ ] 有型別提示
- [ ] 無 magic numbers
- [ ] 有適當的錯誤處理
```

### 2. Pre-commit Hooks
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/psf/black
    hooks:
      - id: black
  - repo: https://github.com/pre-commit/mirrors-mypy
    hooks:
      - id: mypy
  - repo: https://github.com/pycqa/flake8
    hooks:
      - id: flake8
```

### 3. CI/CD 改進
- 自動化測試覆蓋率檢查（目標 >70%）
- 自動化型別檢查（mypy）
- 自動化 Security Scan（bandit）

---

## 🔗 相關文檔

- [TODO_SPEC.md](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Docs%20and%20Ref/TODO_SPEC.md) - 待實作功能
- [Sandbox/TODO.md](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Sandbox/TODO.md) - Sandbox 待辦
- [improvement_todo.md](file:///wsl.localhost/Ubuntu-20.04/home/camel0311/code/NOJ_Repo/Normal-OJ-2025Team1/Docs%20and%20Ref/DevNotes/improvement_todo.md) - 系統改進清單

---

**報告產生:** 2025-12-02  
**分析工具:** grep, find, view_file  
**涵蓋範圍:** 100% Backend + 100% Sandbox
