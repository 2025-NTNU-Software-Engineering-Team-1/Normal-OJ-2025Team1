# Teacher Compile Error診斷

## 錯誤
```
Build Failed: failed to prepare teacher artifacts: 
teacher compile failed: cc1: fatal error: *.c: No such file or directory
```

## 根本原因

[build_strategy.py:238-239](file:///\\wsl.localhost\Ubuntu-20.04\home\camel0311\code\NOJ_Repo\Normal-OJ-2025Team1\Sandbox\dispatcher\build_strategy.py#L238-L239) **強制要求teacherLang**：

```python
if not teacher_lang_val:
    raise BuildStrategyError("interactive mode requires teacherLang")
```

但系統**根本不會設定teacherLang**！（見TEACHER_LANG_TRACING.md）

## 修正

移除強制檢查，加入fallback：

```python
# ✅ Fallback到student language
teacher_lang = teacher_lang_map.get(
    str(teacher_lang_val or "").lower(), 
    Language(meta.language)  # 預設
)
```

然後用`_resolve_teacher_lang()`從檔案推斷：

```python
# Write file first
src_path.write_bytes(data)

# Re-resolve from actual files
teacher_lang = _resolve_teacher_lang(meta=meta, teacher_dir=teacher_dir)
```

## 立即行動

1. 移除line 238-239的強制檢查
2. 加入fallback到meta.language
3. 寫入檔案後用_resolve_teacher_lang重新推斷
