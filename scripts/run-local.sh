#!/bin/bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_PATH="$SCRIPT_DIR/../file-server"
export GOOGLE_APPLICATION_CREDENTIALS="$SCRIPT_DIR/../keys/hw3-sa.json"

cd "$SRC_PATH"
functions-framework --target file_server --debug