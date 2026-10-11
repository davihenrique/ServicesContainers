#!/bin/sh
# Checks the syntax of the YAML files given as arguments.
# Relaxed profile: fails only on real syntax/structure errors; style issues become warnings.
set -e

if [ "$#" -eq 0 ]; then
  echo "No files to check"
  exit 0
fi

yamllint -f colored \
  -d '{extends: relaxed, rules: {line-length: disable}}' \
  "$@"
