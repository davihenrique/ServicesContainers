#!/bin/sh
# Copies the given files to DEST_DIR on the server, over SSH, keeping their paths.
# e.g. Qbittorrent/compose.yml -> $DEST_DIR/Qbittorrent/compose.yml
# Missing folders are created; existing files are replaced.
#
# Input (env):
#   FILES            space-separated files, relative to the repo root (empty = nothing to do)
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

if [ -z "$FILES" ]; then
  echo "No files to copy"
  exit 0
fi

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

# Runs on the server: unpacks the files into a temp folder, then moves each one into place.
# Each file is written next to its target and renamed, so it is never left half-written.
REMOTE_SCRIPT='
set -e
STAGE=$(mktemp -d)
trap "rm -rf \"$STAGE\"" EXIT
tar -xf - -C "$STAGE"
cd "$STAGE"
find . -type f | sed "s#^\./##" | while IFS= read -r file; do
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
'

# shellcheck disable=SC2086 # FILES is a space-separated list on purpose
tar -cf - $FILES | ssh -i "$KEY_FILE" \
  -p "${SSH_PORT:-22}" \
  -o StrictHostKeyChecking=accept-new \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  "$SSH_USER@$SSH_HOST" \
  "DEST_DIR='$DEST_DIR'; $REMOTE_SCRIPT"
