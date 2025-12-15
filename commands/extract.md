---
description: Extract content from URL, images, PDF, directory, or git repo - with optional crawling and output transformation
allowed-tools:
  - mcp__plugin_knowledge-etl_playwright__browser_navigate
  - mcp__plugin_knowledge-etl_playwright__browser_wait_for
  - mcp__plugin_knowledge-etl_playwright__browser_snapshot
  # ⛔ browser_take_screenshot REMOVED - embeds image into context causing overflow!
  - mcp__plugin_knowledge-etl_playwright__browser_close
  - mcp__plugin_knowledge-etl_playwright__browser_click
  - mcp__plugin_knowledge-etl_playwright__browser_type
  - mcp__plugin_knowledge-etl_playwright__browser_scroll
  - mcp__plugin_knowledge-etl_playwright__browser_evaluate
  - mcp__plugin_knowledge-etl_playwright__browser_press_key
arguments:
  - name: source
    description: URL, image path, glob pattern, PDF path, directory, or git URL
    required: true
  - name: --with-depth
    description: "Enable crawling with specified depth (1-3). Example: --with-depth=2"
    required: false
  - name: --topic
    description: "Topic regex for relevance filtering. Example: --topic=\"API|接口|REST\""
    required: false
  - name: --max-pages
    description: "Maximum pages to crawl (default: 20). Example: --max-pages=50"
    required: false
  - name: --pipe
    description: "Transform output to format: skill, plugin, prompt, rag, docs, json"
    required: false
  - name: --output-dir
    description: "Output directory (default: .knowledge-etl). Example: --output-dir=./my-output"
    required: false
  - name: --engine
    description: "Extraction engine: auto (default), playwright, jina, trafilatura. See config/security.yaml for routing rules"
    required: false
  - name: --with-images
    description: "Extract and analyze images (default: false). Increases processing time"
    required: false
  - name: --compact-cph
    description: "Compact Chain of Thought - reduce verbose progress output, only show essential status"
    required: false
---

# Knowledge ETL Extract Command

Unified extraction that converts **any content source to pure text Markdown**. Supports crawling with depth traversal and output transformation to various formats.

---

## ⛔ CRITICAL: MAIN CONTEXT SAFETY RULES

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🚨 PROMPT TOO LONG = PLUGIN FAILURE - 100% PREVENTION REQUIRED 🚨        ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  ⛔⛔⛔ ABSOLUTELY FORBIDDEN IN MAIN CONTEXT ⛔⛔⛔                        ║
║                                                                           ║
║  ❌ browser_take_screenshot - EMBEDS IMAGE INTO CONTEXT!                 ║
║     Even ONE screenshot can cause overflow. NEVER use it.                ║
║     Tool has been REMOVED from allowed-tools list.                       ║
║                                                                           ║
║  ❌ Read(snapshot.md) - could be 500KB+                                   ║
║  ❌ Read(screenshot.png) - could be 2MB+                                  ║
║  ❌ Read any captured content file                                        ║
║  ❌ Read any user-provided large file                                     ║
║                                                                           ║
║  ONLY allowed in MAIN context:                                           ║
║  ✅ browser_snapshot - TEXT only, saves to file, no context impact       ║
║  ✅ browser_evaluate - extract data as text/JSON                         ║
║  ✅ browser_navigate, wait_for, click, close - navigation only           ║
║  ✅ Bash: stat, head -n 10, wc -l (size/preview only)                    ║
║  ✅ Bash: curl for image download (no context impact)                    ║
║  ✅ Task(subagent) - delegate ALL content reading                        ║
║                                                                           ║
║  ALL content processing → Task(extractor) in isolated context            ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

---

## STEP 0: Engine Selection & Security Check (REQUIRED)

**Reference**: `config/security.yaml` for URL routing rules.

### Engine Selection Logic

