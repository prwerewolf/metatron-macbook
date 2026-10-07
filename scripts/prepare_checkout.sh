#!/usr/bin/env bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECKOUT_ROOT="$(git -C "$SOURCE_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -e "$SOURCE_DIR/.git" && -z "$CHECKOUT_ROOT" ]]; then
    echo "Git metadata exists but this checkout could not be verified. Repair it before setup so publication guards can be enabled."
    exit 1
fi
if [[ -n "$CHECKOUT_ROOT" ]]; then
    CHECKOUT_ROOT="$(cd "$CHECKOUT_ROOT" && pwd -P)"
fi
if [[ "$CHECKOUT_ROOT" != "$SOURCE_DIR" ]]; then
    echo "Source archive: no repository hooks to install. Maintainers should use a Git clone for guarded updates."
    exit 0
fi
# Only prepare this application's own checkout, never an enclosing repository.
"$SOURCE_DIR/scripts/install_hooks.sh"
