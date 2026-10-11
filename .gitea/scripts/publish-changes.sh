#!/bin/sh
# Writes the list of changed composes (one per line) to a file on the server, over SSH.
#
# Input (env):
#   COMPOSES         space-separated composes (empty = empty file)
#   OUTPUT_FILE      file path on the server
#   SSH_HOST         server
#   SSH_USER         user
#   SSH_PORT         port (default: 22)
#   SSH_PRIVATE_KEY  private key
set -e

: "${OUTPUT_FILE:?OUTPUT_FILE is not set}"
: "${SSH_HOST:?SSH_HOST is not set}"
: "${SSH_USER:?SSH_USER is not set}"
: "${SSH_PRIVATE_KEY:?SSH_PRIVATE_KEY is not set}"

KEY_FILE=$(mktemp)
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s\n' "$SSH_PRIVATE_KEY" > "$KEY_FILE"
chmod 600 "$KEY_FILE"

# One line per compose; empty when no compose changed
printf '%s\n' $COMPOSES | sed '/^$/d' > list.txt
echo "Contents of $OUTPUT_FILE:"
cat list.txt

# Write to a temp file and move it, so the file is never left half-written
ssh -i "$KEY_FILE" \
  -p "${SSH_PORT:-22}" \
  -o StrictHostKeyChecking=accept-new \
  "$SSH_USER@$SSH_HOST" \
  "cat > '$OUTPUT_FILE.tmp' && mv '$OUTPUT_FILE.tmp' '$OUTPUT_FILE'" < list.txt