```bash
# Determine extraction engine based on URL and --engine flag

select_engine() {
  local url="$1"
  local requested_engine="${2:-auto}"

  # Extract domain from URL
  domain=$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')

  # ─────────────────────────────────────────────────────────────────
  # SECURITY CHECK: Force local for internal/sensitive URLs
  # ─────────────────────────────────────────────────────────────────

  # Internal domains (from security.yaml)
  INTERNAL_PATTERNS=(
    "*.alibaba-inc.com"
    "alidocs.dingtalk.com"
    "*.yuque.com"
  )

  # Private networks
  PRIVATE_PATTERNS=(
    "localhost" "127.0.0.1" "::1"
    "10.*" "192.168.*" "172.16.*" "172.17.*" "172.18.*" "172.19.*"
    "172.20.*" "172.21.*" "172.22.*" "172.23.*" "172.24.*" "172.25.*"
    "172.26.*" "172.27.*" "172.28.*" "172.29.*" "172.30.*" "172.31.*"
  )

  # Sensitive URL patterns
  SENSITIVE_PATTERNS=(
    "*login*" "*signin*" "*auth*" "*oauth*" "*sso*"
    "*admin*" "*dashboard*" "*internal*" "*intranet*"
  )

  # Check if URL matches any force_local pattern
  for pattern in "${INTERNAL_PATTERNS[@]}" "${PRIVATE_PATTERNS[@]}"; do
    if [[ "$domain" == $pattern ]]; then
      echo "playwright"  # Force local
      return
    fi
  done

  for pattern in "${SENSITIVE_PATTERNS[@]}"; do
    if [[ "$url" == $pattern ]]; then
      echo "playwright"  # Force local
      return
    fi
  done

  # ─────────────────────────────────────────────────────────────────
  # USER REQUESTED ENGINE
  # ─────────────────────────────────────────────────────────────────
  case "$requested_engine" in
    playwright|jina|trafilatura)
      echo "$requested_engine"
      ;;
    auto)
      # Default to playwright (safest)
      # Can try jina for public URLs if configured
      echo "playwright"
      ;;
    *)
      echo "playwright"
      ;;
  esac
}
```

### Engine Capabilities

| Engine | 速度 | 登录支持 | 图片提取 | 隐私安全 | 适用场景 |
|--------|------|----------|----------|----------|----------|
| **playwright** | 慢 | ✅ | ✅ | ✅ 本地 | 内部系统、需登录 |
| **jina** | 快 | ❌ | ⚠️ URL | ❌ 第三方 | 公开文档 |
| **trafilatura** | 中 | ❌ | ❌ | ✅ 本地 | 公开文章 |

### Security Output

```
┌─ SECURITY ──────────────────────────────────────┐
│ URL:    alidocs.dingtalk.com/...               │
│ Domain: alidocs.dingtalk.com                   │
│ Match:  internal_domains                       │
│ Engine: playwright (forced local)              │
└────────────────────────────────────────────────┘
```

---

## STEP 1: Task Analysis & Plan Output (REQUIRED)

**Before executing, analyze the task complexity and output a plan:**

```
┌─ PLAN ─────────────────────────────────────────┐
│ Engine:      {playwright|jina|trafilatura}     │
│ 1. Extract   → {what}                          │
│ 2. Process   → {what} ║ {parallel}             │
│ 3. Transform → {pipe} (if specified)           │
│ 4. Validate  → {validator}                     │
└────────────────────────────────────────────────┘
```

### Task Complexity Detection

| Condition | Complexity | Plan Steps |
|-----------|------------|------------|
| Single URL, no pipe | Simple | Extract only |
| Single URL + pipe | Medium | Extract → Transform → Validate |
| --with-depth | Complex | Crawl → Summarize → Transform → Validate |
| Directory (>10 files) | Complex | Scan → Batch Extract → Merge |
| Large image (>1MB) | Medium | Compress → Extract |
| Git repo | Complex | Clone → Scan → Extract |

### Plan Examples

**Simple (single page - internal):**
```
┌─ PLAN ─────────────────────────────────────────┐
│ Engine:      playwright (forced: internal)     │
│ 1. Extract   → capture page snapshot           │
└────────────────────────────────────────────────┘
```

**Simple (single page - public with jina):**
```
┌─ PLAN ─────────────────────────────────────────┐
│ Engine:      jina (public URL)                 │
│ 1. Extract   → curl r.jina.ai/{url}            │
└────────────────────────────────────────────────┘
```

