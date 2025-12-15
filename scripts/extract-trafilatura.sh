#!/bin/bash
# extract-trafilatura.sh - Extract content using local trafilatura
# Usage: ./extract-trafilatura.sh <url> <output_dir>
#
# Requires: pip3 install trafilatura

set -e

URL="$1"
OUTPUT_DIR="${2:-.knowledge-etl}"

if [ -z "$URL" ]; then
  echo "[error] Usage: $0 <url> [output_dir]"
  exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CHECK DEPENDENCIES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if ! command -v trafilatura &> /dev/null; then
  echo "[error] trafilatura not found. Install with:"
  echo "        pip3 install trafilatura"
  exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# EXTRACT VIA TRAFILATURA (LOCAL - NO EXTERNAL API)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate output filename from URL
SAFE_NAME=$(echo "$URL" | sed -E 's|https?://||; s|[^a-zA-Z0-9]|_|g' | cut -c1-50)
OUTPUT_FILE="$OUTPUT_DIR/${SAFE_NAME}.md"

echo "[trafilatura] Extracting: $URL"
echo "[trafilatura] Output: $OUTPUT_FILE"

# Extract using trafilatura
# --favour-precision: prefer precision over recall
# --include-links: keep hyperlinks
# --include-tables: keep tables

CONTENT=$(trafilatura -u "$URL" --favour-precision --include-links --include-tables 2>/dev/null)

if [ -z "$CONTENT" ]; then
  echo "[error] trafilatura returned empty content"
  echo "[error] The page might require JavaScript or login"
  exit 2
fi

# Write output with frontmatter
{
  echo "---"
  echo "source: $URL"
  echo "engine: trafilatura"
  echo "extracted_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "---"
  echo ""
  echo "$CONTENT"
} > "$OUTPUT_FILE"

# Stats
LINES=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null)

echo "[trafilatura] ✓ Extracted: $LINES lines, $SIZE bytes"
echo "[trafilatura] Output: $OUTPUT_FILE"
