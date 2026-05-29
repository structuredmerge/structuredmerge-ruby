#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUBY_WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
GEMS_ROOT="$RUBY_WORKSPACE/gems"

GEMS=(
  tree_haver
  ast-crispr
  ast-crispr-markdown-markly
  ast-crispr-ruby-prism
  ast-merge
  ast-merge-git
  ast-template
  bash-merge
  binary-merge
  citrus-toml-merge
  commonmarker-merge
  dotenv-merge
  go-merge
  json-merge
  kettle-dev
  kettle-drift
  kettle-jem
  kettle-jem-appraisals
  kettle-soup-cover
  kettle-test
  kramdown-merge
  markdown-merge
  markly-merge
  nomono
  parslet-toml-merge
  plain-merge
  prism-merge
  psych-merge
  rbs-merge
  ruby-merge
  rust-merge
  smorg-rb
  stone_checksums
  token-resolver
  toml-merge
  turbo_tests2
  typescript-merge
  yaml-converter
  yaml-merge
  yard-fence
  yard-timekeeper
  yard-yaml
  zip-merge
)

ONLY_GEM=""
START_AT=""

parse_family_selection() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --only)
        ONLY_GEM="${2:?--only requires a gem name}"
        shift 2
        ;;
      --start-at)
        START_AT="${2:?--start-at requires a gem name}"
        shift 2
        ;;
      *)
        echo "Unknown option: $1" >&2
        exit 2
        ;;
    esac
  done
}

selected_gems() {
  local emit=false
  [[ -z "$START_AT" ]] && emit=true

  for gem in "${GEMS[@]}"; do
    if [[ -n "$ONLY_GEM" ]]; then
      [[ "$gem" == "$ONLY_GEM" ]] && printf '%s\n' "$gem"
      continue
    fi

    if [[ "$gem" == "$START_AT" ]]; then
      emit=true
    fi

    [[ "$emit" == true ]] && printf '%s\n' "$gem"
  done
}

gem_dir_for() {
  printf '%s/%s\n' "$GEMS_ROOT" "$1"
}

run_for_selected_gems() {
  local callback="$1"
  local seen=false
  local gem
  while IFS= read -r gem; do
    seen=true
    "$callback" "$gem" "$(gem_dir_for "$gem")"
  done < <(selected_gems)

  if [[ "$seen" == false ]]; then
    echo "No gems matched selection." >&2
    exit 1
  fi
}
