# Sandbox 配置文件參考指南

## 概述

本文檔詳細說明 Normal-OJ Sandbox 的所有配置文件，包括參數說明、默認值、使用場景和配置示例。

## 配置文件位置

所有配置文件位於 `Sandbox/.config/` 目錄：

```
.config/
├── dispatcher.json      # Dispatcher 全局配置
├── submission.json      # 提交處理配置
└── interactive.json     # Interactive 模式配置
```

---

## 1. dispatcher.json

### 用途
控制 Dispatcher 的全局行為，包括任務隊列大小和容器並發限制。

### 配置參數

| 參數 | 類型 | 默認值 | 說明 |
|------|------|--------|------|
| `QUEUE_SIZE` | int | 1024 | 任務隊列最大容量（Build + Execute 任務總數） |
| `MAX_CONTAINER_NUMBER` | int | 4 | 同時運行的最大容器數量 |

### 詳細說明

#### QUEUE_SIZE
- **作用**: 限制 Dispatcher 可以接受的任務數量
- **影響**: 
  - 過小：頻繁拒絕提交（HTTP 429）
  - 過大：記憶體佔用增加
- **建議值**: 
  - 低負載：256-512
  - 中等負載：1024（默認）
  - 高負載：2048-4096

#### MAX_CONTAINER_NUMBER
- **作用**: 控制同時運行的 Docker 容器數量
- **影響**:
  - 過小：評測速度慢，排隊時間長
  - 過大：系統資源耗盡（CPU/Memory/Disk I/O）
- **建議值**:
  - 單核/2GB 記憶體：2
  - 四核/4GB 記憶體：4（默認）
  - 八核/8GB+ 記憶體：8-16

### 配置示例

```json
{
    "QUEUE_SIZE": 2048,
    "MAX_CONTAINER_NUMBER": 8
}
```

### 注意事項

1. **動態調整**: 修改後需重啟 Sandbox 服務
2. **監控指標**: 使用 `/status` API 查看當前負載
3. **資源規劃**: `MAX_CONTAINER_NUMBER` 應考慮主機資源限制

---

## 2. submission.json

### 用途
配置提交處理的核心參數，包括工作目錄、Docker 連接、語言映射和容器鏡像。

### 配置參數

| 參數 | 類型 | 說明 |
|------|------|------|
| `working_dir` | string | 提交檔案的工作目錄（絕對路徑） |
| `docker_url` | string | Docker daemon 連接 URL |
| `lang_id` | object | 語言鍵到語言 ID 的映射 |
| `image` | object | 語言鍵到 Docker 鏡像的映射 |
| `interactive_image` | string | Interactive 模式專用鏡像 |

### 詳細說明

#### working_dir
- **作用**: 所有提交檔案和測資的存儲根目錄
- **結構**: 
  ```
  working_dir/
  ├── <submission_id>/
  │   ├── src/
  │   │   ├── common/      # 編譯產物與原始碼
  │   │   └── cases/       # 各測試案例執行環境
  │   │       ├── 0000/
  │   │       └── ...
  │   ├── teacher/     # 教師代碼（Interactive模式）
  │   └── ...
  └── problem_meta/    # 測資緩存
  ```
- **要求**: 
  - 必須是絕對路徑
  - Sandbox 進程需有讀寫權限
  - 建議使用 SSD 以提升 I/O 性能

#### docker_url
- **作用**: 指定 Docker daemon 的連接方式
- **支持格式**:
  - Unix Socket: `unix://var/run/docker.sock`（默認）
  - TCP: `tcp://localhost:2375`（不推薦，安全風險）
- **權限**: Sandbox 進程用戶需在 `docker` 組中

#### lang_id
- **作用**: 將語言鍵映射為 `sandbox_interactive` 使用的語言 ID
- **映射表**:
  ```json
  {
    "c11": 0,
    "cpp17": 1,
    "python3": 2
  }
  ```
- **用途**: 傳遞給 `sandbox_interactive` 的第一個參數
- **擴展**: 若新增語言，需同步更新此映射

#### image
- **作用**: 為每種語言指定編譯/執行的 Docker 鏡像
- **默認配置**:
  ```json
  {
    "c11": "noj-c-cpp",
    "cpp17": "noj-c-cpp",
    "python3": "noj-py3"
  }
  ```
- **鏡像要求**:
  - 必須包含對應語言的編譯器/解釋器
  - 已安裝 `sandbox` 可執行檔（C/C++）
  - 受信任的基底鏡像（安全性）

#### interactive_image
- **作用**: Interactive 模式專用鏡像
- **默認值**: `noj-interactive`
- **特殊要求**:
  - 包含 `sandbox_interactive` 可執行檔
  - 支援 FIFO 和 `/dev/fd` 管道
  - 已配置 Seccomp 規則

