#!/bin/sh
# Detects the .yml/.yaml files changed between BASE and HEAD_SHA and, among them, the compose files.
#
# Input (env):
#   BASE      commit to compare against (empty or all zeros = take every file)
#   HEAD_SHA  current commit (default: $GITHUB_SHA or HEAD)
# Output:
#   changed.txt / composes.txt, plus "files" / "composes" in $GITHUB_OUTPUT (when set)
set -e

ZERO="0000000000000000000000000000000000000000"
HEAD_SHA="${HEAD_SHA:-${GITHUB_SHA:-HEAD}}"

# Manual run, first push or missing base commit: take every file
if [ -z "$BASE" ] || [ "$BASE" = "$ZERO" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo "No base commit - taking every .yml/.yaml file"
  git ls-files '*.yml' '*.yaml' > changed.txt
else
  echo "Comparing $BASE...$HEAD_SHA"
  git diff --name-only --diff-filter=ACMR "$BASE" "$HEAD_SHA" -- '*.yml' '*.yaml' > changed.txt
fi

# Compose files only (compose.yml, docker-compose.yaml, ...)
grep -E '(^|/)(docker-)?compose\.ya?ml$' changed.txt > composes.txt || true

print_list() {
  echo "$1:"
  if [ -s "$2" ]; then
    sed 's/^/  - /' "$2"
  else
    echo "  (none)"
  fi
}
print_list "Changed files" changed.txt
print_list "Changed composes" composes.txt

# Space-separated lists for the next jobs/steps
if [ -n "$GITHUB_OUTPUT" ]; then
  echo "files=$(tr '\n' ' ' < changed.txt | sed 's/ *$//')" >> "$GITHUB_OUTPUT"
  echo "composes=$(tr '\n' ' ' < composes.txt | sed 's/ *$//')" >> "$GITHUB_OUTPUT"
fi
