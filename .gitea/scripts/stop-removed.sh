#!/bin/sh
# Stops the services whose compose file is about to be deleted from the server.
# Must run BEFORE sync-files.sh: once the compose file is gone, podman compose can no
# longer find the containers to stop.
#
# Input (env):
#   DELETE    space-separated files to remove, relative to the repo root
#   DEST_DIR  destination folder on the server
#   SSH_*, PODMAN_SUDO  see ssh.sh
set -e

. "$(dirname "$0")/ssh.sh"

# Deleted compose files only
COMPOSES=""
for file in $DELETE; do
  for name in $COMPOSE_NAMES; do
    if [ "${file##*/}" = "$name" ]; then COMPOSES="$COMPOSES $file"; fi
  done
done

if [ -z "$COMPOSES" ]; then
  echo "No compose file deleted - nothing to stop"
  exit 0
fi

remote "DEST_DIR='$DEST_DIR'; COMPOSES='$COMPOSES'; PODMAN='$PODMAN'; $REMOTE_LIB"'
failed=""
for file in $COMPOSES; do
  if [ ! -f "$DEST_DIR/$file" ]; then
    echo "== $file: not on the server, skipping"
    continue
  fi
  foreign=$(foreign_containers "$DEST_DIR/${file%/*}" "${file##*/}")
  if [ -n "$foreign" ]; then
    echo "== $file: NOT stopping, container name used by another service: $foreign" >&2
    failed="$failed $file"
    continue
  fi
  echo "== $file: stopping"
  ( cd "$DEST_DIR/${file%/*}" && $PODMAN compose -f "${file##*/}" down ) || failed="$failed $file"
done

if [ -n "$failed" ]; then
  echo "Failed to stop:$failed" >&2
  exit 1
fi
'
