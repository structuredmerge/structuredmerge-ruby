
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

for repo in "${REPOS[@]}"; do
  echo "=== $repo ==="
  cd "$BASE/$repo" || { echo "FAILED: cd $BASE/$repo"; exit 1; }
  mise trust -C . --quiet 2>/dev/null || true
  result=$(mise exec -- bash -c 'kettle-test' 2>&1)
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "FAILED ($exit_code):"
    echo "$result"
    exit 1
  else
    echo "OK"
    echo "$result" | tail -3
  fi
  echo ""
done
echo "=== ALL DONE ==="