**Medium (single page + skill):**
```
┌─ PLAN ─────────────────────────────────────────┐
│ Engine:      playwright                        │
│ 1. Extract   → capture page                    │
│ 2. Transform → skill (built-in template)       │
│ 3. Validate  → self-check output size          │
└────────────────────────────────────────────────┘
```

**Complex (crawl + skill):**
```
┌─ PLAN ─────────────────────────────────────────┐
│ Engine:      playwright                        │
│ 1. Crawl     → depth:2 max:20 topic-filter     │
│ 2. Summarize → INDEX.md + REPORT.md            │
│ 3. Transform → skill (built-in template)       │
│ 4. Validate  → self-check output size          │
└────────────────────────────────────────────────┘
```

**Complex (directory with parallel):**
```
┌─ PLAN ─────────────────────────────────────────┐
│ 1. Scan      → count files, detect types       │
│ 2. Extract   → batch(5) ║ compress ║ describe  │
│ 3. Merge     → combine all to INDEX.md         │
│ 4. Transform → rag                             │
└────────────────────────────────────────────────┘
```

---

## Progress Output During Execution (USE TodoWrite)

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🚨 USE TodoWrite FOR PROGRESS - NEVER TEXT OUTPUT 🚨                    ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  ❌ WRONG: print "[Extract] ██░░░░░░░░ 20% | page loaded"                ║
║  ❌ WRONG: Output text after each step (causes context overflow!)        ║
║                                                                           ║
║  ✅ RIGHT: Use TodoWrite to update task status                           ║
║  ✅ RIGHT: TodoWrite renders in UI statusline (persistent, no context)   ║
║                                                                           ║
║  WHY: Text output accumulates → "Prompt is too long" error               ║
║       TodoWrite UI updates → Zero context growth                         ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

**TodoWrite Usage Pattern:**

```javascript
// STEP 1: Initialize at start
TodoWrite({
  todos: [
    { content: "Extract page content", status: "in_progress", activeForm: "Navigating to URL..." },
    { content: "Process images", status: "pending", activeForm: "Processing images" },
    { content: "Transform output", status: "pending", activeForm: "Transforming output" },
    { content: "Validate results", status: "pending", activeForm: "Validating results" }
  ]
})

// STEP 2: Update activeForm during work
// After navigate:
TodoWrite({ todos: [
  { content: "Extract page content", status: "in_progress", activeForm: "Page loaded, capturing snapshot..." },
  ...
]})

// After snapshot:
TodoWrite({ todos: [
  { content: "Extract page content", status: "in_progress", activeForm: "Snapshot captured (12K chars)" },
  ...
]})

// STEP 3: Mark complete, start next
TodoWrite({ todos: [
  { content: "Extract page content", status: "completed", activeForm: "Extracted page content" },
  { content: "Process images", status: "in_progress", activeForm: "Downloading images (3/5)..." },
  ...
]})
```

**activeForm Examples:**
- `"Navigating to URL..."` → `"Page loaded, waiting..."` → `"Capturing snapshot..."`
- `"Downloading images (2/5)..."` → `"Compressing (1.2MB→280KB)..."`
- `"⏸ LOGIN REQUIRED - complete in browser"`
- `"⚠ Anti-scrape detected, using screenshot"`
- `"✓ Done: extracted.md (8K chars)"`

**Final Summary (text output only at completion):**
```markdown
### ✓ Extraction Complete
- Output: `.knowledge-etl/extracted.md` (8,234 chars)
- Images: 5 processed, 2 skipped
- Time: 15.2s
```

---

