#!/bin/sh
# Syncs the changed files with DEST_DIR on the server, over SSH, keeping their paths.
# e.g. qbittorrent/compose.yml -> $DEST_DIR/qbittorrent/compose.yml
# Missing folders are created, existing files are replaced, deleted files are removed
# (and their folders too, once empty: folders holding other data are kept).
# Service folders deleted entirely from the repo are moved, data included, to
# $DEST_DIR/.trash/<service>-<date>, so they can be restored.
#
# Input (env):
#   FILES            space-separated files to copy, relative to the repo root
#   DELETE           space-separated files to remove, relative to the repo root
#   REMOVED          space-separated service folders deleted entirely from the repo
#   DEST_DIR         destination folder on the server
#   SSH_*            see ssh.sh
set -e

if [ -z "$FILES" ] && [ -z "$DELETE" ] && [ -z "$REMOVED" ]; then
  echo "Nothing to sync"
  exit 0
fi

. "$(dirname "$0")/ssh.sh"

# Runs on the server.
# Check: every target folder (or its closest existing parent) must be writable, so the sync
# never stops halfway through.
# Copy: unpacks the files into a temp folder, then moves each one into place; each file is
# written next to its target and renamed, so it is never left half-written.
# Delete: removes each file, then its parent folders while they are empty.
# Trash: moves each removed service folder, as a whole, to $DEST_DIR/.trash.
REMOTE_SCRIPT='
set -e

is_removed() {
  case " $REMOVED " in *" ${1%%/*} "*) return 0 ;; *) return 1 ;; esac
}

denied=""
deny() {
  case " $denied " in *" $1 "*) ;; *) denied="$denied $1" ;; esac
}
for file in $FILES $DELETE; do
  dir="$DEST_DIR/$(dirname "$file")"
  while [ ! -e "$dir" ]; do dir=$(dirname "$dir"); done
  if [ ! -w "$dir" ]; then deny "$dir"; fi
done
# Moving a folder to another parent needs write access to the folder itself and to $DEST_DIR
for service in $REMOVED; do
  if [ -d "$DEST_DIR/$service" ]; then
    if [ ! -w "$DEST_DIR/$service" ]; then deny "$DEST_DIR/$service"; fi
    if [ ! -w "$DEST_DIR" ]; then deny "$DEST_DIR"; fi
  fi
done
if [ -n "$denied" ]; then
  echo "No write permission for $(id -un) in:$denied" >&2
  echo "Nothing was changed." >&2
  exit 1
fi

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
  # Removed services go to the trash whole, compose included
  if is_removed "$file"; then continue; fi
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

for service in $REMOVED; do
  if [ -d "$DEST_DIR/$service" ]; then
    mkdir -p "$DEST_DIR/.trash"
    target="$DEST_DIR/.trash/$service-$(date +%Y%m%d-%H%M%S)"
    mv "$DEST_DIR/$service" "$target"
    echo "trashed folder  $DEST_DIR/$service -> $target"
  fi
done
'

# FILES, DELETE and REMOVED are space-separated lists on purpose
if [ -n "$FILES" ]; then
  # shellcheck disable=SC2086
  tar -cf - $FILES
fi | remote "DEST_DIR='$DEST_DIR'; FILES='$FILES'; DELETE='$DELETE'; REMOVED='$REMOVED'; $REMOTE_SCRIPT"
