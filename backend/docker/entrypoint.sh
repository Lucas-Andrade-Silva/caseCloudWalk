#!/bin/sh
set -e

# As gems ficam num volume nomeado. Se o Gemfile mudou depois do build, instala o que falta.
bundle check >/dev/null 2>&1 || bundle install

rm -f tmp/pids/server.pid

exec "$@"