### 配置示例

```json
{
  "working_dir": "/home/sandbox/submissions",
  "docker_url": "unix://var/run/docker.sock",
  "lang_id": {
    "c11": 0,
    "cpp17": 1,
    "python3": 2
  },
  "image": {
    "c11": "noj-c-cpp:latest",
    "cpp17": "noj-c-cpp:latest",
    "python3": "noj-py3:latest"
  },
  "interactive_image": "noj-interactive:latest"
}
```

### 注意事項

1. **路徑一致性**: `working_dir` 必須與 Docker volume mount 一致
2. **鏡像版本**: 建議使用固定版本標籤而非 `latest`
3. **權限配置**: 確保 Docker socket 權限正確
4. **測試驗證**: 修改後執行 `pytest tests/` 確保相容

---

## 3. interactive.json

### 用途
配置 Interactive 執行模式的特定參數，包括資源限制和權限控制。

### 配置參數

| 參數 | 類型 | 默認值 | 說明 |
|------|------|--------|------|
| `outputLimitBytes` | int | 67108864 | 輸出大小限制（位元組） |
| `maxTeacherNewFiles` | int | 500 | 教師程式可創建的最大檔案數 |
| `teacherUid` | int | 1450 | 教師進程的用戶 ID |
| `studentUid` | int | 1451 | 學生進程的用戶 ID |
| `sandboxGid` | int | 1450 | 沙盒統一組 ID |
| `studentAllowRead` | bool | false | 學生是否可讀取 src 目錄 |
| `studentAllowWrite` | bool | false | 學生是否可寫入 src 目錄 |

### 詳細說明

#### outputLimitBytes
- **作用**: 限制單個進程的輸出大小（stdout + stderr）
- **默認值**: 67108864（64 MB）
- **影響**: 超過限制會觸發 `OLE`（Output Limit Exceeded）
- **建議值**:
  - 一般題目：64 MB（默認）
  - 大數據題目：128 MB - 256 MB
  - 檔案輸出題目：根據需求調整
- **安全考量**: 過大可能導致磁碟空間耗盡

#### maxTeacherNewFiles
- **作用**: 限制教師程式可創建的新檔案數量
- **默認值**: 500
- **檢查時機**: 執行完成後，若超過限制回傳 `CE`
- **建議值**:
  - 簡單互動：100-200
  - 複雜互動：500（默認）
  - 檔案密集型：1000+
- **注意**: 不包括執行前已存在的檔案

#### teacherUid / studentUid
- **作用**: 控制教師和學生進程的 UID，實現權限隔離
- **默認值**:
  - `teacherUid`: 1450
  - `studentUid`: 1451
- **權限矩陣**:
  ```
  /workspace/teacher/  owner=1450  mode=700  (學生無法訪問)
  /workspace/src/      owner=1451  mode=755  (教師可讀)
  ```
- **修改影響**: 需同步更新容器內的用戶配置

#### sandboxGid
- **作用**: 統一的組 ID，方便 host 端清理檔案
- **默認值**: 1450
- **用途**: 所有檔案屬於同一 group，簡化權限管理

#### studentAllowRead / studentAllowWrite
- **作用**: 控制學生對 src 目錄的讀寫權限（預留接口）
- **默認值**: 均為 `false`
- **使用場景**:
  - `studentAllowRead=true`: 一般題目需要讀取自己的代碼
  - `studentAllowWrite=true`: 檔案輸出型題目
- **安全性**: 
  - 寫入由 Seccomp 強制執行
  - 讀取由文件權限控制
- **未來擴展**: 為後續模組（如檔案輸出題型）提供接口

### 配置示例

#### 默認配置（嚴格隔離）
```json
{
  "outputLimitBytes": 67108864,
  "maxTeacherNewFiles": 500,
  "teacherUid": 1450,
  "studentUid": 1451,
  "sandboxGid": 1450,
  "studentAllowRead": false,
  "studentAllowWrite": false
}
```

#### 寬鬆配置（允許學生讀寫）
```json
{
  "outputLimitBytes": 134217728,
  "maxTeacherNewFiles": 1000,
  "teacherUid": 1450,
  "studentUid": 1451,
  "sandboxGid": 1450,
  "studentAllowRead": true,
  "studentAllowWrite": true
}
```

### 注意事項

1. **安全警告**: 
   - 啟用 `studentAllowRead/Write` 會降低安全性
   - 僅在必要時啟用（如特定題型需求）
   
2. **權限一致性**:
   - 修改 UID/GID 後需同步更新 `interactive_orchestrator.py`
   - 測試所有權限設置以確保隔離有效

3. **資源限制**:
   - `outputLimitBytes` 和 `maxTeacherNewFiles` 應根據硬體資源調整
   - 監控磁碟使用情況

