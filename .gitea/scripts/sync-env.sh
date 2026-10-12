#!/bin/sh
# Writes the .env file of each service on the server from its ENV_<SERVICE> variable.
# The variable holds the whole .env content (KEY=value lines, built from the secrets in
# deploy.yml); its name is the service folder in upper case, with "-" as "_"
# (e.g. uptime-kuma -> ENV_UPTIME_KUMA).
# A KEY= line with no value means a missing secret: the step fails before writing anything.
# Services without the variable are left alone (a .env created by hand stays as it is).
# Only files whose content changed are rewritten; the contents are never printed.
#
# Input (env):
#   ENV_<SERVICE>    .env content of each service (mapped from the secrets in deploy.yml)
#   DEST_DIR         destination folder on the server
#   SSH_*            see ssh.sh
# Output:
#   "changed" in $GITHUB_OUTPUT (when set): space-separated services whose .env changed
set -e

STAGE=$(mktemp -d)
SERVICES=""
MISSING=""
for dir in */; do
  service=${dir%/}
  var="ENV_$(printf '%s' "$service" | tr 'a-z-' 'A-Z_')"
  case "$var" in *[!A-Z0-9_]*) continue ;; esac
  eval "value=\${$var:-}"
  if [ -z "$value" ]; then continue; fi
  mkdir -p "$STAGE/$service"
  # Strip CRs in case the secret was pasted from Windows
  printf '%s\n' "$value" | tr -d '\r' > "$STAGE/$service/.env"
  for key in $(sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=[[:space:]]*$/\1/p' "$STAGE/$service/.env"); do
    MISSING="$MISSING $service:$key"
  done
  SERVICES="$SERVICES $service"
done

if [ -n "$MISSING" ]; then
  echo "Empty values (secret missing or empty in Gitea), nothing was written:$MISSING" >&2
  rm -rf "$STAGE"
  exit 1
fi

if [ -z "$SERVICES" ]; then
  echo "No ENV_* secret set - nothing to write"
  rm -rf "$STAGE"
  exit 0
fi
echo "Services with secrets:$SERVICES"

. "$(dirname "$0")/ssh.sh"
trap 'rm -f "$KEY_FILE"; rm -rf "$STAGE"' EXIT

# Runs on the server: each .env is written next to its target and renamed, readable by its owner only.
# Prints "changed: <services>" as the last line.
REMOTE_SCRIPT='
set -e
umask 077
STAGE=$(mktemp -d)
trap "rm -rf \"$STAGE\"" EXIT
tar -xf - -C "$STAGE"
changed=""
for service in $SERVICES; do
  target="$DEST_DIR/$service/.env"
  if [ ! -d "$DEST_DIR/$service" ]; then
    echo "== $service: folder not on the server, skipping"
    continue
  fi
  if [ -r "$target" ] && [ "$(cat "$target")" = "$(cat "$STAGE/$service/.env")" ]; then
    echo "== $service: .env unchanged"
    continue
  fi
  cp "$STAGE/$service/.env" "$target.tmp"
  chmod 600 "$target.tmp"
  mv "$target.tmp" "$target"
  echo "== $service: .env written"
  changed="$changed $service"
done
echo "changed:$changed"
'

ENV_FILES=""
for service in $SERVICES; do ENV_FILES="$ENV_FILES $service/.env"; done

# shellcheck disable=SC2086 # space-separated list on purpose
OUTPUT=$(tar -cf - -C "$STAGE" $ENV_FILES |
  remote "DEST_DIR='$DEST_DIR'; SERVICES='$SERVICES'; $REMOTE_SCRIPT") || {
  printf '%s\n' "$OUTPUT"
  exit 1
}
printf '%s\n' "$OUTPUT" | grep -v '^changed:' || true

CHANGED=$(printf '%s\n' "$OUTPUT" | sed -n 's/^changed: *//p')
if [ -n "$GITHUB_OUTPUT" ]; then
  echo "changed=$CHANGED" >> "$GITHUB_OUTPUT"
fi
