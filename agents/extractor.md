---
name: extractor
description: |
  Content extractor - processes LOCAL files in isolated context.

  Use this agent when:
  - Processing pre-captured snapshots/screenshots (from main context Playwright)
  - Analyzing local images
  - Processing PDFs or directories
  - Any extraction that may exceed context limits

  Key capability: Runs in isolated context. NO MCP tools available.
  Main context must capture URL content first, then delegate local files here.
  REUSES atomic capabilities: content-safeguard, relevance-scorer.

  Triggers: "process snapshot", "analyze image", "prompt too large", "extract pdf"
model: sonnet
tools:
  - Read
  - Write
  - Bash
  - Glob
  - Grep
  - AskUserQuestion
# NOTE: MCP tools (Playwright) are NOT available in subagents.
# URL extraction must be done in main context BEFORE calling this agent.
# This agent processes LOCAL files only (.playwright-mcp/snapshot.md, etc.)
---

# Content Extractor Coordinator

Unified extraction agent running in **isolated context** to prevent overflow.

---

## Core Principle: Apply Atomic Capabilities

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    COORDINATION, NOT DUPLICATION                          ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  This agent COORDINATES extraction using atomic capabilities:            ║
║                                                                           ║
║  1. content-safeguard skill → Size limits, compression, truncation       ║
║  2. relevance-scorer skill  → Link scoring, topic matching               ║
║                                                                           ║
║  Apply these patterns, don't reinvent them.                              ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## Safety Limits

**Reference**: `config/limits.yaml` for centralized configuration.

| Resource | Limit | Action |
|----------|-------|--------|
| Image size | 300 KB | Compress before read |
| Image width | 800 px | Resize |
| Images/session | 5 | Skip decorative |
| Text/file | 20,000 chars | Truncate |
| Snapshot | 30,000 chars | Truncate |
| Total output | 50,000 chars | Summarize |
| PDF pages | 15 | Summarize rest |
| Batch size | 5 files | Process in batches |

---

## Input Type Detection

```
URL (http/https)     → URL Extraction Flow
Image (png/jpg/gif)  → Image Processing Flow
PDF (.pdf)           → PDF Processing Flow
Directory            → Directory Processing Flow
Glob pattern         → Expand then route
Git URL              → Clone then Directory Flow
```

---

## URL Content Processing Flow

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  ⚠️ THIS AGENT PROCESSES LOCAL FILES ONLY                                 ║
║                                                                            ║
║  URL capture (Playwright) is done by caller in MAIN context.              ║
║  This agent receives pre-captured snapshot/screenshot files.              ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

**Input from caller:**
- `.playwright-mcp/snapshot.md` - Page snapshot (text)
- `.playwright-mcp/screenshot.png` - Page screenshot (fallback)
- `.playwright-mcp/images.json` - Image metadata (NEW)
- `.playwright-mcp/img_*.jpg` - Downloaded page images, pre-compressed (NEW)

### ⚠️ EXTRACTION PRIORITY: Snapshot FIRST, Screenshot FALLBACK ONLY

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🎯 PRIORITY: TEXT SNAPSHOT ALWAYS PREFERRED OVER SCREENSHOT              ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  WHY SNAPSHOT IS BETTER:                                                  ║
║  ✅ Preserves actual text (searchable, copyable)                         ║
║  ✅ Preserves image URLs (can download separately)                       ║
║  ✅ Much lighter tokens (text << image)                                  ║
║  ✅ Faster processing                                                     ║
║  ✅ Better structure extraction (headings, lists)                        ║
║                                                                           ║
║  WHY SCREENSHOT IS WORSE:                                                 ║
║  ❌ Loses image download capability completely!                          ║
║  ❌ Much heavier tokens (expensive)                                       ║
║  ❌ Text becomes approximate (OCR-like)                                  ║
║  ❌ Structure harder to extract                                          ║
║                                                                           ║
║  USE SCREENSHOT ONLY WHEN:                                                ║
║  - Snapshot is empty or <100 chars (anti-scrape blocked it)              ║
║  - Dynamic/canvas content not captured in snapshot                       ║
║  - User explicitly requests visual capture                               ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

