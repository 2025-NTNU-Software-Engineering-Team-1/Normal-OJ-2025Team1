# Normal-OJ 資料庫 Schema 文檔

本文檔說明 Normal-OJ 系統的 MongoDB 資料庫結構與 Redis 快取策略。

## 📋 目錄

- [概述](#概述)
- [MongoDB Collections](#mongodb-collections)
  - [User](#user)
  - [Problem](#problem)
  - [Submission](#submission)
  - [Course](#course)
  - [Homework](#homework)
  - [其他 Collections](#其他-collections)
- [Redis 快取](#redis-快取)
- [索引策略](#索引策略)
- [資料遷移](#資料遷移)

---

## 概述

Normal-OJ 使用 **MongoDB** 作為主要資料庫，**Redis** 作為快取層。

### 技術棧

- **MongoDB**: 6.0+
- **Redis**: 7.0+
- **ODM**: MongoEngine

### 連線設定

```python
# mongo/config.py
from mongoengine import connect

connect(
    db='noj',
    host=os.getenv('MONGO_HOST', 'mongodb'),
    port=int(os.getenv('MONGO_PORT', 27017))
)
```

---

## MongoDB Collections

### User

**Collection**: `user`

**用途**: 儲存使用者帳號資訊

**Schema**:
```python
class User(Document):
    username: str  # 唯一，使用者名稱
    password: str  # bcrypt hash
    email: str     # 唯一，Email
    role: int      # 0=Admin, 1=Teacher, 2=Student
    active: bool   # 是否已啟用
    created_at: datetime  # 建立時間
    
    # Profile
    profile: dict  # {
                   #   'displayed_name': str,
                   #   'bio': str,
                   #   'avatar_url': str (optional)
                   # }
    
    # Submissions
    submission_ids: list  # [str], ULID 列表
    
    # Courses (for students)
    courses: list  # [str], 課程名稱列表
    
    # IP Tracking
    login_ips: list  # [{'ip': str, 'timestamp': datetime}]
    
    # Agreement
    has_agreed: bool  # 是否同意使用條款
    
    # MongoDB metadata
    meta = {
        'collection': 'user',
        'indexes': [
            'username',
            'email',
            'role',
            ('active', 'role')
        ]
    }
```

**範例文檔**:
```json
{
  "_id": ObjectId("..."),
  "username": "student01",
  "password": "$2b$12$...",
  "email": "student01@example.com",
  "role": 2,
  "active": true,
  "created_at": ISODate("2023-01-01T00:00:00Z"),
  "profile": {
    "displayed_name": "Student One",
    "bio": "Hello, I'm a student!"
  },
  "submission_ids": ["01HQABC...", "01HQDEF..."],
  "courses": ["Algorithms", "Data Structures"],
  "login_ips": [
    {"ip": "140.113.123.45", "timestamp": ISODate("2023-12-25T10:00:00Z")}
  ],
  "has_agreed": true
}
```

---

### Problem

**Collection**: `problem`

**用途**: 儲存題目資訊

**Schema**:
```python
class Problem(Document):
    problem_id: int  # 唯一，自動遞增
    problem_name: str  # 題目名稱
    description: str   # 題目描述（Markdown）
    tags: list         # [str], 標籤
    
    # Ownership
    owner: str         # 題目擁有者 username
    courses: list      # [str], 所屬課程名稱
    
    # Status
    status: int        # 0=Public, 1=Private, 2=Hidden
    
    # Test Cases
    test_case: dict    # {
                       #   'tasks': [
                       #     {
                       #       'caseCount': int,
                       #       'taskScore': int,
                       #       'memoryLimit': int (KB),
                       #       'timeLimit': int (ms)
                       #     }
                       #   ]
                       # }
    
    # Configuration
    config: dict       # {
                       #   'submissionMode': int (0=CODE, 1=ZIP),
                       #   'executionMode': str ('general'/'functionOnly'/'interactive'),
                       #   'allowedLanguage': [int],
                       #   'canViewStdout': bool,
                       #   'staticAnalysis': {...},
                       #   'networkAccessRestriction': {...},
                       #   'artifactCollection': {...}
                       # }
    
    # Assets (MinIO paths)
    asset_paths: dict  # {
                       #   'testdata': str,
                       #   'makefile': str,
                       #   'teacher_file': str,
                       #   'checker': str,
                       #   'scoring_script': str,
                       #   'local_service': str
                       # }
    
    # Statistics
    ac_user: int       # AC 的使用者數
    submitter: int     # 提交過的使用者數
    
    # Timestamps
    created_at: datetime
    updated_at: datetime
    
    # Homework (optional)
    homework: str      # 所屬作業 ID（如果是作業題目）
    
    meta = {
        'collection': 'problem',
        'indexes': [
            'problem_id',
            'owner',
            'courses',
            ('status', 'courses'),
            'tags'
        ]
    }
```

**範例文檔**:
```json
{
  "_id": ObjectId("..."),
  "problem_id": 123,
  "problem_name": "A+B Problem",
  "description": "# Description\nGiven two integers...",
  "tags": ["basic", "math"],
  "owner": "teacher01",
  "courses": ["Algorithms"],
  "status": 0,
  "test_case": {
    "tasks": [
      {
        "caseCount": 10,
        "taskScore": 100,
        "memoryLimit": 65536,
        "timeLimit": 1000
      }
    ]
  },
  "config": {
    "submissionMode": 0,
    "executionMode": "general",
    "allowedLanguage": [0, 1, 2],
    "canViewStdout": true
  },
  "asset_paths": {
    "testdata": "problems/123/testdata.zip"
  },
  "ac_user": 45,
  "submitter": 60,
  "created_at": ISODate("2023-01-01T00:00:00Z"),
  "updated_at": ISODate("2023-12-25T00:00:00Z")
}
```

---

### Submission

**Collection**: `submission`

**用途**: 儲存提交記錄

**Schema**:
```python
class Submission(Document):
    submission_id: str  # ULID，唯一
    problem_id: int     # 題目 ID
    user_id: str        # 提交者 username
    language_type: int  # 0=C, 1=C++, 2=Python
    
    # Code
    main_code_path: str  # MinIO 路徑
    
    # Status
    status: int  # 0=AC, 1=WA, 2=RE, 3=TLE, 4=MLE, 5=CE, 6=JE, 7=OLE
    score: int   # 總分
    
    # Results
    tasks: list  # [
                 #   {
                 #     'taskIndex': int,
                 #     'taskScore': int,
                 #     'status': int,
                 #     'cases': [
                 #       {
                 #         'caseIndex': int,
                 #         'status': int,
                 #         'runTime': int,
                 #         'memoryUsage': int,
                 #         'exitCode': int
                 #       }
                 #     ]
                 #   }
                 # ]
    
    # Static Analysis
    sa_status: str   # 'success', 'failure', 'skip'
    sa_message: str  # 分析訊息
    sa_report: str   # 分析報告內容
    sa_report_path: str  # MinIO 報告路徑
    
    # Teacher feedback
    comment: str     # 教師評語
    grade: int       # 手動評分（覆寫 score）
    
    # Timestamps
    timestamp: datetime  # 提交時間
    judge_timestamp: datetime  # 評測完成時間
    
    # Metadata
    ip_addr: str     # 提交 IP
    course: str      # 所屬課程
    
    meta = {
        'collection': 'submission',
        'indexes': [
            'submission_id',
            'user_id',
            'problem_id',
            ('problem_id', '-timestamp'),
            ('user_id', '-timestamp'),
            ('status', 'problem_id')
        ]
    }
```

**範例文檔**:
```json
{
  "_id": ObjectId("..."),
  "submission_id": "01HQABCDEF123456789",
  "problem_id": 123,
  "user_id": "student01",
  "language_type": 1,
  "main_code_path": "submissions/01HQABC.../main.cpp",
  "status": 0,
  "score": 100,
  "tasks": [
    {
      "taskIndex": 0,
      "taskScore": 100,
      "status": 0,
      "cases": [
        {
          "caseIndex": 0,
          "status": 0,
          "runTime": 15,
          "memoryUsage": 2048,
          "exitCode": 0
        }
      ]
    }
  ],
  "sa_status": "success",
  "sa_message": "No violations found",
  "timestamp": ISODate("2023-12-25T10:00:00Z"),
  "judge_timestamp": ISODate("2023-12-25T10:00:15Z"),
  "ip_addr": "140.113.123.45",
  "course": "Algorithms"
}
```

---

### Course

**Collection**: `course`

**用途**: 儲存課程資訊

**Schema**:
```python
class Course(Document):
    course_name: str  # 唯一，課程名稱
    teacher: str      # 授課教師 username
    
    # Students
    students: list    # [str], 學生 username 列表
    
    # Teaching Assistants
    tas: list         # [str], 助教 username 列表
    
    # Settings
    is_public: bool   # 是否公開
    
    # Timestamps
    created_at: datetime
    
    meta = {
        'collection': 'course',
        'indexes': [
            'course_name',
            'teacher',
            'students'
        ]
    }
```

---

### Homework

**Collection**: `homework`

**用途**: 儲存作業資訊

**Schema**:
```python
class Homework(Document):
    homework_name: str  # 作業名稱
    course: str         # 所屬課程
    
    # Problems
    problem_ids: list   # [int], 題目 ID 列表
    
    # Deadline
    start_time: datetime
    end_time: datetime
    
    # Scoring
    scoreboard_visible: bool  # 排行榜是否可見
    
    meta = {
        'collection': 'homework',
        'indexes': [
            'course',
            ('course', 'end_time')
        ]
    }
```

---

### 其他 Collections

#### Announcement

```python
class Announcement(Document):
    title: str
    content: str
    pinned: bool
    course: str  # 所屬課程（空字串表示全站公告）
    created_at: datetime
```

#### Post

```python
class Post(Document):
    title: str
    content: str
    author: str
    problem_id: int  # 相關題目
    course: str
    created_at: datetime
    comments: list  # [{'author': str, 'content': str, 'timestamp': datetime}]
```

#### PersonalAccessToken (PAT)

```python
class PersonalAccessToken(Document):
    token: str        # 唯一，Token 字串
    user: str         # 擁有者 username
    description: str  # Token 說明
    scopes: list      # [str], 權限範圍
    
    # Expiration
    created_at: datetime
    expires_at: datetime  # null 表示永不過期
    
    # Status
    is_revoked: bool
    last_used: datetime
```

---

## Redis 快取

### 用途

1. **JWT Token 黑名單** - 撤銷的 Token
2. **Sandbox Token** - 提交評測的臨時 Token
3. **Session 管理** - 使用者會話
4. **Rate Limiting** - API 速率限制

### 鍵值結構

#### Sandbox Token

```
Key: submission:token:{submission_id}
Value: {token_string}
TTL: 3600 seconds (1 hour)
```

**用途**: 驗證 Sandbox 回報結果的合法性

**流程**:
1. Backend 送交 Submission 時生成隨機 token 並存入 Redis
2. Sandbox 完成後攜帶該 token 呼叫 `/submission/<id>/complete`
3. Backend 驗證 token 後刪除

#### JWT Blacklist (未來實作)

```
Key: jwt:blacklist:{token_hash}
Value: 1
TTL: {token_expiration_time}
```

**用途**: 撤銷已發出的 JWT Token

#### Rate Limiting

```
Key: ratelimit:{endpoint}:{user_id}
Value: {request_count}
TTL: 60 seconds
```

**用途**: 限制 API 請求頻率

---

## 索引策略

### User Collection

```python
db.user.createIndex({"username": 1}, {unique: true})
db.user.createIndex({"email": 1}, {unique: true})
db.user.createIndex({"role": 1})
db.user.createIndex({"active": 1, "role": 1})
```

**查詢優化**:
- 登入查詢: `username` 索引
- Email 驗證: `email` 索引
- 角色篩選: `role` 索引

### Problem Collection

```python
db.problem.createIndex({"problem_id": 1}, {unique: true})
db.problem.createIndex({"owner": 1})
db.problem.createIndex({"courses": 1})
db.problem.createIndex({"status": 1, "courses": 1})
db.problem.createIndex({"tags": 1})
```

**查詢優化**:
- 題目詳情: `problem_id` 索引
- 課程題目列表: `(status, courses)` 複合索引
- 標籤搜尋: `tags` 索引

### Submission Collection

```python
db.submission.createIndex({"submission_id": 1}, {unique: true})
db.submission.createIndex({"user_id": 1, "timestamp": -1})
db.submission.createIndex({"problem_id": 1, "timestamp": -1})
db.submission.createIndex({"status": 1, "problem_id": 1})
```

**查詢優化**:
- 使用者提交歷史: `(user_id, -timestamp)` 複合索引
- 題目提交列表: `(problem_id, -timestamp)` 複合索引
- AC 統計: `(status, problem_id)` 複合索引

### Course Collection

```python
db.course.createIndex({"course_name": 1}, {unique: true})
db.course.createIndex({"teacher": 1})
db.course.createIndex({"students": 1})
```

---

## 資料遷移

### 遷移腳本位置

```
Back-End/migrations/
├── migrate.py          # 主要遷移腳本
├── 001_add_config.py   # 範例：新增 config 欄位
└── 002_update_schema.py
```

### 執行遷移

```bash
# 在 Docker 容器內執行
docker compose exec backend python migrations/migrate.py

# 或本地執行
cd Back-End
poetry run python migrations/migrate.py
```

### 遷移範例

**migrations/001_add_config.py**:
```python
from mongo import Problem

def migrate():
    """為所有題目新增 config 欄位"""
    problems = Problem.objects()
    
    for problem in problems:
        if not problem.config:
            problem.update(config={
                'submissionMode': 0,
                'executionMode': 'general',
                'allowedLanguage': [0, 1, 2],
                'canViewStdout': True
            })
    
    print(f"Migrated {problems.count()} problems")

if __name__ == '__main__':
    migrate()
```

---

## 備份與復原

### 備份

```bash
# 備份整個資料庫
docker compose exec mongodb mongodump --out /backup/$(date +%Y%m%d)

# 備份特定 collection
docker compose exec mongodb mongodump --collection=user --out /backup/user

# 複製到 Host
docker cp mongodb:/backup ./mongodb-backup
```

### 復原

```bash
# 復原整個資料庫
docker compose exec mongodb mongorestore /backup/20231225

# 復原特定 collection
docker compose exec mongodb mongorestore --collection=user /backup/user
```

---

## 效能建議

### 查詢優化

1. **使用索引**: 確保常用查詢有對應索引
2. **限制回傳欄位**: 使用 `only()` 只取需要的欄位
3. **分頁查詢**: 使用 `skip()` 和 `limit()` 分頁
4. **避免 N+1 查詢**: 使用 `select_related()`

### 範例

```python
# Good: 使用索引 + 限制欄位
submissions = Submission.objects(
    user_id='student01'
).only(
    'submission_id', 'status', 'score', 'timestamp'
).order_by(
    '-timestamp'
).limit(20)

# Bad: 全欄位 + 無索引排序
submissions = Submission.objects().order_by('-created_at')
```

---

## 相關文檔

- [API_REFERENCE.md](API_REFERENCE.md) - API 參考
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - 部署指南
- [ARCHITECTURE.md](ARCHITECTURE.md) - 系統架構

---

**最後更新：** 2025-11-29  
**維護者：** 2025 NTNU Software Engineering Team 1
