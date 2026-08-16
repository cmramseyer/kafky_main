#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SCRIPT_PATH="$SCRIPT_DIR/$(basename -- "${BASH_SOURCE[0]}")"
JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
RVM_SCRIPT="/usr/share/rvm/scripts/rvm"

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

pane_command() {
  local directory=$1
  local command=$2

  if [[ -z "$command" ]]; then
    printf 'cd %q; printf "Karafka no se inicia: kafky_prices no tiene topics configurados.\n"; exec bash' "$directory"
    return
  fi

  printf 'export JAVA_HOME=%q; source %q && rvm use 3.4.3 && cd %q && %s; status=$?; printf "\nProceso finalizado con estado %%s. Presiona Ctrl-D para cerrar este panel.\n" "$status"; exec bash' \
    "$JAVA_HOME" "$RVM_SCRIPT" "$directory" "$command"
}

start_tmux_session() {
  local session=$1
  shift

  local -a labels=()
  local -a directories=()
  local -a commands=()
  local -a panes=()
  local index=0

  while (($#)); do
    labels+=("$1")
    directories+=("$2")
    commands+=("$3")
    shift 3
  done

  panes+=("$(tmux new-session -d -P -F '#{pane_id}' -s "$session" -n services "$(pane_command "${directories[0]}" "${commands[0]}")")")
  panes+=("$(tmux split-window -P -F '#{pane_id}' -t "${panes[0]}" -h "$(pane_command "${directories[1]}" "${commands[1]}")")")
  panes+=("$(tmux split-window -P -F '#{pane_id}' -t "${panes[0]}" -v "$(pane_command "${directories[2]}" "${commands[2]}")")")
  panes+=("$(tmux split-window -P -F '#{pane_id}' -t "${panes[1]}" -v "$(pane_command "${directories[3]}" "${commands[3]}")")")
  tmux select-layout -t "$session:services" tiled

  for index in "${!labels[@]}"; do
    tmux select-pane -t "${panes[$index]}" -T "${labels[$index]}"
  done

  tmux attach-session -t "$session"
}

run_tmux_session() {
  local session=${1:-}

  case "$session" in
    kafky-apps)
      start_tmux_session "$session" \
        "Kafky Rails :3010" "$SCRIPT_DIR/kafky" "bundle exec rails server -p 3010" \
        "Kafky Karafka" "$SCRIPT_DIR/kafky" "bundle exec karafka server" \
        "Kafky Prices Rails :3011" "$SCRIPT_DIR/kafky_prices" "bundle exec rails server -p 3011" \
        "Kafky Prices Karafka (idle)" "$SCRIPT_DIR/kafky_prices" ""
      ;;
    support-apps)
      start_tmux_session "$session" \
        "Kafky Storage Rails :3012" "$SCRIPT_DIR/kafky_storage" "bundle exec rails server -p 3012" \
        "Kafky Storage Karafka" "$SCRIPT_DIR/kafky_storage" "bundle exec karafka server" \
        "Kafky Providers Rails :3013" "$SCRIPT_DIR/kafky_providers" "bundle exec rails server -p 3013" \
        "Kafky Providers Karafka" "$SCRIPT_DIR/kafky_providers" "bundle exec karafka server"
      ;;
    outbox-publishers)
      start_tmux_session "$session" \
        "Kafky Outbox" "$SCRIPT_DIR/kafky" "while true; do bundle exec rails outbox:publish; sleep 5; done" \
        "Kafky Prices Outbox" "$SCRIPT_DIR/kafky_prices" "while true; do bundle exec rails outbox:publish; sleep 5; done" \
        "Kafky Storage Outbox" "$SCRIPT_DIR/kafky_storage" "while true; do bundle exec rails outbox:publish; sleep 5; done" \
        "Kafky Providers Outbox" "$SCRIPT_DIR/kafky_providers" "while true; do bundle exec rails outbox:publish; sleep 5; done"
      ;;
    *)
      fail "sesion tmux desconocida: $session"
      ;;
  esac
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || fail "no se encontro el comando '$1'"
}

if [[ ${1:-} == "--tmux-session" ]]; then
  run_tmux_session "${2:-}"
  exit 0
fi

for directory in "$SCRIPT_DIR/kafky" "$SCRIPT_DIR/kafky_prices" "$SCRIPT_DIR/kafky_storage" "$SCRIPT_DIR/kafky_providers"; do
  [[ -d "$directory" ]] || fail "no existe el directorio '$directory'"
done
[[ -d "$JAVA_HOME" ]] || fail "no existe JAVA_HOME en '$JAVA_HOME'"
[[ -f "$RVM_SCRIPT" ]] || fail "no se encontro RVM en '$RVM_SCRIPT'"

check_command bundle
check_command gnome-terminal
check_command tmux

# Detiene las sesiones anteriores del script para no duplicar procesos.
for session in kafky-apps support-apps outbox-publishers; do
  if tmux has-session -t "$session" 2>/dev/null; then
    tmux kill-session -t "$session"
  fi
done

printf 'Abriendo paneles para las aplicaciones...\n'
gnome-terminal --title="Kafky y Kafky Prices" -- "$SCRIPT_PATH" --tmux-session kafky-apps
gnome-terminal --title="Kafky Storage y Providers" -- "$SCRIPT_PATH" --tmux-session support-apps
gnome-terminal --title="Kafky Outbox Publishers" -- "$SCRIPT_PATH" --tmux-session outbox-publishers