### Step 1: Check Snapshot Size

```bash
SIZE=$(stat -f%z ".playwright-mcp/snapshot.md" 2>/dev/null || echo "0")
echo "[Extract] snapshot size: ${SIZE} bytes"
```

### Step 2: Process Content (Apply content-safeguard)

**Prefer snapshot over screenshot** (text is lighter):
```bash
if [ "$SIZE" -gt 100 ]; then
  # Use snapshot (text)
  # CRITICAL: Check line count and read in chunks if needed!
  LINES=$(wc -l < ".playwright-mcp/snapshot.md")

  if [ "$LINES" -gt 500 ]; then
    # Large file: read in chunks, summarize each chunk
    # Chunk 1: first 500 lines
    Read(".playwright-mcp/snapshot.md", limit: 500)
    # Summarize chunk 1, store summary

    # Chunk 2: next 500 lines (if exists)
    Read(".playwright-mcp/snapshot.md", offset: 500, limit: 500)
    # Summarize chunk 2, append to summary

    # Continue until done, then combine summaries
  else
    # Small file: read directly
    Read(".playwright-mcp/snapshot.md")
  fi
else
  # Fall back to screenshot
  # Check size, compress if > 300KB
  "${CLAUDE_PLUGIN_ROOT}/scripts/compress-image.sh" \
    ".playwright-mcp/screenshot.png" \
    ".playwright-mcp/screenshot-compressed.jpg" 800
  Read(".playwright-mcp/screenshot-compressed.jpg")
fi
```

**Chunking Strategy for Large Snapshots:**
```
╔═══════════════════════════════════════════════════════════════════════════╗
║  LARGE SNAPSHOT (>500 lines) PROCESSING                                   ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  1. Read chunk (500 lines) → Extract key info → Store summary            ║
║  2. Read next chunk → Extract key info → Append to summary               ║
║  3. Repeat until EOF                                                      ║
║  4. Combine summaries into final output                                   ║
║                                                                           ║
║  NEVER read entire large file at once!                                   ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

### Step 3: Extract and Transform Text

- Extract text content from snapshot
- Parse document structure (headings, lists, tables)
- Structure as Markdown

### Step 4: Process Downloaded Images (OPTIMIZED)

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🖼️ PAGE IMAGE PROCESSING - ALWAYS USE COMPRESSED VERSION                 ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  Image locations (after download-images.sh):                             ║
║  - Original: {output_dir}/images/img_*.png                               ║
║  - Compressed: {output_dir}/images/compressed/img_*.jpg (<100KB)         ║
║                                                                           ║
║  🚨 ALWAYS use compressed version for analysis!                          ║
║  - Compressed images are optimized for model context (<100KB)            ║
║  - Original images may be too large and cause "Prompt too long"         ║
║                                                                           ║
║  Processing rules:                                                        ║
║  1. ALWAYS check compressed/ directory first                             ║
║  2. Read ONE compressed image at a time                                  ║
║  3. Describe immediately, store as text                                  ║
║  4. If read fails, return error - NEVER fabricate content                ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

**Step 4.1: Check for compressed images (PRIORITY)**
```bash
# ALWAYS use compressed directory first
COMPRESSED_DIR="${OUTPUT_DIR}/images/compressed"

if [ -d "$COMPRESSED_DIR" ]; then
  IMAGE_COUNT=$(ls -1 "$COMPRESSED_DIR"/img_*.jpg 2>/dev/null | wc -l)
  echo "[Extract] Found ${IMAGE_COUNT} compressed images in $COMPRESSED_DIR"
else
  echo "[Extract] ⚠ No compressed directory found, checking original..."
  IMAGE_COUNT=$(ls -1 "${OUTPUT_DIR}/images"/img_*.png 2>/dev/null | wc -l)
fi

# Read metadata if available
if [ -f "${OUTPUT_DIR}/images.json" ]; then
  Read("${OUTPUT_DIR}/images.json")
fi
```

**Step 4.2: Process each COMPRESSED image**
```bash
IMAGE_DESCRIPTIONS=""
PROCESSED=0
SKIPPED=0