## Architecture

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    PLUGGABLE PIPELINE ARCHITECTURE                        ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  [Input Sources]        [Core]           [Output Pipes]                   ║
║  ───────────────       ──────           ────────────────                  ║
║  • URL (single)   ─┐                 ┌─▶ • --pipe=skill                   ║
║  • URL (crawl)    ─┤                 ├─▶ • --pipe=plugin                  ║
║  • Local file     ─┼──▶ Extractor ───┼─▶ • --pipe=prompt                  ║
║  • Directory      ─┤    Agent        ├─▶ • --pipe=rag                     ║
║  • Glob pattern   ─┤    (isolated)   ├─▶ • --pipe=docs                    ║
║  • Git repo       ─┘                 └─▶ • --pipe=json                    ║
║                                                                           ║
║  IRON RULE: Every operation runs in isolated agent context               ║
║             to PREVENT "Prompt Too Long" errors.                          ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

## Input

- **Source**: `$ARGUMENTS.source`
  - URL (http/https) - single page or with --with-depth for crawling
  - Image path (png, jpg, etc.)
  - Glob pattern (*.png, docs/*.md)
  - PDF path
  - Directory path
  - Git URL (git@..., https://github.com/...)

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--with-depth=N` | Enable crawling with depth N (1-3) | disabled |
| `--topic=REGEX` | Topic filter regex for relevance scoring | none (all) |
| `--max-pages=N` | Maximum pages to crawl | 20 |
| `--pipe=FORMAT` | Transform output: skill, plugin, prompt, rag, docs, json | none |
| `--output-dir=PATH` | Output directory | .knowledge-etl |

## Output

**Pure Markdown text** with:
- YAML frontmatter (source, title, stats)
- Text content
- Image descriptions (text, not files)

**With --pipe**: Additional formatted output in `output/{format}/`

## Execution

### Engine Dispatch (STEP 2)

Based on STEP 0 security check, dispatch to appropriate engine:

```
┌─ ENGINE DISPATCH ────────────────────────────────────────────────┐
│                                                                   │
│  engine = "playwright" (default/internal)                         │
│  ├── Use Playwright MCP for full browser automation             │
│  ├── Supports: login, JS rendering, images, cookies             │
│  └── See: "For URLs (playwright)" section below                  │
│                                                                   │
│  engine = "jina" (public URLs only)                               │
│  ├── Fast: Single curl call to r.jina.ai                         │
│  ├── Clean: Returns pure Markdown directly                       │
│  ├── Script: scripts/extract-jina.sh                             │
│  └── Usage:                                                       │
│      Bash: "${CLAUDE_PLUGIN_ROOT}/scripts/extract-jina.sh"       │
│            "{URL}" "{OUTPUT_DIR}"                                 │
│                                                                   │
│  engine = "trafilatura" (local, no JS)                            │
│  ├── Local: No external API calls                                │
│  ├── Script: scripts/extract-trafilatura.sh                      │
│  └── Usage:                                                       │
│      Bash: "${CLAUDE_PLUGIN_ROOT}/scripts/extract-trafilatura.sh"│
│            "{URL}" "{OUTPUT_DIR}"                                 │
│                                                                   │
└──────────────────────────────────────────────────────────────────┘
```

**Jina Engine Example:**
```bash
# For public URLs - fast extraction
Bash("${CLAUDE_PLUGIN_ROOT}/scripts/extract-jina.sh" \
     "https://docs.python.org/3/library/json.html" \
     ".knowledge-etl/python-json")

# Output: .knowledge-etl/python-json/docs_python_org_3_library_json_html.md
```

**Security Block Example:**
```bash
# Internal URL → Script will exit with error code 2
Bash("${CLAUDE_PLUGIN_ROOT}/scripts/extract-jina.sh" \
     "https://alidocs.dingtalk.com/..." \
     ".knowledge-etl/")

# Output: [error] Security: alidocs.dingtalk.com is an internal domain.
# Action: Fall back to playwright engine
```

---

### For URLs (playwright engine)

```
╔════════════════════════════════════════════════════════════════════════════╗
║  ⚠️ CRITICAL: MCP TOOLS NOT AVAILABLE IN SUBAGENTS                        ║
║                                                                            ║
║  Playwright MCP tools only work in MAIN context, not in Task agents.      ║
║  Solution: Main context captures URL, then delegates LOCAL files.         ║
╚════════════════════════════════════════════════════════════════════════════╝
```

**Step-by-step execution (3-phase):**

```
PHASE 1: MAIN CONTEXT - Capture URL content + Extract Images
─────────────────────────────────────────────────────────────
Execute Playwright in main context (MCP tools available here):

Step 1.1: Navigate and capture page (TEXT ONLY - NO SCREENSHOT!)
─────────────────────────────────────────────────────────────────
1. mcp__playwright__browser_navigate(url: "{URL}")
2. mcp__playwright__browser_wait_for(time: 3)
3. mcp__playwright__browser_press_key(key: "End")  # Trigger lazy-load
4. mcp__playwright__browser_wait_for(time: 2)
5. mcp__playwright__browser_snapshot(filename: "snapshot.md")
# ⛔ NO browser_take_screenshot - it embeds image into context!

Step 1.2: Check for login (NEVER read full file!)
──────────────────────────────────────────────────
- Use Bash to check first 10 lines ONLY:
  head -n 10 .playwright-mcp/snapshot.md | grep -iE "登录|login|password|SSO|sign.?in"
- If login detected:
  - AskUserQuestion: "请在浏览器中完成登录"
  - Re-capture after user confirms

Step 1.3: Extract image URLs from page (NEW)
────────────────────────────────────────────
Use browser_evaluate to get image URLs with filtering:

mcp__playwright__browser_evaluate({
  function: "() => {
    const imgs = Array.from(document.querySelectorAll('img'));
    return imgs
      .filter(img => {
        // Filter out decorative images
        const w = img.naturalWidth || img.width;
        const h = img.naturalHeight || img.height;
        if (w < 100 || h < 100) return false;

        const src = (img.src || '').toLowerCase();
        const alt = (img.alt || '').toLowerCase();

        // Skip icons, logos, avatars
        const skipPatterns = ['icon', 'logo', 'avatar', 'emoji', 'button', 'arrow'];
        if (skipPatterns.some(p => src.includes(p) || alt.includes(p))) return false;

        return true;
      })
      .slice(0, 5)  // Max 5 images
      .map((img, i) => ({
        index: i,
        src: img.src,
        alt: img.alt || '',
        width: img.naturalWidth || img.width,
        height: img.naturalHeight || img.height
      }));
  }"
})

→ Write result to: .playwright-mcp/images.json (using Bash echo)

Step 1.4: Download images (CONTEXT-SAFE METHOD)
────────────────────────────────────────────────

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🚨 NEVER USE browser_take_screenshot IN A LOOP FOR IMAGE DOWNLOAD 🚨    ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  Each screenshot embeds image data into conversation context!            ║
║  Multiple screenshots = RAPID context explosion = "Prompt is too long"   ║
║                                                                           ║
║  ❌ DEPRECATED: Click-to-preview screenshot loop                         ║
║  ✅ CORRECT: browser_evaluate + curl download (zero context impact)      ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

Download images using curl (ONLY correct method)
─────────────────────────────────────────────────
# Get cookies for authenticated image download
mcp__playwright__browser_evaluate({
  function: "() => document.cookie"
})
→ Store as $COOKIES

# Download images in parallel (Bash)
for each image in images.json:
  curl -s -L \
    -H "Cookie: $COOKIES" \
    -H "Referer: {URL}" \
    -H "User-Agent: Mozilla/5.0..." \
    --max-time 10 \
    -o ".playwright-mcp/img_{index}.jpg" \
    "{image.src}" &
wait  # Wait for all downloads

# Verify downloads - skip invalid files (don't use screenshot fallback!)
for img in .playwright-mcp/img_*.jpg:
  # Check if file is actually an image or an error page
  file_type=$(file -b "$img" | head -c 10)
  if [[ "$file_type" != "JPEG"* && "$file_type" != "PNG"* && "$file_type" != "WebP"* ]]; then
    echo "[Extract] ⚠ download failed for $img, skipping (auth-protected)"
    rm -f "$img"  # Remove invalid file
    # NOTE: Do NOT use screenshot fallback - causes context overflow!
  fi

# Compress large images
for img in .playwright-mcp/img_*.jpg:
  SIZE=$(stat -f%z "$img" 2>/dev/null || stat -c%s "$img" 2>/dev/null || echo "0")
  if [ "$SIZE" -gt 300000 ]; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/compress-image.sh" "$img" "$img" 800
  fi

print "[Extract] ████████░░ 80% | images captured"

Step 1.5: Close browser
───────────────────────
mcp__playwright__browser_close()

PHASE 2: SUBAGENT - Process local files (isolated context)
───────────────────────────────────────────────────────────
Delegate to extractor agent for content processing:

Task(
  subagent_type: "knowledge-etl:extractor",
  prompt: """
    Process captured content from: {URL}

    Local files available:
    - .playwright-mcp/snapshot.md (text content)
    - .playwright-mcp/screenshot.png (visual fallback)
    - .playwright-mcp/images.json (image metadata)
    - .playwright-mcp/img_*.jpg (downloaded page images, pre-compressed)

    ⚠️ EXTRACTION PRIORITY:
    Snapshot FIRST (text) → Screenshot FALLBACK ONLY (when blocked)

    Steps:
    1. Read snapshot.md FIRST (chunk if >500 lines)
    2. Read images.json for image metadata
    3. For each img_*.jpg (if exists):
       a. Check size (<300KB required)
       b. Read ONE image at a time
       c. Describe image (type + content)
       d. Release from context before next image
    4. Combine: text content + image descriptions
    5. Write output to: {output_dir}/extracted.md

    Output format:
    ---
    source: {URL}
    title: {extracted_title}
    stats:
      chars: {count}
      images: {processed_count}
    ---

    {text_content}

    ---
    **[Image 1: {alt or description}]**
    Type: {flowchart|architecture|screenshot|chart}
    {detailed_visual_description}
    ---

    Follow safety limits strictly.
  """
)
```

**Why 2-phase:**
| Phase | Context | MCP Tools | Purpose |
|-------|---------|-----------|---------|
| 1 | Main | ✅ Available | Network capture |
| 2 | Subagent | ❌ Not available | Content processing (isolated) |

**Why this works:**

| Aspect | Old Approach (broken) | New Approach (correct) |
|--------|----------------------|------------------------|
| Playwright runs in | Main context | Extractor agent (isolated) |
| Screenshot data goes to | Main context → OVERFLOW | Agent context → safe |
| Context isolation | Partial (only processing) | Complete (fetch + process) |

### For Local Files (Images, PDFs, Directories)

**Delegate directly to the extractor agent** for isolated context:

```
Task(
  subagent_type: "knowledge-etl:extractor",
  prompt: """
    Extract content from: $ARGUMENTS.source

    Requirements:
    - Extract all text content
    - Convert images to text descriptions
    - Return pure Markdown, no file references
    - Follow safety limits strictly
    - Use fallback strategies when needed
  """
)
```

## Safety Limits (Enforced by Agent)

| Resource | Limit |
|----------|-------|
| Image size | 300 KB max (compress if larger) |
| Image width | 800 px max |
| Images per session | 5 max |
| Text per file | 20,000 chars (truncate beyond) |
| Snapshot | 30,000 chars (truncate beyond) |
| Total output | 50,000 chars |
| PDF pages | 15 max |
| Batch size | 5 files |

## Processing Strategies

| Input Type | Strategy |
|------------|----------|
| Single URL | Snapshot → Screenshot fallback |
| Single Image | Size check → Compress → Describe |
| Single PDF | Read → Summarize if >15 pages |
| Multiple Images | One-by-one → Describe each → Combine |
| Directory | Scan → Batch(5) → Summarize each |

## Obstacle Handling

| Obstacle | Resolution |
|----------|------------|
| Login required | Report to user, wait for login |
| Anti-scrape | Screenshot + visual analysis |
| Prompt too large | Segment processing |
| Image unreadable | Mark as "[cannot read image]" |

## Output Format

```markdown
---
source: [URL or path]
title: [Extracted title]
type: [url|image|pdf|directory]
extracted_at: [ISO timestamp]
stats:
  chars: [total chars]
  images: [images processed]
  files: [files processed]
---

# [Title]

[Text content...]

---
**[Image 1: Description]**
[Detailed image description in text]
---

[More content...]
```

## Examples

**Web page:**
```
/knowledge-etl:extract https://docs.example.com/guide

→ Extracts text via snapshot
→ Describes images in text
→ Returns pure Markdown
```

**Large screenshot:**
```
/knowledge-etl:extract ./screenshot-4k.png

→ Compresses to 800px width
→ Extracts visible text (OCR)
→ Describes visual elements
→ Returns text description
```

**Directory:**
```
/knowledge-etl:extract ./docs/

→ Scans directory (excludes node_modules, .git)
→ Processes in batches of 5
→ Generates summary per file
→ Returns combined index
```

**Glob pattern:**
```
/knowledge-etl:extract "./images/*.png"

→ Expands glob to file list
→ Processes one by one
→ Describes each image
→ Returns combined text
```

---

## Crawl Mode (--with-depth)

When `--with-depth` is specified, execute multi-page extraction with URL capture loop:

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    CRAWL MODE EXECUTION                                   ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  ⚠️ MCP tools only work in MAIN context (this command).                   ║
║  URL capture loop runs HERE, processing delegated to subagents.          ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝

STEP 1: Initialize crawl state
──────────────────────────────
mkdir -p {output_dir}/pages {output_dir}/links
Write config.json with: depth, topic, max_pages, entry_url
Write queue.json with: [{url: entry_url, depth: 0, priority: 10}]
Write visited.json with: {urls: {}, count: 0}

STEP 2: URL Capture Loop (MAIN CONTEXT - MCP available)
────────────────────────────────────────────────────────
page_id = 0
while queue not empty AND page_id < max_pages:

  # 2a. Read queue, get highest priority URL
  queue = Read(queue.json)
  url = pop_highest_priority(queue)

  # Skip if visited
  if url in visited: continue

  page_id += 1

  # 2b. Capture URL using Playwright (TEXT SNAPSHOT ONLY!)
  mcp__playwright__browser_navigate(url: url)
  mcp__playwright__browser_wait_for(time: 3)
  mcp__playwright__browser_snapshot(filename: "page_{page_id}.md")
  # ⛔ NO browser_take_screenshot - causes context overflow!

  # Check for login (NEVER Read full file - use Bash head only!)
  # Bash: head -n 10 .playwright-mcp/page_{page_id}.md | grep -iE "登录|login|password|SSO"
  if login_detected:
    AskUserQuestion("请在浏览器中完成登录")
    # Re-capture after login

  # 2c. Delegate processing to extractor (isolated context)
  Task(
    subagent_type: "knowledge-etl:extractor",
    prompt: "Process .playwright-mcp/page_{page_id}.md ..."
  )
  # Extractor writes: pages/{page_id}_*.md, links/{page_id}.json

  # 2d. Read extracted links, add to queue
  links = Read("{output_dir}/links/{page_id}.json")
  for link in links:
    if link.depth <= max_depth AND link.relevance >= 5:
      add_to_queue(link, priority=link.relevance + parent_bonus)

  # 2e. Mark URL as visited
  add_to_visited(url, page_id)

  # 2f. Report progress
  print("[Crawl] {page_id}/{max_pages} | {url} | relevance: {score}")

mcp__playwright__browser_close()

STEP 3: Summarize (delegate to summarizer)
──────────────────────────────────────────
Task(
  subagent_type: "knowledge-etl:crawler-summarizer",
  prompt: "Generate INDEX.md and REPORT.md for {output_dir}..."
)

STEP 4: Transform (if --pipe specified)
───────────────────────────────────────
if pipe:
  Task(
    subagent_type: "knowledge-etl:output-transformer",
    prompt: "Transform to {pipe} format..."
  )

STEP 5: Return summary
```

**Crawl Examples:**

```bash
# Basic crawl with depth 2
/knowledge-etl:extract https://docs.example.com --with-depth=2

# Crawl with topic filter (regex)
/knowledge-etl:extract https://api.example.com --with-depth=2 --topic="API|REST|endpoint|认证"

# Crawl and convert to skill
/knowledge-etl:extract https://docs.example.com/api --with-depth=2 --topic="API" --pipe=skill

# Crawl and generate RAG chunks
/knowledge-etl:extract https://docs.example.com --with-depth=3 --max-pages=50 --pipe=rag
```

---

## Pipeline Mode (--pipe)

When `--pipe` is specified, transform extracted content to target format:

```
Supported formats:
  --pipe=skill    → Claude Code Skill (skill.yaml + SKILL.md)
  --pipe=plugin   → Claude Code Plugin structure
  --pipe=prompt   → System prompt for LLMs
  --pipe=rag      → RAG-friendly chunks for vector DB
  --pipe=docs     → Documentation structure
  --pipe=json     → Structured JSON knowledge base
```

**Pipeline is executed AFTER extraction completes:**

```
1. Extraction phase (extractor or crawler)
   → Raw content saved to {output_dir}/pages/

2. Summarization phase (if crawl mode)
   → INDEX.md and REPORT.md generated

3. Transformation phase (if --pipe specified)
   → Task(
       subagent_type: "knowledge-etl:output-transformer",
       prompt: """
         Transform extracted content to: {pipe} format

         Source directory: {output_dir}
         Topic: {topic}

         Read REPORT.md (or single page content) and transform to
         {pipe} format. Follow the template for that format.

         Output to: {output_dir}/output/{pipe}/
       """
     )

4. Return summary and output location
```

**Pipeline Examples:**

```bash
# Single page to skill
/knowledge-etl:extract https://docs.example.com/quick-start --pipe=skill

# Directory to RAG chunks
/knowledge-etl:extract ./docs --pipe=rag

# Git repo to system prompt
/knowledge-etl:extract https://github.com/user/library --pipe=prompt

# Crawl to plugin
/knowledge-etl:extract https://api.example.com --with-depth=2 --topic="API" --pipe=plugin
```

---

## Git Repository Support

When source is a git URL, extract documentation and code signatures:

```
Detection patterns:
  • git@github.com:user/repo.git
  • https://github.com/user/repo.git
  • https://github.com/user/repo

Extraction:
  1. Clone repo (shallow, to temp dir)
  2. Process README and docs/*.md
  3. Extract API signatures from code
  4. Generate codebase overview

Example:
/knowledge-etl:extract https://github.com/user/awesome-lib --pipe=skill
```

---

## Output Directory Structure

```
{output_dir}/
├── config.json           # Extraction configuration
├── pages/                # Extracted page content
│   ├── 001_*.md
│   └── ...
├── links/                # Discovered links (crawl mode)
│   └── *.json
├── INDEX.md              # Page index (crawl mode)
├── REPORT.md             # Topic report (crawl mode)
└── output/               # Transformed output (--pipe)
    └── {format}/
        └── ...
```

---

## Complete Execution Flow

### Step 1: Analyze & Plan

```
1. Parse $ARGUMENTS.source and options
2. Detect task complexity (simple/medium/complex)
3. Generate plan steps
4. OUTPUT PLAN to user (REQUIRED)
```

### Step 2: Execute Plan Steps Sequentially

```
FOR EACH step in plan:
  1. Output progress line: [N/M Step] ████░░░░░░ X% | status...
  2. Execute step
  3. Report key result (file, size, status)
  4. Continue to next step

IF any step fails:
  → Output warning: [N/M Step] ████░░░░░░ X% | ⚠ reason
  → Apply fallback if available
  → Continue or abort based on severity
```

### Step 3: Final Summary

```
━━━ DONE (Xs) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Step 1 ██████████ ✓ Xs
Step 2 ██████████ ✓ Xs
...

→ output files list
```

---

## Execution Modes

```
Parse $ARGUMENTS.source and options

IF source is URL AND --with-depth specified:
  → Crawl mode: Use crawler-coordinator agent

ELSE IF source is git URL:
  → Git mode: Clone and extract docs

ELSE:
  → Single extraction: Use extractor agent

THEN IF --pipe specified:
  → Transform: Use output-transformer agent

FINALLY:
  → Return summary and output location
```
