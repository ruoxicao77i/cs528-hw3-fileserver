#!/bin/bash
set -eu

# Usage:
#   bash scripts/test_client.sh [local|cloud] [#requests] [-v]
# Examples:
#   bash scripts/test_client.sh              
#   bash scripts/test_client.sh local 5 -v   
#   bash scripts/test_client.sh cloud 100    

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT="$SCRIPT_DIR/../client/http-client"

TARGET="${1:-local}"
NUM_REQUESTS="${2:-10}"
EXTRA="${3:-}"

BUCKET_NAME="/cs528-ruoxi-pagerank"
WEBDIR="pages"
MAX_INDEX=12000

case "$TARGET" in
    local)
        ARGS=(-d localhost -p 8080)
        ;;
    cloud)
        URL="$(gcloud run services describe file-server \
            --region us-central1 --format='value(status.url)')"
        ARGS=(-d "${URL#https://}" -p 443 -s)
        ;;
    *)
        echo "Usage $0 [local|cloud] [requests] [-v]" >&2
        exit 1
        ;;
esac

echo "send $NUM_REQUESTS requests to $TARGET"
"$CLIENT" "${ARGS[@]}" \
    -b "$BUCKET_NAME" -w "$WEBDIR" \
    -i "$MAX_INDEX" -n "$NUM_REQUESTS" $EXTRA