#!/bin/sh
# Detects the files changed between BASE and HEAD_SHA.
#
# Input (env):
#   BASE      commit to compare against (empty or all zeros = take every file)
#   HEAD_SHA  current commit (default: $GITHUB_SHA or HEAD)
# Output:
#   yaml.txt    added/changed .yml/.yaml files (to lint)
#   deploy.txt  added/changed files inside service folders (to copy to the server)
#   delete.txt  deleted files inside service folders (to remove from the server)
#   removed.txt service folders deleted entirely from the repo (to move to the trash)
#   "yaml" / "deploy" / "delete" / "removed" in $GITHUB_OUTPUT (when set), space separated
# Root files and dot folders (.gitea, ...) are never deployed or deleted.
set -e

ZERO="0000000000000000000000000000000000000000"
HEAD_SHA="${HEAD_SHA:-${GITHUB_SHA:-HEAD}}"

# Manual run, first push or missing base commit: take every file, delete nothing
if [ -z "$BASE" ] || [ "$BASE" = "$ZERO" ] || ! git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  echo "No base commit - taking every file"
  git ls-files > changed.txt
  : > deleted.txt
else
  echo "Comparing $BASE...$HEAD_SHA"
  # --no-renames: a rename becomes a delete of the old path plus an add of the new one
  git diff --name-only --no-renames --diff-filter=ACM "$BASE" "$HEAD_SHA" > changed.txt
  git diff --name-only --no-renames --diff-filter=D "$BASE" "$HEAD_SHA" > deleted.txt
fi

SERVICE_FILES='^[^./][^/]*/'
grep -E '\.ya?ml$' changed.txt > yaml.txt || true
grep -E "$SERVICE_FILES" changed.txt > deploy.txt || true
grep -E "$SERVICE_FILES" deleted.txt > delete.txt || true

# Service folders with deleted files and nothing left in the repo
: > removed.txt
for service in $(sed "s#/.*##" delete.txt | sort -u); do
  if [ -z "$(git ls-tree "$HEAD_SHA" -- "$service")" ]; then echo "$service" >> removed.txt; fi
done

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
print_list "Files to delete" delete.txt
print_list "Service folders removed" removed.txt

# Space-separated lists for the next jobs/steps
if [ -n "$GITHUB_OUTPUT" ]; then
  echo "yaml=$(tr '\n' ' ' < yaml.txt | sed 's/ *$//')" >> "$GITHUB_OUTPUT"
  echo "deploy=$(tr '\n' ' ' < deploy.txt | sed 's/ *$//')" >> "$GITHUB_OUTPUT"
  echo "delete=$(tr '\n' ' ' < delete.txt | sed 's/ *$//')" >> "$GITHUB_OUTPUT"
  echo "removed=$(tr '\n' ' ' < removed.txt | sed 's/ *$//')" >> "$GITHUB_OUTPUT"
fi