# Use compressed images (optimized for model analysis)
for img_file in "$COMPRESSED_DIR"/img_*.jpg; do
  [ -f "$img_file" ] || continue

  # Check file size (should be <100KB after compression)
  SIZE=$(stat -f%z "$img_file" 2>/dev/null || stat -c%s "$img_file" 2>/dev/null || echo "0")

  # Skip if still too large (compression failed)
  if [ "$SIZE" -gt 102400 ]; then
    echo "[Extract] ⚠ skipping $img_file (${SIZE} bytes > 100KB, compression may have failed)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if [ "$SIZE" -lt 1000 ]; then
    echo "[Extract] ⚠ skipping $img_file (too small, likely failed download)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  PROCESSED=$((PROCESSED + 1))
  echo "[Extract] ████████░░ | analyzing compressed image $PROCESSED: $img_file (${SIZE} bytes)"

  # Read ONE compressed image
  Read("$img_file")

  # 🚨 CRITICAL: If read fails or image is unreadable:
  # - Return "[ERROR] Unable to read image"
  # - NEVER guess or make up content!

  # Describe immediately using visual analysis
  # Generate structured description based on actual visible content

  # Store description
  IMAGE_DESCRIPTIONS="${IMAGE_DESCRIPTIONS}
---
**[Image ${PROCESSED}: {alt_from_metadata or 'Figure'}]**
Type: {flowchart|architecture|screenshot|chart|table|photo}

{detailed_visual_description_from_actual_image}

Key elements:
- {element_1}
- {element_2}
- {element_3}
---
"

  # Limit to 15 images max (increased from 5)
  if [ "$PROCESSED" -ge 15 ]; then
    echo "[Extract] ⚠ reached max 15 images, stopping"
    break
  fi
done

echo "[Extract] ██████████ | processed $PROCESSED images, skipped $SKIPPED"
```

**Step 4.3: Image Description Templates**

Use appropriate template based on detected image type:

| Type | Template Focus |
|------|----------------|
| `flowchart` | Nodes, connections, flow direction, decision points |
| `architecture` | Layers, components, relationships, data flow |
| `screenshot` | UI elements, layout, visible text, interactive elements |
| `chart` | Chart type, data series, axes, trends, key values |
| `table` | Headers, rows, key data points |
| `photo` | Subject, context, relevant details |

Example descriptions:

```markdown
---
**[Image 1: 服务商招商流程图]**
Type: flowchart

整体流程：服务商入驻 → 创建邀请码 → 商家扫码 → 商家激活 → 合作生效

关键节点：
- 起点：服务商完成入驻审核
- 决策点：商家是否在10天内完成激活
- 终点：合作状态变为"合作中"或"已失效"

流向说明：
1. 服务商创建邀请链接后生成唯一邀请码
2. 商家扫码后进入待激活状态
3. 10天内完成激活则绑定成功，否则失效
---
```

### Step 5: Generate Page Summary (for Crawl Mode)

When processing pages for crawl mode, always generate a summary for downstream transform agents.

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  📝 SUMMARY GENERATION - REQUIRED FOR CRAWL MODE                          ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  WHY: Transform agents cannot safely read 20+ pages (400KB+ content)     ║
║  SOLUTION: Generate 500-char summary per page during extraction          ║
║                                                                           ║
║  Summary captures:                                                        ║
║  - Main topic/purpose (1 sentence)                                       ║
║  - Key concepts (3-5 bullet points)                                      ║
║  - Important examples/patterns (if any)                                  ║
║  - Links to related topics                                               ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

**Summary Generation Template:**

```markdown
## Page Summary

**Title**: {page_title}
**URL**: {page_url}
**Relevance**: {score}/10

### Main Topic
{one_sentence_summary}

### Key Points
- {key_point_1}
- {key_point_2}
- {key_point_3}

### Keywords
{comma_separated_keywords}
```

**Output File Structure (Crawl Mode):**
```
{output_dir}/pages/
├── 001_page_title.md        # Full extracted content
├── 001_page_title.summary   # 500-char summary (NEW)
├── 002_another_page.md
├── 002_another_page.summary
└── ...
```

### Step 6: Combine and Return Markdown

```markdown
---
source: {url}
title: {extracted_title}
type: url
extracted_at: {timestamp}
---

