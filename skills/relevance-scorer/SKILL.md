---
name: Relevance Scorer
description: |-
  This skill should be used when scoring content relevance against topics using regex patterns.

  Use this skill when:
  - Filtering links by topic relevance during crawling
  - Scoring page content against search topics
  - Prioritizing items in a queue by relevance
  - Implementing smart traversal (DFS for high, BFS for low relevance)

  Triggers: "relevance score", "topic match", "filter by topic", "regex pattern",
  "link relevance", "content scoring", "priority queue", "smart traversal"
version: 1.0.0
allowed-tools: Bash, Grep
---

# Relevance Scorer - Atomic Capability

Score content relevance against topics using regex pattern matching.

## Topic Pattern Format

Topics are regex patterns for flexible matching:

```bash
# Simple keywords (OR logic)
topic="API|REST|endpoint"

# Multi-language support
topic="API|接口|端点|认证|authentication"

# Specific patterns
topic="v[0-9]+\\.api|/docs/|reference"
```

## Scoring Algorithm

### Link Relevance Score (0-10)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      LINK RELEVANCE SCORING                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Component Scores:                                                          │
│                                                                             │
│  1. URL Match (weight: 2)                                                   │
│     URL contains topic pattern → +3                                         │
│     URL path suggests docs/api → +2                                        │
│                                                                             │
│  2. Anchor Text Match (weight: 3) - Most Important                         │
│     Anchor text contains topic → +5                                        │
│     Anchor text contains related → +3                                      │
│                                                                             │
│  3. Context Match (weight: 2)                                               │
│     Surrounding text contains topic → +2                                   │
│                                                                             │
│  4. Structural Bonus (weight: 1)                                           │
│     In navigation → +2                                                     │
│     In main content → +3                                                   │
│     In footer → +0                                                         │
│                                                                             │
│  Final Score = min(sum, 10)                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Page Content Relevance Score (0-10)

```
Component Scores:

1. Title Match
   Title contains topic → +3

2. Heading Match (H1, H2)
   Each heading with topic → +2 (max +4)

3. Content Density
   10+ topic mentions → +3
   5-9 mentions → +2
   2-4 mentions → +1

Final Score = min(sum, 10)
```

## Scoring Functions

### Score a Link

```bash
score_link() {
  local url="$1"
  local anchor="$2"
  local context="$3"
  local topic="$4"
  local score=0

  # URL match
  if echo "$url" | grep -qiE "$topic"; then
    score=$((score + 3))
  fi

  # Anchor text match (most important)
  if echo "$anchor" | grep -qiE "$topic"; then
    score=$((score + 5))
  fi

  # Context match
  if echo "$context" | grep -qiE "$topic"; then
    score=$((score + 2))
  fi

  # Cap at 10
  [ "$score" -gt 10 ] && score=10
  echo "$score"
}
```

### Score Page Content

```bash
score_page() {
  local title="$1"
  local headings="$2"
  local content="$3"
  local topic="$4"
  local score=0

  # Title match
  if echo "$title" | grep -qiE "$topic"; then
    score=$((score + 3))
  fi

  # Heading matches
  heading_matches=$(echo "$headings" | grep -ciE "$topic" || echo "0")
  [ "$heading_matches" -gt 2 ] && heading_matches=2
  score=$((score + heading_matches * 2))

  # Content density
  mentions=$(echo "$content" | grep -oiE "$topic" | wc -l)
  if [ "$mentions" -ge 10 ]; then
    score=$((score + 3))
  elif [ "$mentions" -ge 5 ]; then
    score=$((score + 2))
  elif [ "$mentions" -ge 2 ]; then
    score=$((score + 1))
  fi

  # Cap at 10
  [ "$score" -gt 10 ] && score=10
  echo "$score"
}
```

## Relevance Thresholds

| Score Range | Classification | Traversal Action |
|-------------|----------------|------------------|
| 8-10 | High | DFS - explore deeply |
| 5-7 | Medium | BFS - scan breadth |
| 3-4 | Low | Add to queue tail |
| 0-2 | Irrelevant | Skip exploration |

## Smart Traversal Strategy

```
╔═══════════════════════════════════════════════════════════════════════════╗
║                      SMART HYBRID TRAVERSAL                               ║
╠═══════════════════════════════════════════════════════════════════════════╣
║                                                                           ║
║  High Relevance (8-10):                                                   ║
║    → Deep-first exploration                                               ║
║    → All child links get priority boost                                   ║
║    → Exhaust this branch before moving on                                 ║
║                                                                           ║
║  Medium Relevance (5-7):                                                  ║
║    → Breadth scan                                                         ║
║    → Links added to queue normally                                        ║
║    → No priority boost                                                    ║
║                                                                           ║
║  Low Relevance (<5):                                                      ║
║    → Prune branch                                                         ║
║    → Keep extracted content                                               ║
║    → Don't follow links from this page                                    ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
```

## Priority Queue Integration

```bash
# Calculate queue priority
calculate_priority() {
  local link_score="$1"
  local parent_score="$2"

  # Parent bonus: high-relevance parents boost children
  local parent_bonus=0
  if [ "$parent_score" -ge 8 ]; then
    parent_bonus=3
  elif [ "$parent_score" -ge 5 ]; then
    parent_bonus=1
  fi

  echo $((link_score + parent_bonus))
}

# Add to queue with priority
# Higher priority = processed first
```

## Link Filtering

Skip links that match these patterns:

```bash
SKIP_EXTENSIONS="\.pdf$|\.zip$|\.exe$|\.mp4$|\.png$|\.jpg$|\.css$|\.js$"
SKIP_PATTERNS="login|logout|signup|cart|checkout|download|/static/|/assets/"

should_skip() {
  local url="$1"

  if echo "$url" | grep -qE "$SKIP_EXTENSIONS"; then
    return 0  # Skip
  fi

  if echo "$url" | grep -qiE "$SKIP_PATTERNS"; then
    return 0  # Skip
  fi

  return 1  # Don't skip
}
```

## Output Format

For crawler integration, output scored links as JSON:

```json
{
  "url": "https://example.com/docs/api",
  "anchor_text": "API Reference",
  "context": "Complete API documentation for developers",
  "relevance_score": 9,
  "position": "navigation"
}
```

## Integration Pattern

Other components use this skill by:

1. Passing topic regex pattern
2. Calling scoring function for each item
3. Using score to determine action (explore/skip/queue position)
4. Applying parent bonus for hierarchical traversal

## Additional Resources

For advanced patterns, see:
- **`references/patterns.md`** - Common regex patterns for different domains
