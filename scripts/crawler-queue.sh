#!/bin/bash
# Crawler Queue Management Script
# Helps manage the URL queue for the crawler coordinator

set -e

QUEUE_FILE="${1:-queue.json}"
ACTION="${2:-}"
shift 2 || true

# Ensure jq is available
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed"
    exit 1
fi

# Initialize empty queue
init_queue() {
    echo '{"items":[]}' > "$QUEUE_FILE"
    echo "Queue initialized: $QUEUE_FILE"
}

# Add URL to queue
# Usage: add <url> <depth> <priority> <parent_id> <anchor_text>
add_url() {
    local url="$1"
    local depth="${2:-0}"
    local priority="${3:-10}"
    local parent_id="${4:-}"
    local anchor_text="${5:-}"

    if [ ! -f "$QUEUE_FILE" ]; then
        init_queue
    fi

    # Check if URL already exists
    local exists=$(jq --arg url "$url" '.items | map(select(.url == $url)) | length' "$QUEUE_FILE")
    if [ "$exists" -gt 0 ]; then
        echo "URL already in queue: $url"
        return 0
    fi

    # Add to queue
    local tmp=$(mktemp)
    jq --arg url "$url" \
       --argjson depth "$depth" \
       --argjson priority "$priority" \
       --arg parent "$parent_id" \
       --arg anchor "$anchor_text" \
       '.items += [{"url": $url, "depth": $depth, "priority": $priority, "parent_id": $parent, "anchor_text": $anchor}]' \
       "$QUEUE_FILE" > "$tmp" && mv "$tmp" "$QUEUE_FILE"

    echo "Added: $url (depth=$depth, priority=$priority)"
}

# Pop highest priority URL
pop_url() {
    if [ ! -f "$QUEUE_FILE" ]; then
        echo ""
        return 1
    fi

    # Get highest priority item
    local item=$(jq -c '.items | sort_by(-.priority) | first // empty' "$QUEUE_FILE")

    if [ -z "$item" ] || [ "$item" = "null" ]; then
        echo ""
        return 1
    fi

    # Remove from queue
    local url=$(echo "$item" | jq -r '.url')
    local tmp=$(mktemp)
    jq --arg url "$url" '.items = [.items[] | select(.url != $url)]' "$QUEUE_FILE" > "$tmp" && mv "$tmp" "$QUEUE_FILE"

    echo "$item"
}

# Get queue size
queue_size() {
    if [ ! -f "$QUEUE_FILE" ]; then
        echo "0"
        return
    fi
    jq '.items | length' "$QUEUE_FILE"
}

# Check if queue is empty
is_empty() {
    local size=$(queue_size)
    if [ "$size" -eq 0 ]; then
        echo "true"
    else
        echo "false"
    fi
}

# List all items in queue
list_queue() {
    if [ ! -f "$QUEUE_FILE" ]; then
        echo "Queue not found"
        return 1
    fi
    jq -r '.items | sort_by(-.priority) | .[] | "\(.priority)\t\(.depth)\t\(.url)"' "$QUEUE_FILE"
}

# Clear queue
clear_queue() {
    echo '{"items":[]}' > "$QUEUE_FILE"
    echo "Queue cleared"
}

# --- Visited URLs Management ---

VISITED_FILE="${VISITED_FILE:-visited.json}"

# Initialize visited file
init_visited() {
    echo '{"urls":{},"count":0}' > "$VISITED_FILE"
    echo "Visited file initialized: $VISITED_FILE"
}

# Mark URL as visited
# Usage: mark_visited <url> <id> <depth> <relevance> <title>
mark_visited() {
    local url="$1"
    local id="$2"
    local depth="${3:-0}"
    local relevance="${4:-5}"
    local title="${5:-}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    if [ ! -f "$VISITED_FILE" ]; then
        init_visited
    fi

    local tmp=$(mktemp)
    jq --arg url "$url" \
       --arg id "$id" \
       --argjson depth "$depth" \
       --argjson relevance "$relevance" \
       --arg title "$title" \
       --arg ts "$timestamp" \
       '.urls[$url] = {"id": $id, "depth": $depth, "relevance": $relevance, "title": $title, "processed_at": $ts} | .count = (.urls | length)' \
       "$VISITED_FILE" > "$tmp" && mv "$tmp" "$VISITED_FILE"

    echo "Marked visited: $url"
}

