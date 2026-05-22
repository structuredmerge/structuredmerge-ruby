
REPOS=(
  kettle-jem
  kettle-jem-appraisals
  kettle-dev
  kettle-drift
  kettle-test
  kettle-soup-cover
  markdown-merge
  markly-merge
  commonmarker-merge
  rbs-merge
  psych-merge
  prism-merge
  jsonc-merge
  json-merge
  toml-merge
  dotenv-merge
  bash-merge
  ast-merge
  ast-crispr
  ast-crispr-ruby-prism
  ast-crispr-markdown-markly
  tree_haver
  nomono
  turbo_tests2
  yard-fence
  yard-timekeeper
  yard-yaml
  version_gem
)

BASE=/home/pboling/src/kettle-rb
failures=()

for repo in "${REPOS[@]}"; do
  echo "=== $repo ==="
  cd "$BASE/$repo" || {
    echo "FAILED: cd"
    failures+=("$repo:cd")
    echo ""
    continue
  }
  mise trust -C . --quiet 2>/dev/null || true
  template_dir=$(mise exec -- bundle exec ruby -e 'require "kettle/jem"; puts Kettle::Jem::DuplicateLineValidator.kettle_template_dir' 2>&1)
  template_exit=$?
  if [ $template_exit -ne 0 ]; then
    echo "$template_dir"
    echo ""
    echo "FAILED ($template_exit) resolving kettle-jem template in $repo"
    failures+=("$repo:template:$template_exit")
    echo ""
    continue
  fi

  result=$(mise exec -- bash -c 'bundle exec kettle-drift . --template-dir="$1"' _ "$template_dir" 2>&1)
  exit_code=$?
  echo "$result"
  if [ $exit_code -ne 0 ]; then
    echo ""
    echo "FAILED ($exit_code) in $repo"
    failures+=("$repo:$exit_code")
  fi
  echo ""
done

if [ ${#failures[@]} -ne 0 ]; then
  echo "=== FAILURES ==="
  printf '%s\n' "${failures[@]}"
  exit 1
fi

echo "=== ALL DONE ==="
