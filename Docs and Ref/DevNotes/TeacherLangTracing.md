# Teacher Language Parameter追蹤報告

## 🔍 調查結果

`teacherLang`參數目前**並未被Frontend或Backend主動設定**！

### 關鍵發現

- ❌ Frontend沒有UI讓教師選擇teacher language
- ❌ Backend不會在上傳Teacher_file時設定teacherLang  
- ✅ Sandbox會fallback到student language或從檔案extension推斷

---

## 📊 完整流程

### 1. Frontend (無設定)

搜尋`new-front-end`目錄，**找不到**任何`teacherLang`相關代碼。

### 2. Backend: 上傳Teacher_file

**File**: [problem.py](file:///\\wsl.localhost\Ubuntu-20.04\home\camel0311\code\NOJ_Repo\Normal-OJ-2025Team1\Back-End\mongo\problem\problem.py#L233)

```python
resource_files = {
    'Teacher_file': ('teacher_file', 'Teacher_file'),
}
```

只存path到`assetPaths`，沒有language info：
```json
{
  "teacher_file": "minio/path/to/file"
  // ⚠️ 沒有 teacherLang
}
```

### 3. Sandbox: 推斷Language

**File**: [build_strategy.py](file:///\\wsl.localhost\Ubuntu-20.04\home\camel0311\code\NOJ_Repo\Normal-OJ-2025Team1\Sandbox\dispatcher\build_strategy.py#L275-L280)

```python
teacher_lang_val = (meta.assetPaths or {}).get("teacherLang")
teacher_lang = teacher_lang_map.get(
    str(teacher_lang_val or "").lower(),
    Language(meta.language)  # ⭐ Fallback到student language
)
```

**推斷策略** ([_resolve_teacher_lang](file:///\\wsl.localhost\Ubuntu-20.04\home\camel0311\code\NOJ_Repo\Normal-OJ-2025Team1\Sandbox\dispatcher\build_strategy.py#L301-L316)):
1. assetPaths.teacherLang（目前不存在）
2. 檔案extension (`main.py`, `main.cpp`, `main.c`)
3. Student language

---

## ⚠️ 當前問題

如果teacher用Python，student用C++：

```
1. Backend存 teacher_file path  
2. Sandbox用 meta.language (CPP) 作為teacher_lang
3. 寫入 teacher/main.cpp（內容是Python!）
4. Compile失敗 ❌
```

---

## 🔧 建議改進

### Option 1: Backend自動偵測（推薦）

```python
if key == 'Teacher_file':
    ext = file_obj.filename.split('.')[-1]
    lang_map = {'c': 'c', 'cpp': 'cpp', 'py': 'py'}
    if ext in lang_map:
        new_asset_paths['teacherLang'] = lang_map[ext]
```

### Option 2: Frontend UI

新增dropdown讓教師選擇teacher language。

### Option 3: 保持現狀

確保teacher file extension正確，依賴Sandbox的file-based推斷。

---

## ✅ 對重構的影響

`prepare_interactive_teacher_artifacts()`應該：
- 保留fallback機制
- 繼續使用`_resolve_teacher_lang()`
- 在文檔中註明limitation

---

## 📝 測試資料

[interactive-sample/meta.json](file:///\\wsl.localhost\Ubuntu-20.04\home\camel0311\code\NOJ_Repo\Normal-OJ-2025Team1\Sandbox\problem\interactive-sample\meta.json#L9) 有手動設定：

```json
"assetPaths": {
    "teacher_file": "...",
    "teacherLang": "c"  // 測試資料，實際系統不會產生
}
```
