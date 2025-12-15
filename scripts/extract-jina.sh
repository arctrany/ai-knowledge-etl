#!/bin/bash
# extract-jina.sh - Extract content using r.jina.ai API
# Usage: ./extract-jina.sh <url> <output_dir>

set -e

URL="$1"
OUTPUT_DIR="${2:-.knowledge-etl}"

if [ -z "$URL" ]; then
  echo "[error] Usage: $0 <url> [output_dir]"
  exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SECURITY CHECK - Refuse internal URLs
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

DOMAIN=$(echo "$URL" | sed -E 's|https?://([^/]+).*|\1|')

# Internal domains - NEVER send to external API
BLOCKED_PATTERNS=(
  "alibaba-inc.com"
  "dingtalk.com"
  "yuque.com"
  "aliyun.com"
  "taobao.com"
  "localhost"
  "127.0.0.1"
)

for pattern in "${BLOCKED_PATTERNS[@]}"; do
  if [[ "$DOMAIN" == *"$pattern"* ]]; then
    echo "[error] Security: $DOMAIN is an internal domain. Cannot use jina."
    echo "[error] Use --engine=playwright instead."
    exit 2
  fi
done

# Check for private IP ranges
if [[ "$DOMAIN" =~ ^10\. ]] || [[ "$DOMAIN" =~ ^192\.168\. ]] || [[ "$DOMAIN" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]]; then
  echo "[error] Security: $DOMAIN is a private network. Cannot use jina."
  exit 2
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# EXTRACT VIA JINA
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate output filename from URL
SAFE_NAME=$(echo "$URL" | sed -E 's|https?://||; s|[^a-zA-Z0-9]|_|g' | cut -c1-50)
OUTPUT_FILE="$OUTPUT_DIR/${SAFE_NAME}.md"

echo "[jina] Extracting: $URL"
echo "[jina] Output: $OUTPUT_FILE"

# Call Jina Reader API
JINA_URL="https://r.jina.ai/$URL"

HTTP_CODE=$(curl -s -w "%{http_code}" -o "$OUTPUT_FILE.tmp" \
  --max-time 30 \
  -H "Accept: text/markdown" \
  "$JINA_URL")

if [ "$HTTP_CODE" -ne 200 ]; then
  echo "[error] Jina API returned HTTP $HTTP_CODE"
  rm -f "$OUTPUT_FILE.tmp"
  exit 3
fi

# Add frontmatter
{
  echo "---"
  echo "source: $URL"
  echo "engine: jina"
  echo "extracted_at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "---"
  echo ""
  cat "$OUTPUT_FILE.tmp"
} > "$OUTPUT_FILE"

rm -f "$OUTPUT_FILE.tmp"

# Stats
LINES=$(wc -l < "$OUTPUT_FILE" | tr -d ' ')
SIZE=$(stat -f%z "$OUTPUT_FILE" 2>/dev/null || stat -c%s "$OUTPUT_FILE" 2>/dev/null)

echo "[jina] ✓ Extracted: $LINES lines, $SIZE bytes"
echo "[jina] Output: $OUTPUT_FILE"
