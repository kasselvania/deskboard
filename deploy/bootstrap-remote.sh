#!/usr/bin/env bash
set -euo pipefail

readonly deskboard_stack_name="deskboard"
readonly deskboard_private_directory=".deskboard-private"
readonly deskboard_proxy_port="18080"

require_absolute_directory() {
  local value="$1"
  [[ "$value" == /* && "$value" != "/" && "$value" != *$'\n'* ]]
}

select_dockge_stacks_directory() {
  local configured_container_path="$1"
  local selected=""
  local matching_mount_seen=0
  local type source destination

  while IFS=$'\t' read -r type source destination; do
    [[ -n "$type$source$destination" ]] || continue
    if [[ "$destination" == "$configured_container_path" ]]; then
      matching_mount_seen=$((matching_mount_seen + 1))
      [[ "$matching_mount_seen" -eq 1 && "$type" == "bind" ]] || return 1
      selected="$source"
    fi
  done

  if [[ -n "$selected" ]]; then
    require_absolute_directory "$selected" || return 1
    printf '%s\n' "$selected"
  elif [[ "$configured_container_path" == "/opt/stacks" && "$matching_mount_seen" -eq 0 ]]; then
    printf '%s\n' "/opt/stacks"
  else
    return 1
  fi
}

discover_dockge_stacks_directory() {
  command -v docker >/dev/null 2>&1 || return 1
  docker compose version >/dev/null 2>&1 || return 1

  local container_id=""
  local match_count=0
  local id image name lowered
  while IFS=$'\t' read -r id image name; do
    lowered="$(printf '%s' "$image $name" | tr '[:upper:]' '[:lower:]')"
    if [[ "$lowered" == *dockge* ]]; then
      container_id="$id"
      match_count=$((match_count + 1))
    fi
  done < <(docker ps --filter status=running --format '{{.ID}}\t{{.Image}}\t{{.Names}}')
  [[ "$match_count" -eq 1 && -n "$container_id" ]] || return 1

  local configured_container_path="/opt/stacks"
  local entry
  while IFS= read -r entry; do
    case "$entry" in
      DOCKGE_STACKS_DIR=*)
        configured_container_path="${entry#DOCKGE_STACKS_DIR=}"
        ;;
    esac
  done < <(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$container_id")
  require_absolute_directory "$configured_container_path" || return 1

  docker inspect \
    --format '{{range .Mounts}}{{printf "%s\t%s\t%s\n" .Type .Source .Destination}}{{end}}' \
    "$container_id" \
    | select_dockge_stacks_directory "$configured_container_path"
}

prepare_stage() {
  local stacks_directory="$1"
  require_absolute_directory "$stacks_directory" || return 1
  [[ "$(id -u)" == "1000" ]] || return 1
  mkdir -p "$stacks_directory"
  [[ -w "$stacks_directory" ]] || return 1
  mktemp -d "$stacks_directory/.deskboard.bootstrap.XXXXXX"
}

discard_stage() {
  local stage_directory="$1"
  require_absolute_directory "$stage_directory" || return 1
  local parent base
  parent="$(dirname -- "$stage_directory")"
  base="$(basename -- "$stage_directory")"
  [[ "$parent" != "/" && "$base" == .deskboard.bootstrap.* ]] || return 1
  [[ -d "$stage_directory" ]] || return 0
  rm -rf "$stage_directory"
}

install_stage() {
  local stacks_directory="$1"
  local stage_directory="$2"
  require_absolute_directory "$stacks_directory" || return 1
  require_absolute_directory "$stage_directory" || return 1
  [[ "$stage_directory" == "$stacks_directory"/.deskboard.bootstrap.* ]] || return 1
  [[ -f "$stage_directory/compose.yaml" ]] || return 1

  local stack_directory="$stacks_directory/$deskboard_stack_name"
  local private_source="$stack_directory/$deskboard_private_directory"
  local private_target="$stage_directory/$deskboard_private_directory"
  local backup_directory=""

  if [[ -d "$private_source" ]]; then
    cp -pR "$private_source" "$private_target"
  fi

  if [[ -e "$stack_directory" ]]; then
    backup_directory="$(mktemp -d "$stacks_directory/.deskboard.previous.XXXXXX")"
    rmdir "$backup_directory"
    mv "$stack_directory" "$backup_directory"
  fi

  if mv "$stage_directory" "$stack_directory"; then
    if [[ -n "$backup_directory" ]]; then
      rm -rf "$backup_directory"
    fi
    return 0
  fi

  if [[ -n "$backup_directory" && ! -e "$stack_directory" ]]; then
    mv "$backup_directory" "$stack_directory" || true
  fi
  return 1
}

write_secret() {
  local target="$1"
  [[ "$target" == /*/deskboard/.deskboard-private/apple-bridge-token ]] || return 1
  local directory temporary
  directory="$(dirname -- "$target")"
  umask 077
  mkdir -p "$directory"
  chmod 0700 "$directory"
  temporary="$(mktemp "$directory/.apple-bridge-token.XXXXXX")"
  cat >"$temporary"
  chmod 0600 "$temporary"
  if [[ "$(wc -c <"$temporary" | tr -d ' ')" != "64" ]] \
    || ! LC_ALL=C grep -Eq '^[0-9a-f]{64}$' "$temporary"; then
    rm -f "$temporary"
    return 1
  fi
  mv -f "$temporary" "$target"
}

