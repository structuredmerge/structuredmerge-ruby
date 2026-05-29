#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ruby_family_common.sh
source "$SCRIPT_DIR/ruby_family_common.sh"

parse_family_selection "$@"

docs_gem() {
  local gem="$1"
  local dir="$2"
  [[ -d "$dir" ]] || return 0

  echo "=== $gem ==="
  mise trust -C "$dir" --quiet 2>/dev/null || true
  mise exec -C "$dir" -- bin/rake yard
  echo ""
}

run_for_selected_gems docs_gem
echo "=== ALL DONE ==="