# Check if URL is visited
is_visited() {
    local url="$1"

    if [ ! -f "$VISITED_FILE" ]; then
        echo "false"
        return
    fi

    local exists=$(jq --arg url "$url" '.urls | has($url)' "$VISITED_FILE")
    echo "$exists"
}

# Get visited count
visited_count() {
    if [ ! -f "$VISITED_FILE" ]; then
        echo "0"
        return
    fi
    jq '.count' "$VISITED_FILE"
}

# Generate next page ID
next_page_id() {
    local count=$(visited_count)
    printf "%03d" $((count + 1))
}

# --- URL Utilities ---

# Extract domain from URL
extract_domain() {
    local url="$1"
    echo "$url" | sed -E 's|^https?://([^/]+).*|\1|'
}

# Check if URL is same domain
is_same_domain() {
    local url="$1"
    local base_domain="$2"
    local url_domain=$(extract_domain "$url")

    if [ "$url_domain" = "$base_domain" ]; then
        echo "true"
    else
        echo "false"
    fi
}

# Check if URL should be skipped (file extensions, patterns)
should_skip_url() {
    local url="$1"

    # Skip file extensions
    local skip_ext="\.pdf$|\.zip$|\.exe$|\.mp4$|\.mp3$|\.wav$|\.avi$|\.mov$|\.png$|\.jpg$|\.jpeg$|\.gif$|\.svg$|\.ico$|\.css$|\.js$|\.woff2?$|\.ttf$|\.eot$"
    if echo "$url" | grep -qE "$skip_ext"; then
        echo "true"
        return
    fi

    # Skip patterns
    local skip_patterns="login|logout|signup|signin|register|cart|checkout|payment|download|/static/|/assets/|/images/|/fonts/"
    if echo "$url" | grep -qiE "$skip_patterns"; then
        echo "true"
        return
    fi

    echo "false"
}

# Normalize URL (remove trailing slash, anchors)
normalize_url() {
    local url="$1"
    # Remove anchor
    url=$(echo "$url" | sed 's/#.*//')
    # Remove trailing slash
    url=$(echo "$url" | sed 's|/$||')
    echo "$url"
}

# --- Main ---

case "$ACTION" in
    init)
        init_queue
        ;;
    add)
        add_url "$@"
        ;;
    pop)
        pop_url
        ;;
    size)
        queue_size
        ;;
    empty)
        is_empty
        ;;
    list)
        list_queue
        ;;
    clear)
        clear_queue
        ;;
    init-visited)
        init_visited
        ;;
    mark-visited)
        mark_visited "$@"
        ;;
    is-visited)
        is_visited "$1"
        ;;
    visited-count)
        visited_count
        ;;
    next-id)
        next_page_id
        ;;
    domain)
        extract_domain "$1"
        ;;
    same-domain)
        is_same_domain "$1" "$2"
        ;;
    skip-url)
        should_skip_url "$1"
        ;;
    normalize)
        normalize_url "$1"
        ;;
    *)
        echo "Usage: $0 <queue_file> <action> [args...]"
        echo ""
        echo "Queue actions:"
        echo "  init                    Initialize empty queue"
        echo "  add <url> [depth] [priority] [parent] [anchor]"
        echo "  pop                     Pop highest priority URL"
        echo "  size                    Get queue size"
        echo "  empty                   Check if queue is empty"
        echo "  list                    List all items"
        echo "  clear                   Clear queue"
        echo ""
        echo "Visited actions:"
        echo "  init-visited            Initialize visited file"
        echo "  mark-visited <url> <id> [depth] [relevance] [title]"
        echo "  is-visited <url>        Check if URL is visited"
        echo "  visited-count           Get visited count"
        echo "  next-id                 Generate next page ID"
        echo ""
        echo "URL utilities:"
        echo "  domain <url>            Extract domain from URL"
        echo "  same-domain <url> <base>"
        echo "  skip-url <url>          Check if URL should be skipped"
        echo "  normalize <url>         Normalize URL"
        exit 1
        ;;
esac
