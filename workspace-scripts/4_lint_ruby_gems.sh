#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ruby_family_common.sh
source "$SCRIPT_DIR/ruby_family_common.sh"

parse_family_selection "$@"

lint_gem() {
  local gem="$1"
  local dir="$2"
  local tasks
  [[ -d "$dir" ]] || return 0

  echo "=== $gem ==="
  mise trust -C "$dir" --quiet 2>/dev/null || true
  if [[ -x "$dir/bin/rake" ]]; then
    tasks="$(mise exec -C "$dir" -- bin/rake -T rubocop_gradual 2>/dev/null || true)"
    if [[ "$tasks" != *"rubocop_gradual:autocorrect"* || "$tasks" != *"rubocop_gradual:force_update"* ]]; then
      echo "SKIP: rubocop_gradual rake tasks are unavailable"
      echo ""
      return 0
    fi
    mise exec -C "$dir" -- bin/rake rubocop_gradual:autocorrect
    mise exec -C "$dir" -- bin/rake rubocop_gradual:force_update
  elif [[ -f "$dir/Rakefile" ]]; then
    tasks="$(mise exec -C "$dir" -- bundle exec rake -T rubocop_gradual 2>/dev/null || true)"
    if [[ "$tasks" != *"rubocop_gradual:autocorrect"* || "$tasks" != *"rubocop_gradual:force_update"* ]]; then
      echo "SKIP: rubocop_gradual rake tasks are unavailable"
      echo ""
      return 0
    fi
    mise exec -C "$dir" -- bundle exec rake rubocop_gradual:autocorrect
    mise exec -C "$dir" -- bundle exec rake rubocop_gradual:force_update
  else
    echo "SKIP: no Rakefile or bin/rake"
  fi
  echo ""
}

run_for_selected_gems lint_gem
echo "=== ALL DONE ==="
