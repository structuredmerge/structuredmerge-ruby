#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ruby_family_common.sh
source "$SCRIPT_DIR/ruby_family_common.sh"

LOCK_WAIT_SECONDS="${LOCK_WAIT_SECONDS:-1}"
LOCK_MAX_ATTEMPTS="${LOCK_MAX_ATTEMPTS:-120}"

parse_family_selection "$@"

resolve_lock() {
  local lock_path="$1"
  local attempt=1

  while [[ -e "$lock_path" ]]; do
    if lsof "$lock_path" >/dev/null 2>&1; then
      if [[ "$attempt" -ge "$LOCK_MAX_ATTEMPTS" ]]; then
        echo "FAILED: active git lock persisted after ${LOCK_MAX_ATTEMPTS} attempts"
        return 1
      fi

      echo "WAIT: active git lock detected (${attempt}/${LOCK_MAX_ATTEMPTS})"
      sleep "$LOCK_WAIT_SECONDS"
      attempt=$((attempt + 1))
      continue
    fi

    echo "HEAL: removing stale git lock"
    rm -f "$lock_path"
  done
}

restore_docs() {
  local gem="$1"
  local dir="$2"
  [[ -d "$dir" ]] || return 0

  echo "=== $gem ==="
  if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "SKIP: not a git worktree"
    echo ""
    return 0
  fi

  if ! git -C "$dir" ls-tree -d --name-only HEAD -- docs | grep -qx "docs"; then
    echo "SKIP: no tracked docs/ in HEAD"
    echo ""
    return 0
  fi

  local git_dir
  local lock_path
  git_dir="$(git -C "$dir" rev-parse --absolute-git-dir)"
  lock_path="${git_dir}/index.lock"
  resolve_lock "$lock_path"

  git -C "$dir" restore --source=HEAD --staged --worktree -- docs
  if git -C "$dir" diff --quiet -- docs && git -C "$dir" diff --cached --quiet -- docs; then
    echo "OK: docs/ restored to HEAD"
  else
    echo "FAILED: docs/ still differs after restore"
    return 1
  fi
  echo ""
}

run_for_selected_gems restore_docs
echo "=== ALL DONE ==="
