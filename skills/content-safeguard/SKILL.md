---
name: Content Safeguard
description: |-
  This skill should be used when processing content that may cause "prompt too large" or context overflow errors.

  Use this skill when:
  - Processing large files, images, or web content
  - Handling batch operations with multiple files
  - Need to truncate, summarize, or compress content safely
  - Implementing size checks before reading content

  Triggers: "prompt too large", "context overflow", "content too long", "truncate content",
  "batch processing", "size check", "compress image", "safe read", "prevent overflow"
version: 1.0.0
allowed-tools: Read, Bash, Glob
---

# Content Safeguard - Atomic Capability

Prevent "Prompt Too Long" errors through size-aware content processing.

## Core Principle

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                         IRON RULE                                         ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  NEVER read content without checking size first.                          ║
║  NEVER process multiple large items in parallel.                          ║
║  ALWAYS use fallback chains when content exceeds limits.                  ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

## Safety Limits

| Resource | Hard Limit | Action |
|----------|-----------|--------|
| Image size | 300 KB | Compress before read |
| Image width | 800 px | Resize before read |
| Images per session | 5 | Skip decorative ones |
| Text per file | 20,000 chars | Truncate with notice |
| Snapshot content | 30,000 chars | Truncate with notice |
| Total output | 50,000 chars | Summarize sections |
| PDF pages | 15 | Summarize rest |
| Batch size | 5 files | Process in batches |

## Size Check Pattern

Before reading ANY file:

```bash
# Check file size
SIZE=$(stat -f%z "{file_path}" 2>/dev/null || stat -c%s "{file_path}" 2>/dev/null || echo "0")
echo "Size: $SIZE bytes"

# Decision logic
if [ "$SIZE" -gt 300000 ]; then
  echo "MUST compress or truncate"
fi
```

## Processing Strategies

### Strategy 1: Sequential One-by-One

Process items individually, releasing context after each:

```
for item in items:
  content = read(item)        # Read ONE item
  result = process(content)   # Process immediately
  store(result)               # Store result to file
  # Context released automatically
```

### Strategy 2: Batch with Limits

Split large sets into manageable batches:

```
batches = split(items, batch_size=5)
for batch in batches:
  for item in batch:
    process_one(item)
  # Batch complete, context lighter
```

### Strategy 3: Fallback Chain

When primary method fails, try alternatives:

```
Content Processing Chain:
  Full content → Truncate → Key sections → Summary → Headings only → FAIL

Image Processing Chain:
  Original → Compress(800px) → Compress(640px) → Compress(400px) → FAIL
```

## Image Compression

Use the compression script:

```bash
# Compress to safe size
"${CLAUDE_PLUGIN_ROOT}/scripts/compress-image.sh" "{input}" "{output}" 800

# Verify size after compression
CSIZE=$(stat -f%z "{output}" 2>/dev/null || stat -c%s "{output}" 2>/dev/null)
if [ "$CSIZE" -gt 300000 ]; then
  # Try more aggressive compression
  "${CLAUDE_PLUGIN_ROOT}/scripts/compress-image.sh" "{input}" "{output}" 640
fi
```

## Truncation with Notice

When truncating content, always add notice:

```markdown
---
> **Notice**: Content truncated. Original: {original_chars} chars, showing first {limit} chars.
---
```

## Batch Planning

Before processing directories:

```bash
# Count and estimate
FILE_COUNT=$(find "{dir}" -type f | wc -l)
TOTAL_SIZE=$(find "{dir}" -type f -exec stat -f%z {} + 2>/dev/null | awk '{s+=$1}END{print s}')

echo "Files: $FILE_COUNT, Total size: $TOTAL_SIZE bytes"

# Plan batches
if [ "$FILE_COUNT" -gt 10 ]; then
  echo "Will process in batches of 5"
fi
```

## Integration Pattern

Other agents should call this skill's patterns:

```
1. Before reading: Check size
2. If over limit: Apply compression/truncation
3. Process one item at a time
4. Store results to file, not memory
5. Monitor cumulative output size
```

## Quick Reference

```
╔═══════════════════════════════════════════════════════════════════════════╗
║  NEVER: Read multiple large files at once                                ║
║  NEVER: Read image > 300KB without compressing                           ║
║  NEVER: Return > 50,000 chars total                                      ║
║                                                                           ║
║  ALWAYS: Check size before reading                                        ║
║  ALWAYS: Process one item, store, release                                ║
║  ALWAYS: Use fallback chains                                             ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

## Additional Resources

For detailed limits configuration, see:
- **`references/limits.yaml`** - Configurable safety limits
