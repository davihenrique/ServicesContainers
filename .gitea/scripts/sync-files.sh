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
#   SSH_HOST         server
#   SSH_USER         user
#   SSH_PORT         port (default: 22)
#   SSH_PRIVATE_KEY  private key
set -e

: "${DEST_DIR:?DEST_DIR is not set}"
: "${SSH_HOST:?SSH_HOST is not set}"
: "${SSH_USER:?SSH_USER is not set}"
: "${SSH_PRIVATE_KEY:?SSH_PRIVATE_KEY is not set}"

if [ -z "$FILES" ] && [ -z "$DELETE" ]; then
  echo "Nothing to sync"
  exit 0
fi

# Only plain relative paths go to the server (no "..", no absolute paths, no odd characters)
for file in $FILES $DELETE; do
  case "$file" in
    /* | *..* | *[!A-Za-z0-9._/-]*)
      echo "Unsafe path, aborting: $file" >&2
      exit 1
      ;;
  esac
done

KEY_FILE=$(mktemp)
trap 'rm -f "$KEY_FILE"' EXIT
# Strip CRs in case the secret was pasted from Windows
printf '%s\n' "$SSH_PRIVATE_KEY" | tr -d '\r' > "$KEY_FILE"
chmod 600 "$KEY_FILE"

# Show the matching public key, to compare with ~/.ssh/authorized_keys on the server
if ! ssh-keygen -y -f "$KEY_FILE" > /dev/null 2>&1; then
  echo "SSH_PRIVATE_KEY is not a valid private key (or has a passphrase)" >&2
  exit 1
fi
echo "Using key: $(ssh-keygen -l -f "$KEY_FILE")"

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
fi | ssh -i "$KEY_FILE" \
  -p "${SSH_PORT:-22}" \
  -o StrictHostKeyChecking=accept-new \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  "$SSH_USER@$SSH_HOST" \
  "DEST_DIR='$DEST_DIR'; FILES='$FILES'; DELETE='$DELETE'; $REMOTE_SCRIPT"