write_runtime_configuration() {
  local target="$1"
  [[ "$target" == /*/deskboard/.deskboard-private/runtime.env ]] || return 1
  local directory temporary
  directory="$(dirname -- "$target")"
  umask 077
  mkdir -p "$directory"
  chmod 0700 "$directory"
  temporary="$(mktemp "$directory/.runtime.XXXXXX")"
  cat >"$temporary"
  chmod 0600 "$temporary"

  if [[ "$(grep -c '^' "$temporary")" != "4" ]] \
    || ! grep -Eq '^DESKBOARD_APPLE_BRIDGE_ID=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' "$temporary" \
    || ! grep -Fxq 'DESKBOARD_APPLE_MIRROR_DATABASE_PATH=/var/lib/deskboard/deskboard.sqlite' "$temporary" \
    || ! grep -Fxq 'DESKBOARD_BOARD_MODE=apple-mirror' "$temporary" \
    || ! grep -Eq '^DESKBOARD_BOARD_TIME_ZONE=[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+$' "$temporary" \
    || grep -Eq 'TOKEN|SECRET' "$temporary"; then
    rm -f "$temporary"
    return 1
  fi

  mv -f "$temporary" "$target"
}

wait_for_service_health() {
  local stack_directory="$1"
  local service="$2"
  local container_id status
  container_id="$(cd "$stack_directory" && docker compose -f compose.yaml ps --quiet "$service")"
  [[ -n "$container_id" ]] || return 1
  for _ in $(seq 1 60); do
    status="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id")"
    [[ "$status" == "healthy" ]] && return 0
    [[ "$(docker inspect --format '{{.State.Status}}' "$container_id")" != "exited" ]] || return 1
    sleep 1
  done
  return 1
}

compose_up() (
  local stack_directory="$1"
  [[ "$stack_directory" == /*/deskboard && -f "$stack_directory/compose.yaml" ]] || return 1
  local private_directory="$stack_directory/$deskboard_private_directory"
  local secret_file="$private_directory/apple-bridge-token"
  local runtime_file="$private_directory/runtime.env"
  [[ -f "$secret_file" && -f "$runtime_file" ]] || return 1
  [[ "$(stat -c '%a:%u' "$secret_file")" == "600:1000" ]] || return 1
  [[ "$(stat -c '%a:%u' "$runtime_file")" == "600:1000" ]] || return 1

  local audit_directory
  audit_directory="$(mktemp -d "$private_directory/.audit.XXXXXX")"
  chmod 0700 "$audit_directory"
  cleanup_audit() {
    local exit_status=$?
    trap - EXIT
    rm -rf "$audit_directory"
    exit "$exit_status"
  }
  trap cleanup_audit EXIT

  (
    cd "$stack_directory"
    DESKBOARD_RUNTIME_ENV_FILE=./.deskboard-private/runtime.env \
      DESKBOARD_APPLE_BRIDGE_TOKEN_SECRET_FILE=./.deskboard-private/apple-bridge-token \
      DESKBOARD_PROXY_BIND_PORT="$deskboard_proxy_port" \
      docker compose -f compose.yaml config --quiet \
      >"$audit_directory/config-check.log" 2>&1
    DESKBOARD_RUNTIME_ENV_FILE=./.deskboard-private/runtime.env \
      DESKBOARD_APPLE_BRIDGE_TOKEN_SECRET_FILE=./.deskboard-private/apple-bridge-token \
      DESKBOARD_PROXY_BIND_PORT="$deskboard_proxy_port" \
      docker compose -f compose.yaml up --detach --build \
      >"$audit_directory/up.log" 2>&1
    docker compose -f compose.yaml restart api \
      >"$audit_directory/restart.log" 2>&1
  )

  wait_for_service_health "$stack_directory" api || return 1
  wait_for_service_health "$stack_directory" private-proxy || return 1
  local health_status
  health_status="$(curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --max-time 10 \
    "http://127.0.0.1:$deskboard_proxy_port/health")" || return 1
  [[ "$health_status" == "200" ]] || return 1

  local api_id proxy_id
  api_id="$(cd "$stack_directory" && docker compose -f compose.yaml ps --quiet api)"
  proxy_id="$(cd "$stack_directory" && docker compose -f compose.yaml ps --quiet private-proxy)"
  (
    cd "$stack_directory"
    DESKBOARD_RUNTIME_ENV_FILE=./.deskboard-private/runtime.env \
      DESKBOARD_APPLE_BRIDGE_TOKEN_SECRET_FILE=./.deskboard-private/apple-bridge-token \
      DESKBOARD_PROXY_BIND_PORT="$deskboard_proxy_port" \
      docker compose -f compose.yaml config >"$audit_directory/compose.txt"
    docker compose -f compose.yaml logs --no-color api private-proxy \
      >"$audit_directory/logs.txt" 2>&1
  )
  docker inspect "$api_id" "$proxy_id" >"$audit_directory/inspect.json"
  docker history --no-trunc deskboard-api:phase3d >"$audit_directory/api-history.txt"
  docker history --no-trunc deskboard-private-proxy:phase3d >"$audit_directory/proxy-history.txt"
  if grep -F -f "$secret_file" \
    "$audit_directory/compose.txt" \
    "$audit_directory/logs.txt" \
    "$audit_directory/inspect.json" \
    "$audit_directory/api-history.txt" \
    "$audit_directory/proxy-history.txt" >/dev/null; then
    return 1
  fi

)

