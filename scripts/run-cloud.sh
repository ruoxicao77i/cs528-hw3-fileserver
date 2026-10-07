#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_PATH="$SCRIPT_DIR/../file-server"
REGION=us-central1
SA_EMAIL="hw3-file-server@tonal-plateau-508118-g0.iam.gserviceaccount.com"

gcloud run deploy file-server \
    --source "$SRC_PATH" \
    --function file_server \
    --base-image python313 \
    --region "$REGION" \
    --service-account "$SA_EMAIL" \
    --allow-unauthenticated