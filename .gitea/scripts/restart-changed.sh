#!/bin/sh
# Recreates the containers of every service with changed or deleted files, or a rewritten
# .env: podman compose down, then up. Services without a compose file left on the server
# (removed services) are skipped; stop-removed.sh already stopped them.
# A failing service does not stop the others; the step fails at the end.
#
# Input (env):
#   FILES     space-separated changed files, relative to the repo root
#   DELETE    space-separated deleted files, relative to the repo root
#   ENV_CHANGED  space-separated services whose .env was rewritten (sync-env.sh)
#   DEST_DIR  destination folder on the server
#   SSH_*, PODMAN_SUDO  see ssh.sh
set -e

. "$(dirname "$0")/ssh.sh"

# shellcheck disable=SC2086 # space-separated lists on purpose
SERVICES=$(services_of $FILES $DELETE $ENV_CHANGED | tr '\n' ' ')

if [ -z "$SERVICES" ]; then
  echo "No service changed - nothing to restart"
  exit 0
fi
echo "Services to restart: $SERVICES"

remote "DEST_DIR='$DEST_DIR'; SERVICES='$SERVICES'; COMPOSE_NAMES='$COMPOSE_NAMES'; PODMAN='$PODMAN'; $REMOTE_LIB"'
failed=""
for service in $SERVICES; do
  compose=""
  for name in $COMPOSE_NAMES; do
    if [ -f "$DEST_DIR/$service/$name" ]; then compose="$name"; break; fi
  done
  if [ -z "$compose" ]; then
    echo "== $service: no compose file, skipping"
    continue
  fi
  foreign=$(foreign_containers "$DEST_DIR/$service" "$compose")
  if [ -n "$foreign" ]; then
    echo "== $service: NOT recreating, container name used by another service: $foreign" >&2
    failed="$failed $service"
    continue
  fi

  echo "== $service: recreating ($compose)"
  (
    cd "$DEST_DIR/$service" &&
      $PODMAN compose -f "$compose" down --remove-orphans &&
      $PODMAN compose -f "$compose" up -d --build
  ) || failed="$failed $service"
done

if [ -n "$failed" ]; then
  echo "Failed services:$failed" >&2
  exit 1
fi
'
