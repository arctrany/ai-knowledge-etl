# Knowledge-ETL 进度输出规范

## 设计目标

**核心问题**: 长时间运行任务需要简短的进度反馈，让用户知道系统在工作。

**解决方案**: 使用 **TodoWrite 工具** 实现常驻进度显示，避免上下文膨胀。

---

## ⚠️ 重要：使用 TodoWrite 而非文本输出

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🚨 NEVER USE TEXT OUTPUT FOR PROGRESS - USE TodoWrite INSTEAD 🚨        ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  ❌ WRONG: echo "[Extract] ████░░ 40% | loading..."                      ║
║  ❌ WRONG: Output text messages for each step                            ║
║                                                                           ║
║  ✅ RIGHT: Use TodoWrite tool to update task status                      ║
║  ✅ RIGHT: TodoWrite displays in Claude Code statusline (persistent)     ║
║  ✅ RIGHT: Status updates don't accumulate in context                    ║
║                                                                           ║
║  WHY: Text output accumulates in context → "Prompt is too long" error    ║
║       TodoWrite renders in UI statusline → No context growth             ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## TodoWrite 进度显示模式

### 使用 TodoWrite 更新进度

每个主要阶段使用一个 todo 项，通过 `activeForm` 字段显示当前状态：

```javascript
// 初始化任务列表
TodoWrite({
  todos: [
    { content: "Extract page content", status: "in_progress", activeForm: "Navigating to URL..." },
    { content: "Process images and text", status: "pending", activeForm: "Processing content" },
    { content: "Transform to output format", status: "pending", activeForm: "Transforming output" },
    { content: "Validate results", status: "pending", activeForm: "Validating results" }
  ]
})

// 更新进度 - 修改 activeForm 显示详细状态
TodoWrite({
  todos: [
    { content: "Extract page content", status: "in_progress", activeForm: "Capturing snapshot (12K chars)..." },
    { content: "Process images and text", status: "pending", activeForm: "Processing content" },
    { content: "Transform to output format", status: "pending", activeForm: "Transforming output" },
    { content: "Validate results", status: "pending", activeForm: "Validating results" }
  ]
})

// 完成一个阶段，开始下一个
TodoWrite({
  todos: [
    { content: "Extract page content", status: "completed", activeForm: "Extracted page content" },
    { content: "Process images and text", status: "in_progress", activeForm: "Compressing images (3/5)..." },
    { content: "Transform to output format", status: "pending", activeForm: "Transforming output" },
    { content: "Validate results", status: "pending", activeForm: "Validating results" }
  ]
})
```

### 在 Claude Code 中的显示效果

```
☑ Extract page content
⏺ Processing images (3/5 compressed)...
☐ Transform to output format
☐ Validate results
```

---

## activeForm 状态消息格式

### 提取阶段
```
"Navigating to URL..."
"Waiting for page load..."
"Capturing snapshot (12K chars)..."
"Downloading images (3/8)..."
"⏸ LOGIN REQUIRED - complete login in browser"
```

### 处理阶段
```
"Checking file sizes..."
"Compressing images (2/5)..."
"Processing snapshot chunks (3/6)..."
"⚠ Anti-scrape detected, using screenshot"
```

### 转换阶段
```
"Generating SKILL.md..."
"Creating reference files (2/3)..."
"Writing output structure..."
```

### 验证阶段
```
"Running self-check..."
"✓ Validation passed"
"⚠ Output exceeds 50K chars, summarizing..."
```

---

## 最终完成摘要

任务完成后，输出简短的完成摘要（仅一次）：

```markdown
### ✓ Extraction Complete

**Output:**
- `output/skill/SKILL.md` (1,823 words)
- `output/skill/references/` (3 files)

**Stats:**
- Total time: 15.7s
- Images processed: 5
- Compression: 1.2MB → 280KB
```

---

## 状态图标

| 图标 | 含义 | 在 activeForm 中使用 |
|------|------|---------------------|
| `...` | 进行中 | "Processing..." |
| `✓` | 完成 | "✓ Done" |
| `⚠` | 警告/降级 | "⚠ Using fallback" |
| `✗` | 失败 | "✗ Failed: reason" |
| `⏸` | 等待用户 | "⏸ Waiting for login" |

---

## 关键原则

### DO

1. **使用 TodoWrite** 更新任务进度
2. **通过 activeForm** 显示详细状态
3. **一个阶段一个 todo** 保持简洁
4. **完成时标记 completed** 让用户看到进度

### DON'T

1. **不要 echo 进度消息** - 会累积到上下文
2. **不要频繁输出文本** - 会导致 "Prompt is too long"
3. **不要在 activeForm 中放长内容** - 保持简短 (<50 字符)
4. **不要输出文件内容** - 只显示文件名和大小

---

## Agent 配置指令

```
Progress output rules (CRITICAL):

1. USE TodoWrite FOR ALL PROGRESS UPDATES
   - Never use echo/print for progress
   - Update activeForm field for status details
   - One todo per major phase

2. TodoWrite USAGE:
   - Start: Create todos for all phases (pending)
   - Progress: Update activeForm of in_progress todo
   - Complete: Mark todo as completed, move to next

3. activeForm FORMAT:
   - Keep under 50 chars
   - Include: action + key metric (e.g., "Compressing (3/5)...")
   - Use status icons: ⏸ ⚠ ✓ ✗

4. FINAL OUTPUT:
   - One summary message with output files
   - Include: filenames, sizes, stats
   - No intermediate progress text
```