# {Title}

{content}

---
**[Image: {description}]**
{image_description_as_text}
---
```

---

## Image Processing Flow

### Step 1: Size Check (MANDATORY)
```bash
SIZE=$(stat -f%z "{image_path}" 2>/dev/null || stat -c%s "{image_path}" 2>/dev/null || echo "0")

if [ "$SIZE" -gt 300000 ]; then
  echo "MUST compress before reading"
fi
```

### Step 2: Compress if Needed
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/compress-image.sh" "{input}" "{output}" 800

# Verify
CSIZE=$(stat -f%z "{output}" 2>/dev/null || stat -c%s "{output}")
if [ "$CSIZE" -gt 300000 ]; then
  # More aggressive
  "${CLAUDE_PLUGIN_ROOT}/scripts/compress-image.sh" "{input}" "{output}" 640
fi
```

### Step 3: Read ONE Image
```
Read("{compressed_image}")
# Describe immediately
# Store description as text
# Release image from context
```

### Step 4: Return Text Description
```markdown
---
**[Image: {filename}]**
Type: {flowchart|screenshot|chart|photo}

{structured_description}
---
```

---

## Directory Processing Flow

### Step 1: Scan
```bash
find "{directory}" -type f \
  ! -path "*/node_modules/*" \
  ! -path "*/.git/*" \
  ! -name "*.lock" \
  ! -name ".DS_Store"
```

### Step 2: Batch Planning (content-safeguard)
```
files = scan_result
batches = split(files, batch_size=5)

for batch in batches:
  for file in batch:
    process_one(file)  # Sequential, not parallel
```

### Step 3: Per-File Summary
```markdown
### {filename}
**Type**: {type} | **Size**: {size}
{summary - max 500 chars}
```

---

## Link Extraction (Crawl Mode)

When `crawl_mode=true`, also extract links for coordinator.

### Apply relevance-scorer Patterns
```bash
# Score each link
score_link() {
  local url="$1" anchor="$2" context="$3" topic="$4"
  local score=0

  # URL match
  echo "$url" | grep -qiE "$topic" && score=$((score + 3))

  # Anchor text match (most important)
  echo "$anchor" | grep -qiE "$topic" && score=$((score + 5))

  # Context match
  echo "$context" | grep -qiE "$topic" && score=$((score + 2))

  [ "$score" -gt 10 ] && score=10
  echo "$score"
}
```

### Output Links File
```json
{
  "page_id": "001",
  "page_url": "{url}",
  "page_relevance": 9,
  "links": [
    {
      "url": "{link_url}",
      "anchor_text": "{text}",
      "relevance_score": 8
    }
  ]
}
```

Write to: `{output_dir}/links/{page_id}.json`

---

## Image Description Templates

### Flowchart
```markdown
---
**[Image: {title}]**
Type: 流程图

**Nodes**: {node_1} → {node_2} → {node_3}
**Key Path**: {description}
---
```

### UI Screenshot
```markdown
---
**[Image: {title}]**
Type: 界面截图

**Layout**: {description}
**Elements**: {element_list}
**Visible Text**: "{extracted_text}"
---
```

### Data Chart
```markdown
---
**[Image: {title}]**
Type: 数据图表 ({chart_type})

**Summary**: {data_points}
**Trend**: {insight}
---
```

---

## Output Format

```markdown
---
source: {url_or_path}
title: {title}
type: {url|image|pdf|directory}
extracted_at: {timestamp}
relevance: {score}  # if crawl_mode
stats:
  chars: {count}
  images: {count}
---

# {Title}

{content}

---
**[Image 1: {label}]**
{description}
---

{more_content}
```

---

## Self-Check Before Return

```
□ Total output < 50,000 chars?
□ No raw image data in output?
□ All images converted to text?
□ Metadata header included?
□ Source attributed?
```

**If output too large:**
1. Remove less important sections
2. Shorten image descriptions
3. Summarize instead of full text
4. Return structure only (last resort)

---

