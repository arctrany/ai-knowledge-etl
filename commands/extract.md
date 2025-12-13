---
name: "knowledge-etl:extract"
description: Extract content from URL, images, PDF, directory, or git repo - with optional crawling and output transformation
category: Knowledge ETL
tags: [extract, web, crawl, images, pdf, directory, git, skill, plugin, rag]
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
---

# Knowledge ETL Extract Command

Unified extraction that converts **any content source to pure text Markdown**. Supports crawling with depth traversal and output transformation to various formats.

---

## STEP 0: Task Analysis & Plan Output (REQUIRED)

**Before executing, analyze the task complexity and output a plan:**

```
┌─ PLAN ─────────────────────────────────────────┐
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

**Simple (single page):**
```
┌─ PLAN ─────────────────────────────────────────┐
│ 1. Extract   → capture page snapshot           │
└────────────────────────────────────────────────┘
```

**Medium (single page + skill):**
```
┌─ PLAN ─────────────────────────────────────────┐
│ 1. Extract   → capture page                    │
│ 2. Transform → skill (plugin-dev)              │
│ 3. Validate  → skill-reviewer                  │
└────────────────────────────────────────────────┘
```

**Complex (crawl + skill):**
```
┌─ PLAN ─────────────────────────────────────────┐
│ 1. Crawl     → depth:2 max:20 topic-filter     │
│ 2. Summarize → INDEX.md + REPORT.md            │
│ 3. Transform → skill (plugin-dev)              │
│ 4. Validate  → skill-reviewer                  │
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

## Progress Output During Execution

Output progress in this format:

```
[1/4 Extract]   ████░░░░░░ 40% | snapshot.md (12K chars)
[2/4 Process]   ██████░░░░ 60% | ║ clean ✓ ║ compress... ║
[3/4 Transform] ████████░░ 80% | SKILL.md + 2 refs...
[4/4 Validate]  ██████████ 100% ✓ passed
```

**Rules:**
- One line per major step
- `...` = in progress, `✓` = done, `⚠` = warning
- `║` separates parallel tasks
- Only key info: filename, size, ratio

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

### For URLs (http/https)

```
╔════════════════════════════════════════════════════════════════════════════╗
║  ⚠️ CRITICAL: MCP TOOLS NOT AVAILABLE IN SUBAGENTS                        ║
║                                                                            ║
║  Playwright MCP tools only work in MAIN context, not in Task agents.      ║
║  Solution: Main context captures URL, then delegates LOCAL files.         ║
╚════════════════════════════════════════════════════════════════════════════╝
```

**Step-by-step execution (2-phase):**

```
PHASE 1: MAIN CONTEXT - Capture URL content
─────────────────────────────────────────────
Execute Playwright in main context (MCP tools available here):

1. mcp__playwright__browser_navigate(url: "{URL}")
2. mcp__playwright__browser_wait_for(time: 3)
3. mcp__playwright__browser_snapshot(filename: "snapshot.md")
4. mcp__playwright__browser_take_screenshot(filename: "screenshot.png")
5. mcp__playwright__browser_close()

Check for login:
- Read .playwright-mcp/snapshot.md
- If login detected (登录, login, password, SSO):
  - AskUserQuestion: "请在浏览器中完成登录"
  - Re-capture after user confirms

PHASE 2: SUBAGENT - Process local files (isolated context)
───────────────────────────────────────────────────────────
Delegate to extractor agent for content processing:

Task(
  subagent_type: "knowledge-etl:extractor",
  prompt: """
    Process captured content from: {URL}

    Local files available:
    - .playwright-mcp/snapshot.md
    - .playwright-mcp/screenshot.png

    Steps:
    1. Read snapshot.md first (text is lighter)
    2. If insufficient, compress and read screenshot
    3. Extract text content
    4. Describe images as text
    5. Write output to: {output_dir}/pages/001_{slug}.md

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

  # 2b. Capture URL using Playwright (MCP tools available here)
  mcp__playwright__browser_navigate(url: url)
  mcp__playwright__browser_wait_for(time: 3)
  mcp__playwright__browser_snapshot(filename: "page_{page_id}.md")
  mcp__playwright__browser_take_screenshot(filename: "page_{page_id}.png")

  # Check for login
  snapshot = Read(".playwright-mcp/page_{page_id}.md", limit: 50)
  if login_detected(snapshot):
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
