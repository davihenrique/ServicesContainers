#!/bin/sh
# Recreates the containers of every service with changed or deleted files:
# podman compose down, then up. Services without a compose file left on the server
# (removed services) are skipped; stop-removed.sh already stopped them.
# A failing service does not stop the others; the step fails at the end.
#
# Input (env):
#   FILES     space-separated changed files, relative to the repo root
#   DELETE    space-separated deleted files, relative to the repo root
#   DEST_DIR  destination folder on the server
#   SSH_*     see ssh.sh
set -e

. "$(dirname "$0")/ssh.sh"

# shellcheck disable=SC2086 # space-separated lists on purpose
SERVICES=$(services_of $FILES $DELETE | tr '\n' ' ')

if [ -z "$SERVICES" ]; then
  echo "No service changed - nothing to restart"
  exit 0
fi
echo "Services to restart: $SERVICES"

remote "DEST_DIR='$DEST_DIR'; SERVICES='$SERVICES'; COMPOSE_NAMES='$COMPOSE_NAMES';"'
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

  echo "== $service: recreating ($compose)"
  (
    cd "$DEST_DIR/$service" &&
      podman compose -f "$compose" down --remove-orphans &&
      podman compose -f "$compose" up -d --build
  ) || failed="$failed $service"
done

if [ -n "$failed" ]; then
  echo "Failed services:$failed" >&2
  exit 1
fi
'
