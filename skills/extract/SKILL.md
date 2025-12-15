---
name: Knowledge ETL Extract
description: |-
  Unified extraction - converts any source to pure text Markdown.
  Supports crawling, relevance scoring, and output transformation.

  Use this skill when:
  - Extracting content from web pages (with anti-scrape handling)
  - Crawling websites with depth (--with-depth)
  - Analyzing local images (especially large ones)
  - Processing PDFs, directories, or git repositories
  - Handling "prompt too large" errors
  - Transforming content to skill, plugin, prompt, RAG formats

  Key capability: All operations run in isolated agent context to PREVENT overflow.
  Self-contained with built-in templates. No external plugin dependencies.

  Triggers: "extract from url", "crawl website", "analyze image", "prompt too large",
  "extract content", "create skill from", "generate rag", "extract with depth"
version: 0.1.3
allowed-tools: Read, Write, Bash, Glob, Grep, AskUserQuestion
---

# Knowledge ETL - Extract Skill

Unified extraction with **built-in templates** and **pluggable pipeline**.

## ⛔ IRON RULE: "Prompt is too long" = PLUGIN FAILURE

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🚨🚨🚨 IRON RULE: PREVENT "PROMPT IS TOO LONG" AT ALL COSTS 🚨🚨🚨      ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  "Prompt is too long" error = COMPLETE PLUGIN FAILURE                    ║
║  This is UNACCEPTABLE and must be prevented with 100% certainty.         ║
║                                                                           ║
║  ALL content processing MUST run in isolated subagent contexts.          ║
║  Main context MUST NOT read any large files (snapshots, images, pages).  ║
║                                                                           ║
║  Key principles:                                                          ║
║  - Main context: Playwright capture ONLY, delegate to subagents          ║
║  - Subagents: Check size FIRST, chunk large files, compress images       ║
║  - NEVER use Read() without checking file size first                     ║
║  - ALWAYS use Read(limit: 500) for files >500 lines                      ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

## Architecture

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    SELF-CONTAINED ARCHITECTURE                            ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  Layer 1: Internal Capabilities                                          ║
║  ──────────────────────────────                                           ║
║  content-safeguard → Size limits, compression, truncation                ║
║  relevance-scorer  → Regex matching, topic filtering                     ║
║                                                                           ║
║  Layer 2: Extraction Agents                                              ║
║  ───────────────────────────                                              ║
║  extractor         → LOCAL file processing (snapshot/image/PDF)          ║
║  crawler-summarizer→ INDEX.md and REPORT.md generation                   ║
║                                                                           ║
║  Layer 3: Output Pipelines (Built-in Templates)                          ║
║  ───────────────────────────────────────────────                          ║
║  output-transformer → skill, plugin, prompt, rag, docs, json             ║
║                                                                           ║
║  IRON RULE: Every operation in isolated context - NO overflow            ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

## Command Format

```bash
/knowledge-etl:extract <source> [--with-depth=N] [--topic=REGEX] [--max-pages=N] [--pipe=FORMAT]
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `--with-depth=N` | Enable crawling with depth N (1-3) | disabled |
| `--topic=REGEX` | Topic filter regex for relevance | none |
| `--max-pages=N` | Maximum pages to crawl | 20 |
| `--pipe=FORMAT` | Output format: skill, plugin, prompt, rag, docs, json | none |

## Safety Limits

Reference: `config/limits.yaml`

| Resource | Limit |
|----------|-------|
| Image | 300 KB / 800 px / 5 per session |
| Text | 20,000 chars per file |
| Output | 50,000 chars total |
| PDF | 15 pages max |
| Batch | 5 files at a time |

## Relevance Scoring

**Topic as Regex:**
```
--topic="API|接口|endpoint|REST|认证"
```

**Scoring:**
- URL match: +3
- Anchor text match: +5
- Context match: +2
- Score 8-10: Deep exploration (DFS)
- Score 5-7: Breadth scan (BFS)
- Score <5: Skip exploration

## MCP Context Limitation

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  MCP tools (Playwright) only work in MAIN context (commands).            ║
║  Subagents cannot access MCP - they process LOCAL files only.            ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

**Execution Model:**
1. Command (main context) captures URL via Playwright → saves locally
2. Extractor agent (isolated) processes local snapshot files
3. Results written to disk, not returned to main context

## Output Pipelines

| Pipe | Output | Template |
|------|--------|----------|
| `--pipe=skill` | SKILL.md + references/ | Built-in skill template |
| `--pipe=plugin` | Full plugin structure | Built-in plugin template |
| `--pipe=prompt` | System prompt for LLMs | Built-in prompt template |
| `--pipe=rag` | Chunked JSON for vector DB | 500-1000 char chunks |
| `--pipe=docs` | Documentation structure | README + reference/ |
| `--pipe=json` | Structured JSON | knowledge.json |

## Examples

```bash
# Single page extraction
/knowledge-etl:extract https://docs.example.com/guide

# Crawl with depth and topic filter (regex)
/knowledge-etl:extract https://api.example.com --with-depth=2 --topic="API|REST"

# Crawl and generate skill
/knowledge-etl:extract https://docs.example.com --with-depth=2 --topic="API" --pipe=skill

# Directory to RAG chunks
/knowledge-etl:extract ./docs --pipe=rag

# Git repo to system prompt
/knowledge-etl:extract https://github.com/user/lib --pipe=prompt
```

## Output Structure

```
.knowledge-etl/
├── config.json          # Configuration
├── pages/               # Extracted content
├── links/               # Discovered links (crawl)
├── INDEX.md             # Page index (crawl)
├── REPORT.md            # Topic report (crawl)
└── output/{pipe}/       # Transformed output
```

## ⛔ Image Extraction Rules (CRITICAL)

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  🚨 NEVER USE browser_take_screenshot FOR IMAGE DOWNLOAD 🚨              ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  Screenshot embeds image data into conversation context!                 ║
║  Multiple screenshots = Context explosion = "Prompt is too long"         ║
║                                                                           ║
║  ❌ WRONG: Click preview → screenshot → loop = CONTEXT OVERFLOW          ║
║  ✅ RIGHT: browser_evaluate → extract URLs → curl download               ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

**Correct Image Download Flow:**
1. `browser_evaluate` - Extract all `img[src]` URLs from page → save to `images.json`
2. `scripts/download-images.sh` - Batch download via curl (no context impact)
3. Subagent processes local image files (isolated context)

**Forbidden Patterns:**
- ❌ `browser_take_screenshot` for downloading images
- ❌ Opening preview modals for extraction
- ❌ Looping screenshots in main context
- ❌ Any operation that embeds images into conversation

## Error Handling

| Error | Resolution |
|-------|------------|
| Login required | AskUserQuestion → wait for user |
| Anti-scrape | Screenshot fallback (single page only, NOT for images) |
| Prompt too large | Apply content-safeguard patterns |
| Image unreadable | Mark "[cannot read image]" |

## Requirements

**MCP:**
- Playwright with persistent profile for URL extraction
