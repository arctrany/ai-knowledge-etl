---
name: Knowledge ETL Extract
description: |-
  Unified extraction with atomic capabilities - converts any source to pure text Markdown.
  Supports crawling, relevance scoring, and output transformation via pluggable pipeline.

  Use this skill when:
  - Extracting content from web pages (with anti-scrape handling)
  - Crawling websites with depth (--with-depth)
  - Analyzing local images (especially large ones)
  - Processing PDFs, directories, or git repositories
  - Handling "prompt too large" errors
  - Transforming content to skill, plugin, prompt, RAG formats

  Key capability: All operations run in isolated agent context to PREVENT overflow.
  REUSES: plugin-dev for skill/plugin generation, internal atomic capabilities.

  Triggers: "extract from url", "crawl website", "analyze image", "prompt too large",
  "extract content", "create skill from", "generate rag", "extract with depth"
version: 3.1.0
allowed-tools: Read, Bash, Glob, Task, AskUserQuestion
---

# Knowledge ETL - Extract Skill

Unified extraction with **atomic capabilities** and **pluggable pipeline**.

## Architecture

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                    ATOMIC CAPABILITIES ARCHITECTURE                       ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  Layer 0: External Capabilities (Reused)                                 ║
║  ────────────────────────────────────────                                 ║
║  plugin-dev:skill-development → Generate skills                          ║
║  plugin-dev:plugin-structure  → Generate plugins                         ║
║  plugin-dev:skill-reviewer    → Validate skill quality                   ║
║                                                                           ║
║  Layer 1: Internal Atomic Capabilities                                   ║
║  ─────────────────────────────────────                                    ║
║  content-safeguard → Size limits, compression, truncation                ║
║  relevance-scorer  → Regex matching, topic filtering                     ║
║                                                                           ║
║  Layer 2: Extraction Agents                                              ║
║  ───────────────────────────                                              ║
║  extractor         → URL/image/PDF/directory processing                  ║
║  crawler-coord     → Multi-page crawl orchestration                      ║
║  crawler-summarizer→ INDEX.md and REPORT.md generation                   ║
║                                                                           ║
║  Layer 3: Output Pipelines                                               ║
║  ─────────────────────────                                                ║
║  output-transformer → Routes to: skill, plugin, prompt, rag, docs, json  ║
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

## Atomic Capabilities

### content-safeguard

Prevents "Prompt Too Long" errors through size-aware processing.

**Limits:**
| Resource | Limit |
|----------|-------|
| Image | 300 KB / 800 px / 5 per session |
| Text | 20,000 chars per file |
| Output | 50,000 chars total |
| PDF | 15 pages max |
| Batch | 5 files at a time |

**Patterns:**
- Size check before read
- Sequential one-by-one processing
- Fallback chains for graceful degradation

### relevance-scorer

Scores content relevance using regex patterns.

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

## Delegation Strategy

ALL sources delegated to agents in **isolated context**:

```
Task(
  subagent_type: "knowledge-etl:extractor",
  prompt: "Extract content from: [SOURCE]..."
)
```

**Why agents?**
- Playwright returns content to calling context → overflow in main
- Agents run isolated → content stays contained
- Files written to disk, not returned to main context

## Output Pipelines

| Pipe | Output | Atomic Capabilities Used |
|------|--------|--------------------------|
| `--pipe=skill` | SKILL.md + references/ | plugin-dev:skill-development → plugin-dev:skill-reviewer |
| `--pipe=plugin` | Full plugin structure | plugin-dev:plugin-structure → plugin-dev:skill-development → plugin-dev:plugin-validator |
| `--pipe=prompt` | System prompt for LLMs | Direct transformation |
| `--pipe=rag` | Chunked JSON for vector DB | content-safeguard patterns |
| `--pipe=docs` | Documentation structure | Direct transformation |
| `--pipe=json` | Structured JSON | Direct transformation |

**Key**: skill 和 plugin 输出都复用 plugin-dev 的原子能力，确保符合 Claude Code 插件规范。

## Examples

```bash
# Single page extraction
/knowledge-etl:extract https://docs.example.com/guide

# Crawl with depth and topic filter (regex)
/knowledge-etl:extract https://api.example.com --with-depth=2 --topic="API|REST"

# Crawl and generate skill (reuses plugin-dev)
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

## Error Handling

| Error | Resolution |
|-------|------------|
| Login required | AskUserQuestion → wait for user |
| Anti-scrape | Screenshot fallback |
| Prompt too large | Apply content-safeguard patterns |
| Image unreadable | Mark "[cannot read image]" |

## Additional Skills

This plugin provides atomic capabilities for reuse:

- **`content-safeguard`** - Size-aware processing patterns
- **`relevance-scorer`** - Topic matching and link scoring

## Dependencies

**External (from claude-code-plugins):**
- plugin-dev:skill-development
- plugin-dev:plugin-structure
- plugin-dev:skill-reviewer
- plugin-dev:plugin-validator

**MCP:**
- Playwright with persistent profile for URL extraction
