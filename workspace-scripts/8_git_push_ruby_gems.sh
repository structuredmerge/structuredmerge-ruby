#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ruby_family_common.sh
source "$SCRIPT_DIR/ruby_family_common.sh"

parse_family_selection "$@"

push_gem() {
  local gem="$1"
  local dir="$2"
  [[ -d "$dir" ]] || return 0

  echo "=== $gem ==="
  git -C "$dir" pull
  git -C "$dir" push
  echo ""
}

run_for_selected_gems push_gem

if [[ -x "$RUBY_WORKSPACE/bin/rake" ]]; then
  echo "=== monitor ruby monorepo CI ==="
  (cd "$RUBY_WORKSPACE" && bin/rake ci:act)
  echo ""
fi

echo "=== ALL DONE ==="
