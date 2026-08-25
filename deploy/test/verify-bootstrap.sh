#!/usr/bin/env bash
set -euo pipefail

proof_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
proof_tmp="$(mktemp -d "${TMPDIR:-/tmp}/deskboard-bootstrap-proof.XXXXXX")"
proof_token="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

cleanup_proof() {
  case "$proof_tmp" in
    "${TMPDIR:-/tmp}"/deskboard-bootstrap-proof.*)
      rm -rf "$proof_tmp"
      ;;
  esac
}

cleanup_proof_on_exit() {
  local exit_status=$?
  trap - EXIT
  cleanup_proof
  exit "$exit_status"
}
trap cleanup_proof_on_exit EXIT

report_proof_failure() {
  local status=$?
  printf 'Deterministic bootstrap synthetic proof failed at line %s.\n' "$1" >&2
  exit "$status"
}
trap 'report_proof_failure "$LINENO"' ERR

export DESKBOARD_BOOTSTRAP_SOURCE_ONLY=1
export DESKBOARD_REMOTE_BOOTSTRAP_SOURCE_ONLY=1
# shellcheck source=../bootstrap-homelab.sh
source "$proof_root/deploy/bootstrap-homelab.sh"
# shellcheck source=../bootstrap-remote.sh
source "$proof_root/deploy/bootstrap-remote.sh"
trap cleanup_proof_on_exit EXIT
trap 'report_proof_failure "$LINENO"' ERR

assert_tracked_archive_only() {
  local repository="$proof_tmp/repository"
  local extracted="$proof_tmp/extracted"
  mkdir -p "$repository" "$extracted"
  git -C "$repository" init --quiet
  git -C "$repository" config user.email synthetic@example.invalid
  git -C "$repository" config user.name "Synthetic Proof"
  printf '%s\n' tracked >"$repository/tracked.txt"
  printf '%s\n' ignored >"$repository/.gitignore"
  printf '%s\n' private-untracked >>"$repository/.gitignore"
  git -C "$repository" add .gitignore tracked.txt
  git -C "$repository" commit --quiet --message synthetic
  printf '%s\n' must-not-upload >"$repository/private-untracked"

  stream_tracked_archive "$repository" >"$proof_tmp/tracked.tar"
  tar -xf "$proof_tmp/tracked.tar" -C "$extracted"
  [[ -f "$extracted/tracked.txt" ]]
  [[ ! -e "$extracted/private-untracked" ]]
  [[ ! -e "$extracted/.git" ]]
}

assert_dockge_discovery_selection() {
  local custom default
  custom="$(
    printf '%s\n' \
      $'bind\t/synthetic/custom-stacks\t/srv/dockge-stacks' \
      $'volume\tsynthetic-data\t/app/data' \
      | select_dockge_stacks_directory /srv/dockge-stacks
  )"
  [[ "$custom" == "/synthetic/custom-stacks" ]]
  default="$(select_dockge_stacks_directory /opt/stacks </dev/null)"
  [[ "$default" == "/opt/stacks" ]]
  ! select_dockge_stacks_directory /srv/custom-stacks </dev/null >/dev/null
  ! printf '%s\n' $'volume\tsynthetic-volume\t/opt/stacks' \
    | select_dockge_stacks_directory /opt/stacks >/dev/null
  ! printf '%s\n' \
    $'bind\t/synthetic/one\t/opt/stacks' \
    $'bind\t/synthetic/two\t/opt/stacks' \
    | select_dockge_stacks_directory /opt/stacks >/dev/null
}

assert_root_compose_is_single_stack() {
  [[ -f "$proof_root/compose.yaml" ]]
  [[ ! -e "$proof_root/deploy/compose.yaml" ]]
  grep -Fq '127.0.0.1:${DESKBOARD_PROXY_BIND_PORT:-8080}:8080' \
    "$proof_root/compose.yaml"
  grep -Fq 'DESKBOARD_APPLE_BRIDGE_TOKEN_FILE: /run/secrets/apple_bridge_token' \
    "$proof_root/compose.yaml"
  [[ "$(grep -c '^    secrets:$' "$proof_root/compose.yaml")" == "1" ]]
  ! sed -n '/private-proxy:/,/^networks:/p' "$proof_root/compose.yaml" \
    | grep -Eq 'apple_bridge_token|DESKBOARD_APPLE_BRIDGE_TOKEN'
}

