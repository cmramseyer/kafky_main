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
[[ -d "$COMPOSE_DIR" ]] || fail "no existe el directorio '$COMPOSE_DIR'"

sudo -v
sudo docker compose version >/dev/null 2>&1 || fail "Docker Compose no esta disponible"

printf 'Deteniendo Kafka y Kafka UI...\n'
(
  cd "$COMPOSE_DIR"
  sudo docker compose down
)