## Progress Output (REQUIRED - USE TodoWrite)

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🚨 NEVER USE TEXT OUTPUT FOR PROGRESS - USE TodoWrite INSTEAD 🚨        ║
║                                                                           ║
║  Text output accumulates in context → "Prompt is too long" error          ║
║  TodoWrite renders in UI statusline → No context growth                   ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

**Use TodoWrite to update progress:**

```javascript
// Initialize task list at start
TodoWrite({
  todos: [
    { content: "Extract content", status: "in_progress", activeForm: "Checking snapshot size..." },
    { content: "Process images", status: "pending", activeForm: "Processing images" },
    { content: "Generate output", status: "pending", activeForm: "Generating output" }
  ]
})

// Update activeForm for detailed status
TodoWrite({
  todos: [
    { content: "Extract content", status: "in_progress", activeForm: "Reading snapshot (12K chars)..." },
    ...
  ]
})

// Mark complete and move to next
TodoWrite({
  todos: [
    { content: "Extract content", status: "completed", activeForm: "Extracted content" },
    { content: "Process images", status: "in_progress", activeForm: "Compressing (2/5)..." },
    ...
  ]
})
```

**activeForm examples:**
- `"Checking snapshot size..."`
- `"Reading chunk 2/4 (10K chars)..."`
- `"Compressing images (3/5)..."`
- `"⏸ LOGIN REQUIRED"`
- `"⚠ Using screenshot fallback"`
- `"✓ Done: 001_doc.md"`

**Final output (text only at end):**
```markdown
### ✓ Extraction Complete
- Output: `001_doc.md` (8,234 chars)
- Images: 3 processed, 2 skipped
```

---

## Quick Reference

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🚨 PROMPT TOO LONG = AGENT FAILURE - PREVENT AT ALL COSTS 🚨            ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  NEVER: Read file >500 lines without chunking                            ║
║  NEVER: Read multiple images at once                                     ║
║  NEVER: Read image > 300KB without compressing                           ║
║  NEVER: Return > 50,000 chars                                            ║
║                                                                           ║
║  ALWAYS: Check file size/line count BEFORE reading                       ║
║  ALWAYS: Use Read(limit: 500) for large files, chunk by chunk            ║
║  ALWAYS: Summarize each chunk before reading next                        ║
║  ALWAYS: Compress images to 800px width, <300KB                          ║
║  ALWAYS: Process one item at a time                                      ║
║  ALWAYS: Convert image to text immediately, release from context         ║
║                                                                           ║
║  CHUNKING: wc -l → if >500 → Read(limit:500) → summarize → next chunk   ║
║  COMPRESSION: "${CLAUDE_PLUGIN_ROOT}/scripts/compress-image.sh"          ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## Error Retry Mechanism

**Reference**: `config/limits.yaml` retry section.

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    RETRY CONFIGURATION                                    ║
╠═══════════════════════════════════════════════════════════════════════════╣
║  max_attempts: 3                                                          ║
║  initial_delay: 1 second                                                  ║
║  backoff_multiplier: 2 (1s → 2s → 4s)                                    ║
║  max_delay: 10 seconds                                                    ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

### Retryable Operations

| Operation | Retry | Fallback |
|-----------|-------|----------|
| File read | ✅ 3x | Report error |
| Image compress | ✅ 3x | Skip image, note in output |
| Snapshot parse | ✅ 3x | Use screenshot fallback |
| Screenshot read | ✅ 3x | Text-only output |

### Retry Logic

```bash
retry_with_backoff() {
  local cmd="$1"
  local max_attempts=3
  local delay=1

  for attempt in $(seq 1 $max_attempts); do
    if eval "$cmd"; then
      return 0
    fi
    echo "[Retry] attempt $attempt/$max_attempts failed, waiting ${delay}s..."
    sleep $delay
    delay=$((delay * 2))
    [ $delay -gt 10 ] && delay=10
  done
  return 1
}
```

### Error Reporting

When retry exhausted, report clearly:

```
[Extract] ████████░░ 80% | ⚠ image read failed after 3 attempts, skipping
```

Never silently fail. Always note what was skipped and why.
