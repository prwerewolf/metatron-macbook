#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
CURRENT_HOOKS="$(git config --get core.hooksPath || true)"
if [[ -n "$CURRENT_HOOKS" && "$CURRENT_HOOKS" != ".githooks" ]]; then
    echo "An existing hooks path is configured. Preserve it and add these privacy checks to your hooks manually."
    exit 1
fi
python3 -B scripts/privacy_check.py --init-local
git config --local core.hooksPath .githooks
echo "Installed commit and push privacy checks for this checkout."