assert_secret_and_runtime_writers() {
  local stack="$proof_tmp/secret-stack/deskboard"
  local secret="$stack/.deskboard-private/apple-bridge-token"
  local runtime="$stack/.deskboard-private/runtime.env"
  local output="$proof_tmp/secret-writer.output"
  local rotated_token="fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
  mkdir -p "$stack"

  printf '%s\n' "bootstrap proof: secret write"
  printf '%s' "$proof_token" \
    | write_secret "$secret" >"$output" 2>&1
  [[ ! -s "$output" ]]
  [[ "$(wc -c <"$secret" | tr -d ' ')" == "64" ]]
  [[ "$(stat -f '%Lp' "$secret")" == "600" ]]
  [[ "$(cat "$secret")" == "$proof_token" ]]

  printf '%s\n' \
    'DESKBOARD_APPLE_BRIDGE_ID=11111111-2222-3333-4444-555555555555' \
    'DESKBOARD_APPLE_MIRROR_DATABASE_PATH=/var/lib/deskboard/deskboard.sqlite' \
    'DESKBOARD_BOARD_MODE=apple-mirror' \
    'DESKBOARD_BOARD_TIME_ZONE=Etc/UTC' \
    | write_runtime_configuration "$runtime" >"$output" 2>&1
  [[ ! -s "$output" ]]
  [[ "$(stat -f '%Lp' "$runtime")" == "600" ]]
  ! grep -Eq 'TOKEN|SECRET|0123456789abcdef' "$runtime"
  ! grep -Fq "$proof_token" "$output"

  printf '%s' "$rotated_token" \
    | write_secret "$secret" >"$output" 2>&1
  [[ ! -s "$output" ]]
  [[ "$(cat "$secret")" == "$rotated_token" ]]

  printf '%s\n' "bootstrap proof: invalid secret no-op"
  set +e
  printf '%s' "${proof_token}0" | write_secret "$secret" >"$output" 2>&1
  local invalid_status=$?
  set -e
  [[ "$invalid_status" -ne 0 ]]
  [[ "$(cat "$secret")" == "$rotated_token" ]]
  ! grep -Fq "$proof_token" "$output"
  ! grep -Fq "$rotated_token" "$output"
}

make_stage() {
  local stacks="$1"
  local marker="$2"
  local stage
  stage="$(mktemp -d "$stacks/.deskboard.bootstrap.XXXXXX")"
  cp -pR "$proof_root/.dockerignore" "$stage/.dockerignore"
  cp -pR "$proof_root/compose.yaml" "$stage/compose.yaml"
  mkdir -p "$stage/deploy"
  cp -pR "$proof_root/deploy/bootstrap-remote.sh" \
    "$stage/deploy/bootstrap-remote.sh"
  printf '%s\n' "$marker" >"$stage/tracked-marker"
  printf '%s' "$stage"
}

assert_stack_rerun_idempotency() {
  local stacks="$proof_tmp/stacks"
  local persistent_volume="$proof_tmp/docker-volume"
  local first second
  mkdir -p "$stacks" "$persistent_volume"
  printf '%s\n' persistent >"$persistent_volume/database-marker"

  first="$(make_stage "$stacks" first)"
  printf '%s\n' old >"$first/removed-on-update"
  install_stage "$stacks" "$first"
  mkdir -p "$stacks/deskboard/.deskboard-private"
  printf '%s' "$proof_token" \
    >"$stacks/deskboard/.deskboard-private/apple-bridge-token"
  chmod 0600 "$stacks/deskboard/.deskboard-private/apple-bridge-token"

  second="$(make_stage "$stacks" second)"
  install_stage "$stacks" "$second"
  [[ "$(cat "$stacks/deskboard/tracked-marker")" == "second" ]]
  [[ ! -e "$stacks/deskboard/removed-on-update" ]]
  [[ "$(cat "$stacks/deskboard/.deskboard-private/apple-bridge-token")" == "$proof_token" ]]
  [[ "$(cat "$persistent_volume/database-marker")" == "persistent" ]]
  [[ "$(find "$stacks" -maxdepth 1 -name '.deskboard.previous.*' | wc -l | tr -d ' ')" == "0" ]]
}

