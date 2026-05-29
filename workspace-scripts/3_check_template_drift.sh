#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ruby_family_common.sh
source "$SCRIPT_DIR/ruby_family_common.sh"

parse_family_selection "$@"

check_drift() {
  local gem="$1"
  local dir="$2"
  [[ -d "$dir" ]] || return 0

  echo "=== $gem ==="
  mise trust -C "$dir" --quiet 2>/dev/null || true
  template_dir="$(mise exec -C "$dir" -- bundle exec ruby -e 'require "kettle/jem"; puts Kettle::Jem::DuplicateLineValidator.kettle_template_dir')"
  mise exec -C "$dir" -- bundle exec kettle-drift . --template-dir="$template_dir"
  echo ""
}

run_for_selected_gems check_drift
echo "=== ALL DONE ==="
