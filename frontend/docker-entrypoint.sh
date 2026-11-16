#!/bin/sh
set -e

# node_modules fica num volume. Se o package-lock.json mudou depois do build, instala de novo.
stamp=node_modules/.package-lock.sha
current=$(sha256sum package-lock.json | cut -d' ' -f1)
if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$current" ]; then
  npm ci
  echo "$current" > "$stamp"
fi

exec "$@"
