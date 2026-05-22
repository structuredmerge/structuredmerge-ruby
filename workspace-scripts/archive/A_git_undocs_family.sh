#!/usr/bin/env bash

set -euo pipefail

BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCK_WAIT_SECONDS="${LOCK_WAIT_SECONDS:-1}"
LOCK_MAX_ATTEMPTS="${LOCK_MAX_ATTEMPTS:-120}"

resolve_lock() {
  local repo_path="$1"
  local lock_path="$2"
  local repo_name="$3"
  local attempt=1

  while [ -e "$lock_path" ]; do
    if lsof "$lock_path" >/dev/null 2>&1; then
      if [ "$attempt" -ge "$LOCK_MAX_ATTEMPTS" ]; then
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

  return 0
}

restore_docs_once() {
  local repo_path="$1"
  local output

  if output="$(git -C "$repo_path" restore --source=HEAD --staged --worktree -- docs 2>&1)"; then
    return 0
  fi

  echo "$output"
  return 1
}

restore_docs() {
  local repo_path="$1"
  local repo_name
  local git_dir
  local lock_path
  local attempt=1
  repo_name="$(basename "$repo_path")"

  echo "=== $repo_name ==="

  if ! git -C "$repo_path" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "SKIP: not a git worktree"
    echo ""
    return 0
  fi

  git_dir="$(git -C "$repo_path" rev-parse --absolute-git-dir)"
  lock_path="${git_dir}/index.lock"

  if ! git -C "$repo_path" ls-tree -d --name-only HEAD -- docs | grep -qx "docs"; then
    echo "SKIP: no tracked docs/ in HEAD"
    echo ""
    return 0
  fi

  while true; do
    resolve_lock "$repo_path" "$lock_path" "$repo_name"

    if restore_docs_once "$repo_path"; then
      break
    fi

    if [ -e "$lock_path" ]; then
      if [ "$attempt" -ge "$LOCK_MAX_ATTEMPTS" ]; then
        echo "FAILED: git restore kept colliding with index.lock"
        return 1
      fi

      echo "RETRY: git restore collided with index.lock (${attempt}/${LOCK_MAX_ATTEMPTS})"
      sleep "$LOCK_WAIT_SECONDS"
      attempt=$((attempt + 1))
      continue
    fi

    echo "FAILED: git restore errored for a reason other than index.lock"
    return 1
  done

  if git -C "$repo_path" diff --quiet -- docs && git -C "$repo_path" diff --cached --quiet -- docs; then
    echo "OK: docs/ restored to HEAD"
  else
    echo "FAILED: docs/ still differs after restore"
    return 1
  fi

  echo ""
}

failures=()

while IFS= read -r repo_path; do
  if ! restore_docs "$repo_path"; then
    failures+=("$(basename "$repo_path")")
  fi
done < <(find "$BASE" -mindepth 1 -maxdepth 1 -type d -exec test -d "{}/.git" \; -print | sort)

if [ "${#failures[@]}" -gt 0 ]; then
  echo "FAILED REPOS: ${failures[*]}"
  exit 1
fi

echo "=== ALL DONE ==="
