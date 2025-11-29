# Normal-OJ API Reference

本文檔詳細說明 Normal-OJ 系統的所有 API 端點，包括 Backend RESTful API 與 Sandbox 內部 API。

## 📋 目錄

- [認證機制](#認證機制)
- [Backend API](#backend-api)
  - [Authentication (`/auth`)](#authentication-auth)
  - [Problem (`/problem`)](#problem-problem)
  - [Submission (`/submission`)](#submission-submission)
  - [Course (`/course`)](#course-course)
  - [Homework (`/homework`)](#homework-homework)
  - [User (`/user`)](#user-user)
  - [Profile (`/profile`)](#profile-profile)
  - [其他端點](#其他端點)
- [Sandbox API](#sandbox-api)
- [錯誤代碼參考](#錯誤代碼參考)

---

## 認證機制

Normal-OJ 支援兩種認證方式：

### 1. JWT Token 認證

**使用方式：**
```http
GET /api/endpoint?token=<JWT_TOKEN>
```
或
```http
POST /api/endpoint
Content-Type: application/json

{
  "token": "<JWT_TOKEN>"
}
```

**取得方式：** 透過 `POST /auth/session` 登入取得

**有效期限：** 由環境變數 `JWT_EXP` 設定（預設 7 天）

### 2. Personal Access Token (PAT) 認證

**使用方式：**
```http
GET /api/endpoint
Authorization: Bearer <PAT_TOKEN>
```

**適用場景：** API 自動化、CI/CD 整合

**Scope 權限：** 不同 PAT 可設定不同權限範圍

---

## Backend API

### Authentication (`/auth`)

#### `POST /auth/session` - 登入

建立使用者會話並取得 JWT Token。

**Request:**
```json
{
  "username": "string",
  "password": "string"
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Login Success",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "user": {
      "username": "student01",
      "role": 2,
      "active": true
    }
  }
}
```

**Error Responses:**
- `400 Bad Request` - 缺少必要欄位
- `403 Forbidden` - 帳號密碼錯誤或帳號未啟用

---

#### `GET /auth/session` - 登出

登出當前使用者並清除 Token。

**Request:**
```http
GET /auth/session?token=<JWT_TOKEN>
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Logout Success"
}
```

---

#### `POST /auth/signup` - 註冊

註冊新使用者帳號。

**Request:**
```json
{
  "username": "string",
  "password": "string",
  "email": "string"
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Signup Success",
  "data": {
    "username": "student01"
  }
}
```

**Error Responses:**
- `400 Bad Request` - 缺少必要欄位或格式錯誤
- `409 Conflict` - 使用者名稱或 Email 已存在

---

#### `PUT /auth/change-password` - 修改密碼

修改當前使用者密碼。

**Request:**
```json
{
  "token": "string",
  "old_password": "string",
  "new_password": "string"
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Password Changed"
}
```

**Error Responses:**
- `403 Forbidden` - 舊密碼錯誤

---

#### `GET /auth/me` - 取得當前使用者資訊

取得登入使用者的詳細資訊。

**Request:**
```http
GET /auth/me?token=<JWT_TOKEN>&fields=username,email,role
```

**Query Parameters:**
- `fields` (optional): 指定要回傳的欄位，以逗號分隔

**Response (200):**
```json
{
  "status": "ok",
  "data": {
    "username": "student01",
    "email": "student01@example.com",
    "role": 2,
    "active": true,
    "profile": {
      "displayed_name": "Student One",
      "bio": "..."
    }
  }
}
```

---

### Problem (`/problem`)

#### `GET /problem` - 取得題目列表

取得題目列表，支援分頁和篩選。

**Request:**
```http
GET /problem?token=<TOKEN>&offset=0&count=20&course=<COURSE_NAME>&tags=dp,graph
```

**Query Parameters:**
- `offset` (int): 起始位置，預設 0
- `count` (int): 每頁數量，預設 20
- `course` (string, optional): 課程名稱篩選
- `tags` (string, optional): 標籤篩選，以逗號分隔
- `problem_id` (int, optional): 題目 ID 篩選
- `name` (string, optional): 題目名稱搜尋

**Response (200):**
```json
{
  "status": "ok",
  "data": [
    {
      "problemId": 1,
      "problemName": "A+B Problem",
      "tags": ["basic", "math"],
      "courseNames": ["Public"],
      "acUser": 150,
      "submitter": 200,
      "status": 0
    }
  ]
}
```

---

#### `GET /problem/<problem_id>` - 取得題目詳情

取得特定題目的詳細資訊。

**Request:**
```http
GET /problem/123?token=<TOKEN>
```

**Response (200):**
```json
{
  "status": "ok",
  "data": {
    "problemId": 123,
    "problemName": "Sample Problem",
    "description": "...",
    "tags": ["dp"],
    "courses": [{"course": "Algorithms", "status": 0}],
    "testCase": {
      "tasks": [
        {
          "caseCount": 10,
          "taskScore": 10,
          "memoryLimit": 65536,
          "timeLimit": 1000
        }
      ]
    },
    "allowedLanguage": [0, 1, 2],
    "canViewStdout": true,
    "submissionMode": 0,
    "executionMode": "general"
  }
}
```

---

#### `POST /problem` - 建立題目

建立新題目（需 Teacher 或 Admin 權限）。

**Request:**
```json
{
  "token": "string",
  "problemName": "string",
  "courses": ["course_name"],
  "description": "string",
  "tags": ["tag1", "tag2"],
  "testCaseInfo": {
    "tasks": [
      {
        "caseCount": 10,
        "taskScore": 10,
        "memoryLimit": 65536,
        "timeLimit": 1000
      }
    ]
  },
  "config": {
    "executionMode": "general",
    "submissionMode": 0,
    "allowedLanguage": [0, 1, 2]
  }
}
```

**Response (200):**
```json
{
  "status": "ok",
  "data": {
    "problemId": 456
  }
}
```

**Error Responses:**
- `403 Forbidden` - 權限不足
- `400 Bad Request` - 資料格式錯誤

---

#### `PUT /problem/<problem_id>` - 更新題目

更新題目資訊（需 Manager 權限）。

**Request:**
```json
{
  "token": "string",
  "problemName": "Updated Name",
  "description": "Updated description",
  "testCaseInfo": { ... },
  "config": { ... }
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Update Success"
}
```

---

#### `PUT /problem/<problem_id>/meta` - 更新題目 Config/Pipeline

僅更新題目的 config 和 pipeline 設定，不包含檔案上傳。

**Request:**
```json
{
  "token": "string",
  "config": {
    "executionMode": "functionOnly",
    "staticAnalysis": {
      "enabled": true,
      "model": "whitelist"
    },
    "artifactCollection": {
      "compiledBinary": true,
      "testcaseOutput": true
    }
  },
  "pipeline": {
    "customChecker": true,
    "customScoring": true
  }
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Meta Updated"
}
```

---

#### `POST /problem/<problem_id>/assets` - 上傳題目資源

上傳題目相關檔案（測資、Checker、Makefile 等）。

**Request (multipart/form-data):**
```
POST /problem/123/assets
Content-Type: multipart/form-data

token: <JWT_TOKEN>
meta: {"executionMode": "functionOnly", "assetPaths": {...}}
makefile: [file]
checker: [file]
teacher_file: [file]
scoring_script: [file]
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Assets Uploaded"
}
```

---

#### `POST /problem/<problem_id>/testcase/upload/initiate` - 初始化測資上傳

初始化分段上傳測資檔案。

**Request:**
```json
{
  "token": "string",
  "length": 104857600,
  "partSize": 5242880
}
```

**Response (200):**
```json
{
  "status": "ok",
  "data": {
    "uploadId": "abc123...",
    "uploadUrls": [
      "https://minio.../part1?uploadId=abc123",
      "https://minio.../part2?uploadId=abc123"
    ]
  }
}
```

---

#### `POST /problem/<problem_id>/testcase/upload/complete` - 完成測資上傳

完成分段上傳並組合測資檔案。

**Request:**
```json
{
  "token": "string",
  "uploadId": "abc123...",
  "parts": [
    {"PartNumber": 1, "ETag": "etag1"},
    {"PartNumber": 2, "ETag": "etag2"}
  ]
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Testcase Upload Complete"
}
```

---

#### `GET /problem/<problem_id>/testcase` - 下載測資

下載題目測資壓縮檔（需 Manager 權限）。

**Request:**
```http
GET /problem/123/testcase?token=<TOKEN>
```

**Response (200):**
- Content-Type: `application/zip`
- Body: 測資 ZIP 檔案

---

#### `GET /problem/<problem_id>/asset/<asset_type>` - 下載題目資源（Sandbox）

供 Sandbox 下載題目資源（需 Sandbox Token）。

**Request:**
```http
GET /problem/123/asset/makefile?token=<SANDBOX_TOKEN>
```

**Asset Types:**
- `makefile` - makefile.zip
- `teacher_file` - Teacher_file
- `checker` - checker.py
- `scoring_script` - score.py
- `local_service` - local_service.zip

**Response (200):**
- Content-Type: 依檔案類型
- Body: 檔案內容

---

#### `GET /problem/<problem_id>/asset-manage/<asset_type>` - 下載題目資源（管理者）

供題目管理者下載已上傳的資源。

**Request:**
```http
GET /problem/123/asset-manage/checker?token=<JWT_TOKEN>
```

**Response (200):**
- 檔案內容

---

#### `GET /problem/<problem_id>/meta` - 取得題目 Meta（Sandbox）

供 Sandbox 取得題目的完整 metadata，包含執行模式和資源路徑。

**Request:**
```http
GET /problem/123/meta?token=<SANDBOX_TOKEN>
```

**Response (200):**
```json
{
  "problemId": 123,
  "tasks": [
    {
      "caseCount": 10,
      "taskScore": 10,
      "memoryLimit": 65536,
      "timeLimit": 1000
    }
  ],
  "submissionMode": 0,
  "executionMode": "functionOnly",
  "buildStrategy": "makeFunctionOnly",
  "assetPaths": {
    "makefile": "problems/123/makefile.zip",
    "teacher_file": "problems/123/teacher_file.cpp"
  },
  "config": {
    "canViewStdout": true,
    "allowedLanguage": [0, 1, 2]
  }
}
```

---

#### `GET /problem/<problem_id>/checksum` - 取得測資校驗碼（Sandbox）

供 Sandbox 檢查測資是否需要更新。

**Request:**
```http
GET /problem/123/checksum?token=<SANDBOX_TOKEN>
```

**Response (200):**
```json
{
  "checksum": "abc123def456...",
  "submissionMode": 0
}
```

---

#### `GET /problem/<problem_id>/rules` - 取得靜態分析規則（Sandbox）

供 Sandbox 取得靜態分析的限制規則。

**Request:**
```http
GET /problem/123/rules?token=<SANDBOX_TOKEN>
```

**Response (200):**
```json
{
  "model": "whitelist",
  "syntax": ["goto"],
  "imports": [],
  "headers": ["stdio.h", "stdlib.h"],
  "functions": ["printf", "scanf"]
}
```

**Response (404):** 若題目未設定靜態分析規則

---

#### `GET /problem/static-analysis/options` - 取得靜態分析可用選項

取得系統支援的靜態分析符號選項。

**Response (200):**
```json
{
  "librarySymbols": {
    "imports": [],
    "headers": ["stdio.h", "stdlib.h", "string.h", "math.h", ...],
    "functions": ["iostream", "vector", "map", "set", ...]
  }
}
```

---

### Submission (`/submission`)

#### `POST /submission` - 建立提交

建立新的程式碼提交。

**Request:**
```json
{
  "token": "string",
  "languageType": 0,
  "problemId": 123
}
```

**Response (200):**
```json
{
  "status": "ok",
  "data": {
    "submissionId": "01HQABCDEF123456789"
  }
}
```

**Language Types:**
- `0` - C
- `1` - C++
- `2` - Python 3

---

#### `PUT /submission/<submission_id>` - 上傳程式碼

上傳提交的程式碼並送交 Sandbox 評測。

**Request (multipart/form-data):**
```
PUT /submission/01HQABCDEF123456789
Content-Type: multipart/form-data

token: <JWT_TOKEN>
code: [file]  # main.c, main.cpp, main.py, or .zip
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Submission Sent to Sandbox"
}
```

**Error Responses:**
- `400 Bad Request` - 檔案格式錯誤或大小超過限制
- `500 Internal Server Error` - Sandbox 佇列已滿
- `202 Accepted` - Sandbox 暫時無法處理，請稍後重試

---

#### `GET /submission` - 取得提交列表

取得提交記錄列表，支援篩選。

**Request:**
```http
GET /submission?token=<TOKEN>&offset=0&count=20&problemId=123&status=AC
```

**Query Parameters:**
- `offset` (int): 起始位置
- `count` (int): 每頁數量
- `problemId` (int, optional): 題目 ID 篩選
- `username` (string, optional): 使用者篩選
- `status` (string, optional): 狀態篩選（AC/WA/TLE/MLE/...）
- `course` (string, optional): 課程篩選
- `languageType` (int, optional): 語言篩選

**Response (200):**
```json
{
  "status": "ok",
  "data": [
    {
      "submissionId": "01HQABCDEF123456789",
      "problemId": 123,
      "username": "student01",
      "languageType": 1,
      "status": 0,
      "score": 100,
      "timestamp": 1701234567,
      "runTime": 123,
      "memoryUsage": 4096
    }
  ]
}
```

**Status Codes:**
- `0` - AC (Accepted)
- `1` - WA (Wrong Answer)
- `2` - RE (Runtime Error)
- `3` - TLE (Time Limit Exceeded)
- `4` - MLE (Memory Limit Exceeded)
- `5` - CE (Compilation Error)
- `6` - JE (Judge Error)
- `7` - OLE (Output Limit Exceeded)

---

#### `GET /submission/<submission_id>` - 取得提交詳情

取得特定提交的詳細結果。

**Request:**
```http
GET /submission/01HQABCDEF123456789?token=<TOKEN>
```

**Response (200):**
```json
{
  "status": "ok",
  "data": {
    "submissionId": "01HQABCDEF123456789",
    "problemId": 123,
    "username": "student01",
    "languageType": 1,
    "status": 0,
    "score": 100,
    "timestamp": 1701234567,
    "tasks": [
      {
        "taskScore": 10,
        "status": 0,
        "cases": [
          {
            "status": 0,
            "runTime": 15,
            "memoryUsage": 2048
          }
        ]
      }
    ],
    "comment": "Well done!",
    "staticAnalysis": {
      "status": "success",
      "message": "No violations found"
    }
  }
}
```

---

#### `GET /submission/<submission_id>/output/<task>/<case>` - 取得測試案例輸出

取得特定測試案例的輸出內容。

**Request:**
```http
GET /submission/01HQABCDEF123456789/output/0/0?token=<TOKEN>
```

**Response (200):**
- Content-Type: `text/plain`
- Body: 輸出內容

---

#### `GET /submission/<submission_id>/artifact/task/<task_index>` - 下載測資輸出 ZIP

下載特定 subtask 的所有測資輸出打包檔。

**Request:**
```http
GET /submission/01HQABCDEF123456789/artifact/task/0?token=<TOKEN>
```

**Response (200):**
- Content-Type: `application/zip`
- Body: ZIP 檔案包含所有該 task 的輸出

---

#### `GET /submission/<submission_id>/artifact/compiledBinary` - 下載編譯後執行檔

下載編譯後的執行檔（若題目允許）。

**Request:**
```http
GET /submission/01HQABCDEF123456789/artifact/compiledBinary?token=<TOKEN>
```

**Response (200):**
- Content-Type: 依檔案類型
- Body: 執行檔內容

---

#### `GET /submission/<submission_id>/static-analysis` - 取得靜態分析報告

取得提交的靜態分析結果。

**Request:**
```http
GET /submission/01HQABCDEF123456789/static-analysis?token=<TOKEN>
```

**Response (200):**
```json
{
  "status": "ok",
  "data": {
    "status": "success",
    "message": "Static analysis passed",
    "report": "詳細分析報告內容...",
    "reportPath": "submissions/01HQ.../sa_report.txt"
  }
}
```

---

#### `PUT /submission/<submission_id>/complete` - 完成提交評測（Sandbox）

Sandbox 回報評測結果給 Backend。

**Request:**
```json
{
  "token": "<SANDBOX_TOKEN>",
  "tasks": [
    {
      "status": 0,
      "score": 10,
      "cases": [
        {
          "status": 0,
          "exitCode": 0,
          "time": 15,
          "memory": 2048,
          "stdout": "output content",
          "stderr": ""
        }
      ]
    }
  ],
  "staticAnalysis": {
    "status": "success",
    "message": "...",
    "report": "..."
  },
  "artifacts": {
    "compiledBinary": "path/to/binary"
  }
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Submission Complete"
}
```

**Error Responses:**
- `403 Forbidden` - Token 驗證失敗
- `404 Not Found` - Submission 不存在

---

#### `POST /submission/<submission_id>/rejudge` - 重新評測

重新評測指定提交（需 Teacher 或 Admin 權限）。

**Request:**
```json
{
  "token": "string"
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Rejudge Initiated"
}
```

---

#### `PUT /submission/<submission_id>/grade` - 手動評分

手動修改提交分數（需 Teacher 或 Admin 權限）。

**Request:**
```json
{
  "token": "string",
  "score": 85
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Grade Updated"
}
```

---

#### `PUT /submission/<submission_id>/comment` - 新增評語

新增或更新提交評語（需 Teacher 或 Admin 權限）。

**Request:**
```json
{
  "token": "string",
  "comment": "Good job! Consider optimizing..."
}
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "Comment Added"
}
```

---

### Course (`/course`)

#### `GET /course` - 取得課程列表

取得使用者可見的課程列表。

**Response (200):**
```json
{
  "status": "ok",
  "data": [
    {
      "courseName": "Algorithms",
      "teacher": "teacher01",
      "studentCount": 45
    }
  ]
}
```

#### `POST /course` - 建立課程

建立新課程（需 Teacher 或 Admin 權限）。

**Request:**
```json
{
  "token": "string",
  "courseName": "Data Structures"
}
```

---

### Homework (`/homework`)

#### `GET /homework` - 取得作業列表

取得課程作業列表。

#### `POST /homework` - 建立作業

建立新作業（需 Teacher 權限）。

---

### User (`/user`)

#### `GET /user` - 取得使用者列表

取得系統使用者列表（需 Admin 權限）。

#### `POST /user` - 新增使用者

直接新增使用者（需 Admin 權限）。

---

### Profile (`/profile`)

#### `GET /profile/<username>` - 取得使用者個人資料

取得指定使用者的公開個人資料。

#### `PUT /profile` - 更新個人資料

更新當前使用者的個人資料。

---

### 其他端點

#### `GET /health` - 健康檢查

檢查 Backend 服務狀態。

**Response (200):**
```json
{
  "status": "ok",
  "timestamp": 1701234567
}
```

#### `GET /ranking` - 排行榜

取得排行榜資訊。

#### `GET /ann` - 公告

取得系統公告。

---

## Sandbox API

Sandbox 提供內部 API 供 Backend 呼叫。

### `POST /submit/<submission_id>` - 提交評測

Backend 送交提交至 Sandbox 進行評測。

**Request (multipart/form-data):**
```
POST /submit/01HQABCDEF123456789
Content-Type: multipart/form-data

token: <SANDBOX_TOKEN>
problem_id: 123
language: 1
src: [file]
```

**Response (200):**
```json
{
  "status": "ok",
  "msg": "ok",
  "data": "ok"
}
```

**Error Responses:**
- `403 Forbidden` - Token 驗證失敗
- `400 Bad Request` - 缺少必要參數或檔案格式錯誤
- `500 Internal Server Error` - 佇列已滿

**處理流程：**
1. 驗證 Sandbox Token
2. 確保測資已下載並為最新版本
3. 準備 Submission 工作目錄
4. 將任務加入評測佇列
5. 非同步執行編譯與測試
6. 完成後呼叫 Backend `/submission/<id>/complete`

---

### `GET /status` - Sandbox 狀態

取得 Sandbox 當前負載狀態。

**Request:**
```http
GET /status?token=<SANDBOX_TOKEN>
```

**Response (200):**
```json
{
  "load": 0.35,
  "queueSize": 7,
  "maxTaskCount": 20,
  "containerCount": 7,
  "maxContainerCount": 20,
  "submissions": ["01HQABC...", "01HQDEF..."],
  "running": true
}
```

**不帶 Token 的回應（公開）：**
```json
{
  "load": 0.35
}
```

---

## 錯誤代碼參考

### HTTP 狀態碼

| 狀態碼 | 說明 |
|--------|------|
| 200 | 請求成功 |
| 202 | 已接受但尚未處理完成 |
| 400 | 錯誤的請求（缺少參數、格式錯誤） |
| 403 | 禁止存取（權限不足、Token 無效） |
| 404 | 資源不存在 |
| 409 | 衝突（如使用者名稱已存在） |
| 500 | 伺服器內部錯誤 |

### 提交狀態碼

| 狀態碼 | 縮寫 | 說明 |
|--------|------|------|
| 0 | AC | Accepted - 答案正確 |
| 1 | WA | Wrong Answer - 答案錯誤 |
| 2 | RE | Runtime Error - 執行時錯誤 |
| 3 | TLE | Time Limit Exceeded - 超過時間限制 |
| 4 | MLE | Memory Limit Exceeded - 超過記憶體限制 |
| 5 | CE | Compilation Error - 編譯錯誤 |
| 6 | JE | Judge Error - 評測系統錯誤 |
| 7 | OLE | Output Limit Exceeded - 輸出超過限制 |

### 靜態分析狀態

- `success` - 分析通過
- `failure` - 發現違規
- `skip` - 跳過分析（缺少必要工具）
- `error` - 分析過程錯誤

---

## 通用回應格式

### 成功回應

```json
{
  "status": "ok",
  "msg": "Operation Success",
  "data": { ... }
}
```

### 錯誤回應

```json
{
  "status": "err",
  "msg": "Error Description",
  "data": null
}
```

---

## 環境變數配置

### Backend

| 變數名 | 說明 | 預設值 |
|--------|------|--------|
| `MONGO_HOST` | MongoDB 主機位址 | `mongodb` |
| `REDIS_HOST` | Redis 主機位址 | `redis` |
| `REDIS_PORT` | Redis 連接埠 | `6379` |
| `MINIO_HOST` | MinIO 主機位址 | - |
| `MINIO_ACCESS_KEY` | MinIO 存取金鑰 | - |
| `MINIO_SECRET_KEY` | MinIO 秘密金鑰 | - |
| `MINIO_BUCKET` | MinIO Bucket 名稱 | - |
| `JWT_SECRET` | JWT 簽章密鑰 | - |
| `JWT_EXP` | JWT 有效期限（天） | `7` |
| `JWT_ISS` | JWT 發行者 | `noj.tw` |
| `SERVER_NAME` | 伺服器名稱 | - |

### Sandbox

| 變數名 | 說明 | 預設值 |
|--------|------|--------|
| `SANDBOX_TOKEN` | Sandbox 認證 Token | - |
| `BACKEND_URL` | Backend API 位址 | - |
| `DISPATCHER_CONFIG` | Dispatcher 配置檔路徑 | `.config/dispatcher.json` |

---

## 相關文檔

- [ARCHITECTURE.md](ARCHITECTURE.md) - 系統架構說明
- [BUILD_STRATEGY_GUIDE.md](BUILD_STRATEGY_GUIDE.md) - 建置策略指南
- [STATIC_ANALYSIS.md](STATIC_ANALYSIS.md) - 靜態分析說明
- [CONFIG_REFERENCE.md](CONFIG_REFERENCE.md) - 配置參考

---

**最後更新：** 2025-11-29  
**維護者：** 2025 NTNU Software Engineering Team 1
