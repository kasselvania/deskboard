#!/usr/bin/env bash
set -euo pipefail

readonly proxy_port="8080"
readonly bridge_bundle_identifier="com.kasselvania.deskboard.AppleBridge"
readonly bridge_application_name="DeskboardAppleBridge.app"
readonly bridge_support_name="DeskboardAppleBridge"
readonly bridge_provisioning_schema_version="1"
readonly bridge_info_plist_path="native/apple-bridge/DeskboardAppleBridge/Info.plist"
readonly provisioning_request_name="bootstrap-provisioning-request-v1.json"
readonly provisioning_receipt_name="bootstrap-provisioning-receipt-v1.json"

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "$script_directory/.." && pwd)"
remote_helper="$script_directory/bootstrap-remote.sh"
local_temporary_directory=""
remote_stage_directory=""
ssh_alias=""

fixed_failure() {
  printf '%s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [[ -n "$remote_stage_directory" && -n "$ssh_alias" ]]; then
    run_embedded_remote_helper discard-stage "$remote_stage_directory" \
      >/dev/null 2>&1 || true
    remote_stage_directory=""
  fi
  if [[ -n "$local_temporary_directory" && -d "$local_temporary_directory" ]]; then
    case "$local_temporary_directory" in
      "${TMPDIR:-/tmp}"/deskboard-bootstrap.*)
        rm -rf "$local_temporary_directory"
        ;;
    esac
  fi
}

cleanup_on_exit() {
  local exit_status=$?
  trap - EXIT
  cleanup
  exit "$exit_status"
}
trap cleanup_on_exit EXIT

shell_quote() {
  printf '%q' "$1"
}

remote_helper_command() {
  local installed_helper="$1"
  shift
  local command
  command="bash $(shell_quote "$installed_helper")"
  local argument
  for argument in "$@"; do
    command="$command $(shell_quote "$argument")"
  done
  printf '%s' "$command"
}

run_embedded_remote_helper() {
  local operation="$1"
  shift
  local command="bash -s -- $(shell_quote "$operation")"
  local argument
  for argument in "$@"; do
    command="$command $(shell_quote "$argument")"
  done
  ssh "$ssh_alias" "$command" <"$remote_helper"
}

stream_tracked_archive() {
  local root="$1"
  git -C "$root" archive --format=tar HEAD
}

validate_tracked_revision() {
  local root="$1"
  git -C "$root" rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null \
    || return 1
  [[ -z "$(git -C "$root" status --porcelain=v1 --untracked-files=all)" ]] \
    || return 1
  git -C "$root" diff --quiet --ignore-submodules -- || return 1
  git -C "$root" diff --cached --quiet --ignore-submodules -- || return 1

  local tracked_file object_type
  for tracked_file in \
    compose.yaml \
    deploy/bootstrap-homelab.sh \
    deploy/bootstrap-remote.sh \
    "$bridge_info_plist_path"; do
    object_type="$(git -C "$root" cat-file -t "HEAD:$tracked_file" 2>/dev/null)" \
      || return 1
    [[ "$object_type" == "blob" ]] || return 1
  done

  local schema_version
  schema_version="$(
    git -C "$root" show "HEAD:$bridge_info_plist_path" \
      | /usr/bin/plutil -extract DeskboardBootstrapProvisioningSchemaVersion \
        raw -o - -- - 2>/dev/null
  )" || return 1
  [[ "$schema_version" == "$bridge_provisioning_schema_version" ]] || return 1
  [[ -z "$(git -C "$root" ls-files -- \
    .deskboard-private \
    deploy/.private-origin \
    'deploy/.private-origin.*')" ]] || return 1
}

validate_local_basis() {
  validate_tracked_revision "$repository_root" \
    || fixed_failure "Bootstrap requires a clean tracked HEAD with the production stack and provisioning schema."
}

