# Knowledge-ETL 进度输出规范

## 设计目标

**核心问题**: 长时间运行任务需要简短的进度反馈，让用户知道系统在工作。

---

## 极简进度格式

### 单行进度（推荐）

```
[Extract] ████░░░░░░ 40% | page loaded, capturing...
[Process] ██████░░░░ 60% | compressed 3 images
[Transform] ████████░░ 80% | generating SKILL.md...
[Validate] ██████████ 100% ✓
```

### 状态图标

| 图标 | 含义 |
|------|------|
| `...` | 进行中 |
| `✓` | 完成 |
| `⚠` | 警告 |
| `✗` | 失败 |
| `⏸` | 等待用户 |

---

## 启动时显示 Plan

```
┌─ PLAN ─────────────────────────────────────────┐
│ 1. Extract   → capture page content            │
│ 2. Process   → clean, compress                 │
│ 3. Transform → skill (plugin-dev)              │
│ 4. Validate  → skill-reviewer                  │
└────────────────────────────────────────────────┘
```

带并行标识：

```
┌─ PLAN ─────────────────────────────────────────┐
│ 1. Extract   → capture page                    │
│ 2. Process   → clean ║ compress ║ dedupe       │ ← 并行
│ 3. Transform → skill                           │
│ 4. Validate  → reviewer                        │
└────────────────────────────────────────────────┘
```

---

## 运行时进度（简短）

### 正常流程

```
[1/4 Extract]   ████████░░ 80% | snapshot.md (12K chars)
[2/4 Process]   ██████░░░░ 60% | compressed: 1.2MB→280KB
[3/4 Transform] ████░░░░░░ 40% | SKILL.md + 2 refs...
[4/4 Validate]  ██████████ 100% ✓ passed
```

### 爬虫模式

```
[1/4 Crawl] ████░░░░░░ 8/20 | depth:1 queue:12 | 005_auth.md...
```

### 并行任务

```
[2/4 Process] ██████░░░░ 60% | ║ clean ✓ ║ compress... ║ links ✓ ║
```

### 等待用户

```
[1/4 Extract] ██░░░░░░░░ 20% | ⏸ LOGIN REQUIRED - 请在浏览器完成登录
```

### 错误降级

```
[1/4 Extract] ████░░░░░░ 40% | ⚠ anti-scrape → using screenshot
```

---

## 完成输出

```
━━━ DONE (15.7s) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Extract   ██████████ ✓ 4.2s
Process   ██████████ ✓ 1.1s
Transform ██████████ ✓ 8.3s
Validate  ██████████ ✓ 2.1s

→ output/skill/SKILL.md (1,823 words)
→ output/skill/references/ (3 files)
```

---

## 关键信息过滤

### 输出 (DO)

| 阶段 | 输出什么 |
|------|----------|
| Extract | 文件名 + 大小 |
| Process | 压缩比 (1.2MB→280KB) |
| Transform | 生成的文件名 |
| Validate | passed/failed |

### 不输出 (DON'T)

- 文件内容
- 调试信息
- 完整路径
- 中间步骤

---

## Agent 输出指令

```
Progress output rules:
1. One line per phase: [N/4 Phase] ████░░░░░░ X% | brief_status
2. Only key info: filename, size, compress ratio, error type
3. No content, no debug, no full paths
4. Use ║ for parallel tasks
5. Final: list output files with sizes
```
