#!/bin/sh
# Detects the files changed between BASE and HEAD_SHA.
#
# Input (env):
#   BASE      commit to compare against (empty or all zeros = take every file)
#   HEAD_SHA  current commit (default: $GITHUB_SHA or HEAD)
# Output:
#   yaml.txt    changed .yml/.yaml files (to lint)
#   deploy.txt  changed files inside service folders (to copy to the server);
#               root files and dot folders (.gitea, ...) are left out
#   "yaml" / "deploy" in $GITHUB_OUTPUT (when set), space separated
set -e

ZERO="0000000000000000000000000000000000000000"
HEAD_SHA="${HEAD_SHA:-${GITHUB_SHA:-HEAD}}"

# Manual run, first push or missing base commit: take every file
if [ -z "$BASE" ] || [ "$BASE" = "$ZERO" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo "No base commit - taking every file"
  git ls-files > changed.txt
else
  echo "Comparing $BASE...$HEAD_SHA"
  git diff --name-only --diff-filter=ACMR "$BASE" "$HEAD_SHA" > changed.txt
fi

grep -E '\.ya?ml$' changed.txt > yaml.txt || true
grep -E '^[^./][^/]*/' changed.txt > deploy.txt || true

print_list() {
  echo "$1:"
  if [ -s "$2" ]; then
    sed 's/^/  - /' "$2"
  else
    echo "  (none)"
  fi
}
print_list "Changed YAML files" yaml.txt
print_list "Files to deploy" deploy.txt

# Space-separated lists for the next jobs/steps
if [ -n "$GITHUB_OUTPUT" ]; then
  echo "yaml=$(tr '\n' ' ' < yaml.txt | sed 's/ *$//')" >> "$GITHUB_OUTPUT"
  echo "deploy=$(tr '\n' ' ' < deploy.txt | sed 's/ *$//')" >> "$GITHUB_OUTPUT"
fi