validate_ssh_alias() {
  [[ "$ssh_alias" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || fixed_failure "Supply one existing SSH configuration alias."
  ssh -o BatchMode=yes -o ConnectTimeout=10 "$ssh_alias" true \
    >"$local_temporary_directory/ssh-preflight.log" 2>&1 \
    || fixed_failure "The supplied SSH alias is not ready for noninteractive use."
}

bridge_state_path() {
  printf '%s' "$HOME/Library/Containers/$bridge_bundle_identifier/Data/Library/Application Support/$bridge_support_name/bridge-state-v1.json"
}

bridge_support_path() {
  printf '%s' "$HOME/Library/Containers/$bridge_bundle_identifier/Data/Library/Application Support/$bridge_support_name"
}

installed_bridge_path() {
  printf '%s' "$HOME/Applications/$bridge_application_name"
}

validate_installed_bridge() {
  local bridge_application info_plist
  bridge_application="$(installed_bridge_path)"
  info_plist="$bridge_application/Contents/Info.plist"
  [[ -d "$bridge_application" && -f "$info_plist" ]] \
    || fixed_failure "The reviewed signed Bridge application is required."
  /usr/bin/codesign --verify --deep --strict "$bridge_application" \
    >"$local_temporary_directory/bridge-signature.log" 2>&1 \
    || fixed_failure "The installed Bridge signature is not valid."
  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - \
    "$info_plist" 2>/dev/null)" == "$bridge_bundle_identifier" ]] \
    || fixed_failure "The installed Bridge identity is not valid."
  [[ "$(/usr/bin/plutil -extract DeskboardBootstrapProvisioningSchemaVersion \
    raw -o - "$info_plist" 2>/dev/null)" == "$bridge_provisioning_schema_version" ]] \
    || fixed_failure "The installed Bridge does not support this bootstrap."
}

read_existing_bridge_id() {
  local state_path="$1"
  [[ -f "$state_path" ]] || fixed_failure "The existing signed Bridge state is required."
  [[ "$(stat -f '%Lp' "$state_path")" == "600" ]] \
    || fixed_failure "The existing Bridge state does not have owner-only permissions."
  local bridge_id
  bridge_id="$(/usr/bin/plutil -extract bridgeId raw -o - "$state_path" 2>/dev/null)" \
    || fixed_failure "The existing Bridge state could not be read safely."
  [[ "$bridge_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] \
    || fixed_failure "The existing Bridge identity is invalid."
  printf '%s' "$bridge_id"
}

read_local_time_zone() {
  local link zone
  link="$(/usr/bin/readlink /etc/localtime 2>/dev/null || true)"
  case "$link" in
    /var/db/timezone/zoneinfo/*)
      zone="${link#/var/db/timezone/zoneinfo/}"
      ;;
    /usr/share/zoneinfo/*)
      zone="${link#/usr/share/zoneinfo/}"
      ;;
    *)
      zone=""
      ;;
  esac
  [[ "$zone" =~ ^[A-Za-z0-9._+-]+(/[A-Za-z0-9._+-]+)+$ ]] \
    || fixed_failure "The Mac time zone could not be resolved to an IANA name."
  printf '%s' "$zone"
}

generate_bearer_token() {
  local token
  token="$(/usr/bin/openssl rand -hex 32 2>/dev/null)" \
    || fixed_failure "A bearer token could not be generated."
  [[ "$token" =~ ^[0-9a-f]{64}$ ]] \
    || fixed_failure "A bearer token could not be generated."
  printf '%s' "$token"
}

validate_ts_hostname() {
  local hostname="$1"
  [[ "$hostname" == *.ts.net ]] || return 1
  [[ "$hostname" != *$'\n'* && "$hostname" != *' '* ]] || return 1
  local old_ifs="$IFS"
  IFS='.'
  local labels=($hostname)
  IFS="$old_ifs"
  [[ "${#labels[@]}" -ge 4 ]] || return 1
  local label
  for label in "${labels[@]}"; do
    [[ ${#label} -ge 1 && ${#label} -le 63 ]] || return 1
    [[ "$label" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || return 1
  done
}

private_origin_health_status() {
  local core_origin="$1"
  {
    printf 'url = "%s/health"\n' "$core_origin"
  } | curl \
    --config - \
    --proto '=https' \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --max-time 15
}

write_private_board_url() {
  local board_url="$1"
  local target_path="$2"
  local origin hostname target_directory temporary_path
  [[ "$board_url" == https://*/board ]] || return 1
  origin="${board_url%/board}"
  hostname="${origin#https://}"
  [[ "$origin" == "https://$hostname" ]] || return 1
  validate_ts_hostname "$hostname" || return 1

  target_directory="$(dirname "$target_path")"
  [[ -d "$target_directory" ]] || return 1
  temporary_path="$(mktemp "$target_directory/.private-origin.XXXXXX")" || return 1
  if ! chmod 0600 "$temporary_path" \
    || ! printf '%s' "$board_url" >"$temporary_path" \
    || ! mv -f "$temporary_path" "$target_path"; then
    rm -f "$temporary_path"
    return 1
  fi
  [[ ! -e "$temporary_path" ]] || return 1
  [[ "$(stat -f '%Lp' "$target_path")" == "600" ]] || return 1
}

write_bridge_provisioning_request() {
  local core_origin="$1"
  local bearer_token="$2"
  local support_directory request_path receipt_path temporary_request
  support_directory="$(bridge_support_path)"
  request_path="$support_directory/$provisioning_request_name"
  receipt_path="$support_directory/$provisioning_receipt_name"
  [[ -d "$support_directory" ]] \
    || fixed_failure "The signed Bridge sandbox state directory is unavailable."
  chmod 0700 "$support_directory"
  rm -f "$receipt_path"
  temporary_request="$(mktemp "$support_directory/.bootstrap-provisioning.XXXXXX")"
  chmod 0600 "$temporary_request"
  {
    printf '%s' '{"schemaVersion":1,"coreOrigin":"'
    printf '%s' "$core_origin"
    printf '%s' '","bearerToken":"'
    printf '%s' "$bearer_token"
    printf '%s' '"}'
  } >"$temporary_request"
  mv -f "$temporary_request" "$request_path"
  [[ "$(stat -f '%Lp' "$request_path")" == "600" ]] \
    || fixed_failure "The Bridge provisioning request is not owner-only."

  local bridge_application
  bridge_application="$(installed_bridge_path)"
  validate_installed_bridge
  /usr/bin/open "$bridge_application" \
    >"$local_temporary_directory/bridge-open.log" 2>&1 \
    || fixed_failure "The signed Bridge could not be launched for provisioning."

  local result=""
  for _ in $(seq 1 60); do
    if [[ -f "$receipt_path" ]]; then
      result="$(/usr/bin/plutil -extract result raw -o - "$receipt_path" 2>/dev/null || true)"
      break
    fi
    sleep 1
  done
  [[ "$result" == "applied" ]] \
    || fixed_failure "The signed Bridge did not accept the provisioning request."
  [[ ! -e "$request_path" ]] \
    || fixed_failure "The signed Bridge did not consume the provisioning request."
  [[ "$(stat -f '%Lp' "$receipt_path")" == "600" ]] \
    || fixed_failure "The Bridge provisioning receipt is not owner-only."
}

main() {
  [[ "$#" -eq 1 ]] || fixed_failure "Usage: ./deploy/bootstrap-homelab.sh <existing-ssh-config-alias>"
  ssh_alias="$1"
  local_temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/deskboard-bootstrap.XXXXXX")"
  chmod 0700 "$local_temporary_directory"

  validate_local_basis
  validate_ssh_alias

  local state_path bridge_id board_time_zone bearer_token
  state_path="$(bridge_state_path)"
  bridge_id="$(read_existing_bridge_id "$state_path")"
  validate_installed_bridge
  board_time_zone="$(read_local_time_zone)"
  bearer_token="$(generate_bearer_token)"

  printf '%s\n' "Clean tracked HEAD, signed Bridge state, and SSH control plane: ready"

  local stacks_directory
  stacks_directory="$(run_embedded_remote_helper discover \
    2>"$local_temporary_directory/dockge-discovery.log")" \
    || fixed_failure "The running Dockge stack directory could not be discovered."
  [[ "$stacks_directory" == /* && "$stacks_directory" != "/" ]] \
    || fixed_failure "The discovered Dockge stack directory is invalid."

  remote_stage_directory="$(run_embedded_remote_helper prepare-stage "$stacks_directory" \
    2>"$local_temporary_directory/stage-preparation.log")" \
    || fixed_failure "The SSH account cannot prepare the Dockge stack directory."
  [[ "$remote_stage_directory" == "$stacks_directory"/.deskboard.bootstrap.* ]] \
    || fixed_failure "The remote staging directory is invalid."

  local quoted_stage
  quoted_stage="$(shell_quote "$remote_stage_directory")"
  if ! stream_tracked_archive "$repository_root" \
    | ssh "$ssh_alias" "tar -xf - -C $quoted_stage" \
      >"$local_temporary_directory/archive-upload.log" 2>&1; then
    fixed_failure "Tracked repository bytes could not be uploaded."
  fi

  local staged_helper="$remote_stage_directory/deploy/bootstrap-remote.sh"
  local install_command
  install_command="$(remote_helper_command \
    "$staged_helper" install-stage "$stacks_directory" "$remote_stage_directory")"
  ssh "$ssh_alias" "$install_command" \
    >"$local_temporary_directory/stack-install.log" 2>&1 \
    || fixed_failure "The tracked Dockge stack files could not be installed."
  remote_stage_directory=""

  local stack_directory="$stacks_directory/deskboard"
  local installed_helper="$stack_directory/deploy/bootstrap-remote.sh"
  local secret_path="$stack_directory/.deskboard-private/apple-bridge-token"
  local runtime_path="$stack_directory/.deskboard-private/runtime.env"
  local secret_command runtime_command
  secret_command="$(remote_helper_command "$installed_helper" write-secret "$secret_path")"
  printf '%s' "$bearer_token" \
    | ssh "$ssh_alias" "$secret_command" \
      >"$local_temporary_directory/secret-write.log" 2>&1 \
    || fixed_failure "The owner-only Core token file could not be rotated."

  runtime_command="$(remote_helper_command "$installed_helper" write-runtime "$runtime_path")"
  {
    printf 'DESKBOARD_APPLE_BRIDGE_ID=%s\n' "$bridge_id"
    printf '%s\n' 'DESKBOARD_APPLE_MIRROR_DATABASE_PATH=/var/lib/deskboard/deskboard.sqlite'
    printf '%s\n' 'DESKBOARD_BOARD_MODE=apple-mirror'
    printf 'DESKBOARD_BOARD_TIME_ZONE=%s\n' "$board_time_zone"
  } | ssh "$ssh_alias" "$runtime_command" \
    >"$local_temporary_directory/runtime-write.log" 2>&1 \
    || fixed_failure "The private Core runtime configuration could not be installed."

  local compose_command
  compose_command="$(remote_helper_command "$installed_helper" compose-up "$stack_directory")"
  ssh "$ssh_alias" "$compose_command" \
    >"$local_temporary_directory/compose-up.log" 2>&1 \
    || fixed_failure "The private Compose stack did not become healthy."
  printf '%s\n' "Tracked stack installed; Core secret rotated; private proxy healthy: yes"

  local serve_command serve_result_file serve_status serve_result consent_url
  serve_command="$(remote_helper_command "$installed_helper" serve "$proxy_port")"
  serve_result_file="$local_temporary_directory/serve-result"
  set +e
  ssh "$ssh_alias" "$serve_command" >"$serve_result_file" \
    2>"$local_temporary_directory/serve-error.log"
  serve_status=$?
  set -e
  serve_result="$(head -n 1 "$serve_result_file" 2>/dev/null || true)"
  if [[ "$serve_status" -ne 0 && "$serve_result" == consent$'\t'* ]]; then
    consent_url="${serve_result#*$'\t'}"
    /usr/bin/open "$consent_url" \
      >"$local_temporary_directory/consent-open.log" 2>&1 || true
    fixed_failure "Approve the opened Tailscale Serve consent page, then rerun the same bootstrap command."
  fi
  [[ "$serve_status" -eq 0 && "$serve_result" == "ok" ]] \
    || fixed_failure "Private Tailscale Serve could not be configured."

  local status_command status_file hostname core_origin
  status_command="$(remote_helper_command "$installed_helper" tailscale-status)"
  status_file="$local_temporary_directory/tailscale-status.json"
  ssh "$ssh_alias" "$status_command" >"$status_file" \
    2>"$local_temporary_directory/tailscale-status-error.log" \
    || fixed_failure "The private Tailscale origin could not be resolved."
  chmod 0600 "$status_file"
  hostname="$(/usr/bin/plutil -extract Self.DNSName raw -o - "$status_file" 2>/dev/null)" \
    || fixed_failure "The private Tailscale origin could not be resolved."
  hostname="${hostname%.}"
  hostname="$(printf '%s' "$hostname" | tr '[:upper:]' '[:lower:]')"
  validate_ts_hostname "$hostname" \
    || fixed_failure "The private Tailscale origin is not an approved .ts.net name."
  core_origin="https://$hostname"
  local remote_health_status
  remote_health_status="$(private_origin_health_status "$core_origin")" \
    || fixed_failure "The private Tailscale origin did not reach the healthy proxy."
  [[ "$remote_health_status" == "200" ]] \
    || fixed_failure "The private Tailscale origin did not reach the healthy proxy."

  local private_origin_path
  private_origin_path="$repository_root/deploy/.private-origin"
  write_private_board_url "$core_origin/board" "$private_origin_path" \
    || fixed_failure "The private Board URL could not be stored locally."
  printf '%s\n' "Private Board URL stored locally: yes"
  if /usr/bin/pbcopy <"$private_origin_path" 2>/dev/null; then
    printf '%s\n' "Private Board URL copied to clipboard: yes"
  else
    printf '%s\n' "Private Board URL copied to clipboard: no"
  fi

  write_bridge_provisioning_request "$core_origin" "$bearer_token"
  bearer_token=""
  core_origin=""
  hostname=""
  printf '%s\n' \
    "Private Serve configured; signed Bridge credential and destination provisioned: yes" \
    "Bootstrap complete. Use explicit Sync Now, then perform private iPad and Steam Deck acceptance."
}

if [[ "${DESKBOARD_BOOTSTRAP_SOURCE_ONLY:-0}" != "1" ]]; then
  main "$@"
fi
