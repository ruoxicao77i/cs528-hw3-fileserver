#!/bin/bash
set -u

# Usage:
#   bash scripts/test_curl.sh           local
#   bash scripts/test_curl.sh cloud     cloud
#   bash scripts/test_curl.sh <URL>     

case "${1:-local}" in
    local) BASE_URL="http://localhost:8080" ;;
    cloud) BASE_URL="$(gcloud run services describe file-server \
               --region us-central1 --format='value(status.url)')" ;;
    *)     BASE_URL="$1" ;;
esac

BUCKET_NAME="cs528-ruoxi-pagerank"
GOOD_FILE="$BUCKET_NAME/pages/1.html"
BAD_FILE="$BUCKET_NAME/pages/non-existent.html"

# run curl
run() {
    local title="$1"; shift
    echo "=== $title ==="
    curl -s -i "$@" | head -n 12
    echo
    echo
}

echo "Testing $BASE_URL"
echo

run "GET existing file (expect 200)"      "$BASE_URL/$GOOD_FILE"
run "GET non-existent file (expect 404)"  "$BASE_URL/$BAD_FILE"

run "POST existing file (expect 200)" -X POST "$BASE_URL" \
    -H "Content-Type: application/json" \
    -d "{\"file\": \"$GOOD_FILE\"}"

run "POST non-existent file (expect 404)" -X POST "$BASE_URL" \
    -H "Content-Type: application/json" \
    -d "{\"file\": \"$BAD_FILE\"}"

for method in PUT DELETE PATCH OPTIONS; do
    run "$method (expect 501)" -X "$method" "$BASE_URL/$GOOD_FILE"
done

run "HEAD (expect 501)" -I "$BASE_URL/$GOOD_FILE"