#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
COMPOSE_DIR="$SCRIPT_DIR/kafky_kafka"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

command -v sudo >/dev/null 2>&1 || fail "no se encontro el comando 'sudo'"
command -v docker >/dev/null 2>&1 || fail "no se encontro el comando 'docker'"
command -v gnome-terminal >/dev/null 2>&1 || fail "no se encontro el comando 'gnome-terminal'"
[[ -d "$COMPOSE_DIR" ]] || fail "no existe el directorio '$COMPOSE_DIR'"
docker compose version >/dev/null 2>&1 || fail "Docker Compose no esta disponible"

printf 'Abriendo Docker Compose en una terminal dedicada...\n'
gnome-terminal --title="Kafka Docker Compose" -- bash -c '
  cd "$1" && sudo docker compose down && exec sudo docker compose up
' bash "$COMPOSE_DIR"
