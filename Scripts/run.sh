#!/bin/zsh
# Debug build + launch. Usage: Scripts/run.sh
set -euo pipefail
cd "$(dirname "$0")/.."
Scripts/build-app.sh debug
open "build/Ground Control.app"
