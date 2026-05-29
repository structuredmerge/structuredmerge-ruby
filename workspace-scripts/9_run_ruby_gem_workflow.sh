#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

family_args=()
args=("$@")
index=0
while [[ "$index" -lt "${#args[@]}" ]]; do
  case "${args[$index]}" in
    --only|--start-at)
      family_args+=("${args[$index]}" "${args[$((index + 1))]:?${args[$index]} requires a gem name}")
      index=$((index + 2))
      ;;
    *)
      index=$((index + 1))
      ;;
  esac
done

"$SCRIPT_DIR/0_install_local_template_stack.rb"
"$SCRIPT_DIR/1_template_ruby_gems.rb" "$@"
"$SCRIPT_DIR/2_check_template_drift.sh" "${family_args[@]}"
"$SCRIPT_DIR/3_lint_ruby_gems.sh" "${family_args[@]}"
"$SCRIPT_DIR/4_test_ruby_gems.sh" "${family_args[@]}"
"$SCRIPT_DIR/5_docs_ruby_gems.sh" "${family_args[@]}"