---

## 配置最佳實踐

### 1. 環境隔離

**開發環境**:
```json
// dispatcher.json
{
  "QUEUE_SIZE": 256,
  "MAX_CONTAINER_NUMBER": 2
}
```

**生產環境**:
```json
// dispatcher.json
{
  "QUEUE_SIZE": 4096,
  "MAX_CONTAINER_NUMBER": 16
}
```

### 2. 安全加固

- ✅ 使用最小權限原則（Interactive 默認配置）
- ✅ 定期更新 Docker 鏡像
- ✅ 限制輸出和檔案數量
- ✅ 監控異常提交模式

### 3. 性能優化

- ✅ SSD 存儲用於 `working_dir`
- ✅ 根據 CPU 核心數調整 `MAX_CONTAINER_NUMBER`
- ✅ 定期清理舊提交目錄
- ✅ 使用鏡像緩存加速容器啟動

### 4. 監控和日誌

```bash
# 查看 Dispatcher 狀態
curl http://sandbox:8080/status

# 監控隊列大小
watch -n 1 'curl -s http://sandbox:8080/status | jq .load'

# 監控容器數量
docker ps --filter "name=noj-" --format "table {{.Names}}\t{{.Status}}"
```

---

## 配置變更流程

1. **備份現有配置**
   ```bash
   cp .config/*.json .config/backup/
   ```

2. **修改配置文件**
   ```bash
   vim .config/dispatcher.json
   ```

3. **驗證 JSON 格式**
   ```bash
   jq . .config/dispatcher.json
   ```

4. **重啟 Sandbox 服務**
   ```bash
   systemctl restart noj-sandbox
   ```

5. **驗證配置生效**
   ```bash
   pytest tests/test_dispatcher.py
   ```

---

## 常見問題

### Q1: 修改配置後不生效？
**解決方法**: 確保重啟了 Sandbox 服務，配置在啟動時讀取。

### Q2: 容器啟動失敗？
**檢查項目**:
- Docker daemon 是否運行
- `docker_url` 配置是否正確
- 鏡像是否存在（`docker images`）

### Q3: 權限錯誤導致無法清理？
**解決方法**: 
```bash
# 方案 1: 修改權限後刪除
chmod -R 777 submissions/<id>
rm -rf submissions/<id>

# 方案 2: 使用容器清理
docker run --rm -v $(pwd)/submissions/<id>:/cleanup alpine rm -rf /cleanup
```

### Q4: Interactive 模式教師無法寫檔？
**檢查項目**:
- `teacherUid` 設置是否正確
- 目錄 owner 是否為 `teacherUid`
- `SANDBOX_ALLOW_WRITE` 環境變數是否設置

---

## 相關文檔

- [05_INTERACTIVE.md](./05_INTERACTIVE.md) - Interactive 模式權限詳解
- [BUILD_STRATEGY_GUIDE.md](./BUILD_STRATEGY_GUIDE.md) - Build Strategy 架構
- [02_STATIC_ANALYSIS.md](./02_STATIC_ANALYSIS.md) - 靜態分析流程
- [Sandbox/Spec.md](../Sandbox/Spec.md) - 系統規格說明

---

## 配置模板

### 小型部署（單機/開發）
```json
// dispatcher.json
{
  "QUEUE_SIZE": 512,
  "MAX_CONTAINER_NUMBER": 2
}

// submission.json
{
  "working_dir": "/var/noj/submissions",
  "docker_url": "unix://var/run/docker.sock",
  "lang_id": {"c11": 0, "cpp17": 1, "python3": 2},
  "image": {
    "c11": "noj-c-cpp:stable",
    "cpp17": "noj-c-cpp:stable",
    "python3": "noj-py3:stable"
  },
  "interactive_image": "noj-interactive:stable"
}

// interactive.json
使用默認配置
```

### 大型部署（生產/高負載）
```json
// dispatcher.json
{
  "QUEUE_SIZE": 8192,
  "MAX_CONTAINER_NUMBER": 32
}

// submission.json
{
  "working_dir": "/mnt/ssd/noj/submissions",
  "docker_url": "unix://var/run/docker.sock",
  "lang_id": {"c11": 0, "cpp17": 1, "python3": 2},
  "image": {
    "c11": "noj-c-cpp:v2.1.0",
    "cpp17": "noj-c-cpp:v2.1.0",
    "python3": "noj-py3:v2.1.0"
  },
  "interactive_image": "noj-interactive:v2.1.0"
}

// interactive.json
{
  "outputLimitBytes": 134217728,
  "maxTeacherNewFiles": 1000,
  "teacherUid": 1450,
  "studentUid": 1451,
  "sandboxGid": 1450,
  "studentAllowRead": false,
  "studentAllowWrite": false
}
```
