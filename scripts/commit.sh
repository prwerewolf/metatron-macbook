#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
python3 -B scripts/privacy_check.py --staged
# Scope the neutral identity to this command; preserve shared Git preferences.
GIT_AUTHOR_NAME="Press To Write Maintainers" \
GIT_AUTHOR_EMAIL="maintainers@presstowrite.invalid" \
GIT_COMMITTER_NAME="Press To Write Maintainers" \
GIT_COMMITTER_EMAIL="maintainers@presstowrite.invalid" \
git commit "$@"
