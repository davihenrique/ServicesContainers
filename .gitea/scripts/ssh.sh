#!/bin/sh
# Shared SSH setup, sourced by the deploy scripts.
# Checks the inputs, writes the key to a temp file and defines remote(), which runs a
# command on the server (stdin is forwarded).
#
# Input (env):
#   FILES / DELETE / REMOVED  space-separated repo paths (checked for safety)
#   DEST_DIR         destination folder on the server
#   SSH_HOST         server
#   SSH_USER         user
#   SSH_PORT         port (default: 22)
#   SSH_PRIVATE_KEY  private key
#   PODMAN_SUDO      "true" to run podman as root through sudo (default: rootless)

: "${DEST_DIR:?DEST_DIR is not set}"
: "${SSH_HOST:?SSH_HOST is not set}"
: "${SSH_USER:?SSH_USER is not set}"
: "${SSH_PRIVATE_KEY:?SSH_PRIVATE_KEY is not set}"

# Only plain relative paths go to the server (no "..", no absolute paths, no odd characters)
for file in $FILES $DELETE $REMOVED; do
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

remote() {
  ssh -i "$KEY_FILE" \
    -p "${SSH_PORT:-22}" \
    -o StrictHostKeyChecking=accept-new \
    -o BatchMode=yes \
    -o IdentitiesOnly=yes \
    "$SSH_USER@$SSH_HOST" \
    "$@"
}

# Prints the service folders (first path component) of the given paths, once each
services_of() {
  for file in "$@"; do
    echo "${file%%/*}"
  done | sort -u
}

# Compose file names, in the order podman compose looks for them
COMPOSE_NAMES="compose.yaml compose.yml docker-compose.yaml docker-compose.yml"

# Podman command run on the server: rootful through sudo when PODMAN_SUDO=true, rootless otherwise.
# sudo -n fails right away instead of waiting for a password.
if [ "$PODMAN_SUDO" = "true" ]; then
  PODMAN="sudo -n podman"
else
  PODMAN="podman"
fi
echo "Podman: $PODMAN"