configure_private_serve() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] || return 1
  local help output status consent_url
  help="$(tailscale serve --help 2>&1)" || return 1
  [[ "$help" == *"--bg"* ]] || return 1

  set +e
  output="$(tailscale serve --bg "http://127.0.0.1:$port" 2>&1)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf '%s\n' "ok"
    return 0
  fi

  consent_url="$(printf '%s\n' "$output" \
    | grep -Eo 'https://login\.tailscale\.com/[^[:space:]]+' \
    | head -n 1 || true)"
  if [[ -n "$consent_url" ]]; then
    printf 'consent\t%s\n' "$consent_url"
    return 2
  fi
  printf '%s\n' "error"
  return 1
}

tailscale_status_json() {
  tailscale status --json
}

main() {
  local operation="${1:-}"
  shift || true
  case "$operation" in
    discover)
      [[ "$#" -eq 0 ]]
      discover_dockge_stacks_directory
      ;;
    prepare-stage)
      [[ "$#" -eq 1 ]]
      prepare_stage "$1"
      ;;
    discard-stage)
      [[ "$#" -eq 1 ]]
      discard_stage "$1"
      ;;
    install-stage)
      [[ "$#" -eq 2 ]]
      install_stage "$1" "$2"
      ;;
    write-secret)
      [[ "$#" -eq 1 ]]
      write_secret "$1"
      ;;
    write-runtime)
      [[ "$#" -eq 1 ]]
      write_runtime_configuration "$1"
      ;;
    compose-up)
      [[ "$#" -eq 1 ]]
      compose_up "$1"
      ;;
    serve)
      [[ "$#" -eq 1 ]]
      configure_private_serve "$1"
      ;;
    tailscale-status)
      [[ "$#" -eq 0 ]]
      tailscale_status_json
      ;;
    *)
      return 1
      ;;
  esac
}

if [[ "${DESKBOARD_REMOTE_BOOTSTRAP_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
