#!/bin/sh
# Syncs the changed files with DEST_DIR on the server, over SSH, keeping their paths.
# e.g. qbittorrent/compose.yml -> $DEST_DIR/qbittorrent/compose.yml
# Missing folders are created, existing files are replaced, deleted files are removed
# (and their folders too, once empty: folders holding other data are kept).
#
# Input (env):
#   FILES            space-separated files to copy, relative to the repo root
#   DELETE           space-separated files to remove, relative to the repo root
#   DEST_DIR         destination folder on the server
#   SSH_*            see ssh.sh
set -e

if [ -z "$FILES" ] && [ -z "$DELETE" ]; then
  echo "Nothing to sync"
  exit 0
fi

. "$(dirname "$0")/ssh.sh"

# Runs on the server.
# Copy: unpacks the files into a temp folder, then moves each one into place; each file is
# written next to its target and renamed, so it is never left half-written.
# Delete: removes each file, then its parent folders while they are empty.
REMOTE_SCRIPT='
set -e

if [ -n "$FILES" ]; then
  STAGE=$(mktemp -d)
  trap "rm -rf \"$STAGE\"" EXIT
  tar -xf - -C "$STAGE"
  cd "$STAGE"
  for file in $FILES; do
    dir=$(dirname "$file")
    if [ ! -d "$DEST_DIR/$dir" ]; then
      mkdir -p "$DEST_DIR/$dir"
      echo "created folder  $DEST_DIR/$dir"
    fi
    if [ -e "$DEST_DIR/$file" ]; then action="replaced file "; else action="created file  "; fi
    cp "$file" "$DEST_DIR/$file.tmp"
    mv "$DEST_DIR/$file.tmp" "$DEST_DIR/$file"
    echo "$action $DEST_DIR/$file"
  done
fi

for file in $DELETE; do
  if [ -e "$DEST_DIR/$file" ]; then
    rm -f "$DEST_DIR/$file"
    echo "deleted file    $DEST_DIR/$file"
  fi
  dir=$(dirname "$file")
  while [ "$dir" != "." ] && rmdir "$DEST_DIR/$dir" 2>/dev/null; do
    echo "deleted folder  $DEST_DIR/$dir"
    dir=$(dirname "$dir")
  done
done
'

# FILES and DELETE are space-separated lists on purpose
if [ -n "$FILES" ]; then
  # shellcheck disable=SC2086
  tar -cf - $FILES
fi | remote "DEST_DIR='$DEST_DIR'; FILES='$FILES'; DELETE='$DELETE'; $REMOTE_SCRIPT"