assert_private_serve_command() {
  local fake_bin="$proof_tmp/fake-bin"
  local mapping="$proof_tmp/serve-mapping"
  local calls="$proof_tmp/tailscale-calls"
  mkdir -p "$fake_bin"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf '%s\n' 'printf "%s\\n" "$*" >>"$DESKBOARD_FAKE_TAILSCALE_CALLS"'
    printf '%s\n' 'if [[ "$1" == "serve" && "${2:-}" == "--help" ]]; then printf "%s\\n" "--bg"; exit 0; fi'
    printf '%s\n' 'if [[ "$1" == "serve" && "$2" == "--bg" && "$#" -eq 3 ]]; then'
    printf '%s\n' '  if [[ "${DESKBOARD_FAKE_TAILSCALE_CONSENT:-0}" == "1" ]]; then printf "%s\\n" "To enable, visit: https://login.tailscale.com/synthetic-consent" >&2; exit 1; fi'
    printf '%s\n' '  printf "%s\\n" "$3" >"$DESKBOARD_FAKE_TAILSCALE_MAPPING"; exit 0'
    printf '%s\n' 'fi'
    printf '%s\n' 'exit 1'
  } >"$fake_bin/tailscale"
  chmod 0700 "$fake_bin/tailscale"
  export DESKBOARD_FAKE_TAILSCALE_CALLS="$calls"
  export DESKBOARD_FAKE_TAILSCALE_MAPPING="$mapping"

  [[ "$(PATH="$fake_bin:$PATH" configure_private_serve 8080)" == "ok" ]]
  [[ "$(PATH="$fake_bin:$PATH" configure_private_serve 8080)" == "ok" ]]
  [[ "$(cat "$mapping")" == "http://127.0.0.1:8080" ]]
  [[ "$(grep -Fc 'serve --bg http://127.0.0.1:8080' "$calls")" == "2" ]]
  local consent_output consent_status
  set +e
  consent_output="$(
    DESKBOARD_FAKE_TAILSCALE_CONSENT=1 \
      PATH="$fake_bin:$PATH" configure_private_serve 8080
  )"
  consent_status=$?
  set -e
  [[ "$consent_status" == "2" ]]
  [[ "$consent_output" == $'consent\thttps://login.tailscale.com/synthetic-consent' ]]
  ! grep -Eqi '(^|[[:space:]])funnel([[:space:]]|$)' "$calls"
  ! rg -n 'tailscale[[:space:]]+funnel' \
    "$proof_root/deploy/bootstrap-homelab.sh" \
    "$proof_root/deploy/bootstrap-remote.sh" >/dev/null
}

assert_bootstrap_secret_is_not_an_argument() {
  ! rg -n 'ssh[^\n]*\$bearer_token|--env[^\n]*(TOKEN|token)|write-secret[^\n]*bearer_token' \
    "$proof_root/deploy/bootstrap-homelab.sh" \
    "$proof_root/deploy/bootstrap-remote.sh" >/dev/null
  grep -Fq 'git -C "$root" archive --format=tar HEAD' \
    "$proof_root/deploy/bootstrap-homelab.sh"
}

printf '%s\n' "bootstrap proof: tracked archive"
assert_tracked_archive_only
printf '%s\n' "bootstrap proof: Dockge discovery"
assert_dockge_discovery_selection
printf '%s\n' "bootstrap proof: root Compose"
assert_root_compose_is_single_stack
printf '%s\n' "bootstrap proof: secret writers"
assert_secret_and_runtime_writers
printf '%s\n' "bootstrap proof: rerun idempotency"
assert_stack_rerun_idempotency
printf '%s\n' "bootstrap proof: private Serve"
assert_private_serve_command
printf '%s\n' "bootstrap proof: argument privacy"
assert_bootstrap_secret_is_not_an_argument

printf '%s\n' "Deterministic bootstrap synthetic proof: PASS"
