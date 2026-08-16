#!/usr/bin/env bash

set -euo pipefail

command -v tmux >/dev/null 2>&1 || {
  printf "Error: no se encontro el comando 'tmux'\n" >&2
  exit 1
}

for session in kafky-apps support-apps outbox-publishers; do
  if tmux has-session -t "$session" 2>/dev/null; then
    printf 'Deteniendo la sesion %s...\n' "$session"
    tmux kill-session -t "$session"
  fi
done

printf 'Las aplicaciones Rails, Karafka y los publicadores outbox fueron detenidos.\n'
