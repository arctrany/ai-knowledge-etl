#!/bin/bash
# Cross-platform image compression wrapper
#
# Usage:
#   Single file: compress-image.sh <input> <output> [maxWidth]
#   Batch mode:  compress-image.sh --batch <inputDir> <outputDir> [maxWidth]
#
# Examples:
#   compress-image.sh screenshot.png compressed.jpg 1280
#   compress-image.sh --batch ./images ./compressed 1280

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if node is available
if ! command -v node &> /dev/null; then
    echo "Error: Node.js is required but not installed."
    echo "Please install Node.js 18+ from https://nodejs.org/"
    exit 1
fi

# Run the Node.js compression script
node "$SCRIPT_DIR/compress-image.mjs" "$@"
