#!/usr/bin/env bash
set -euo pipefail

proof_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
proof_tmp="$(mktemp -d "$proof_root/.phase3d-proof.XXXXXX")"
proof_project="deskboardphase3dproof$$"
proof_port="18080"
proof_token="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
proof_bridge="synthetic-deployment-bridge"
proof_env="$proof_tmp/synthetic.env"
proof_api_image="deskboard-api:phase3d"
proof_proxy_image="deskboard-private-proxy:phase3d"
proof_baseline_image="deskboard-api:phase3c-proof"
proof_baseline_commit="8fda01fc8ad83899ec6a8a93f07c21dc85cf588a"
proof_volume="${proof_project}_deskboard-data"
proof_baseline_container="${proof_project}-baseline"
compose=()

cleanup() {
  if [[ ${#compose[@]} -gt 0 ]]; then
    "${compose[@]}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  docker rm --force "$proof_baseline_container" >/dev/null 2>&1 || true
  docker volume rm "$proof_volume" >/dev/null 2>&1 || true
  docker image rm "$proof_baseline_image" >/dev/null 2>&1 || true
  case "$proof_tmp" in
    "$proof_root"/.phase3d-proof.*) rm -rf -- "$proof_tmp" ;;
  esac
}
trap cleanup EXIT

for required in docker curl git node tar; do
  command -v "$required" >/dev/null
done
compose_command=()
if docker compose version >/dev/null 2>&1; then
  compose_command=(docker compose)
elif command -v docker-compose >/dev/null && docker-compose version >/dev/null; then
  compose_command=(docker-compose)
else
  printf '%s\n' "Docker Compose is required." >&2
  exit 1
fi
compose=(
  "${compose_command[@]}"
  --project-name "$proof_project"
  --env-file "$proof_env"
  --file "$proof_root/deploy/compose.yaml"
)
docker info >/dev/null

printf '%s\n' \
  "DESKBOARD_APPLE_BRIDGE_ID=$proof_bridge" \
  "DESKBOARD_APPLE_BRIDGE_TOKEN=$proof_token" \
  "DESKBOARD_APPLE_MIRROR_DATABASE_PATH=/var/lib/deskboard/synthetic.sqlite" \
  "DESKBOARD_BOARD_MODE=apple-mirror" \
  "DESKBOARD_BOARD_TIME_ZONE=Etc/UTC" \
  "DESKBOARD_PROXY_BIND_PORT=$proof_port" \
  >"$proof_env"
chmod 0600 "$proof_env"
chmod 1777 "$proof_tmp"
export DESKBOARD_ENV_FILE="$proof_env"

wait_for_health() {
  local service="$1"
  local container_id
  container_id="$("${compose[@]}" ps --all --quiet "$service")"
  [[ -n "$container_id" ]]
  for _ in $(seq 1 60); do
    if [[ "$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$container_id")" == "healthy" ]]; then
      return 0
    fi
    if [[ "$(docker inspect --format '{{.State.Status}}' "$container_id")" == "exited" ]]; then
      return 1
    fi
    sleep 1
  done
  return 1
}

assert_apply_result() {
  node "$proof_root/deploy/test/assert-apply-result.mjs" "$@"
}

proxy_request() {
  local method="$1"
  local path="$2"
  local response_name="$3"
  local headers_name="$4"
  local body_path="$5"
  local authentication="$6"
  docker run --rm \
    --network "${proof_project}_private" \
    --user 0:0 \
    --env "DESKBOARD_SYNTHETIC_TOKEN=$proof_token" \
    --volume "$proof_root/deploy/test:/proof:ro" \
    --volume "$proof_root/deploy/test-fixtures:/fixtures:ro" \
    --volume "$proof_tmp:/output" \
    "$proof_api_image" \
    node /proof/proxy-request.mjs \
      "$method" \
      "$path" \
      "/output/$response_name" \
      "/output/$headers_name" \
      "$body_path" \
      "$authentication"
}

post_source() {
  local output="$1"
  proxy_request \
    POST \
    /v1/apple-source-snapshots \
    "$(basename "$output")" \
    "$(basename "$output").headers" \
    /fixtures/source-envelope.json \
    authenticated
}

post_status() {
  local output="$1"
  proxy_request \
    POST \
    /v1/apple-bridge-status \
    "$(basename "$output")" \
    "$(basename "$output").headers" \
    /fixtures/status-snapshot.json \
    authenticated
}

assert_runtime_images() {
  [[ "$(docker image inspect --format '{{.Config.User}}' "$proof_api_image")" == "node" ]]
  [[ "$(docker image inspect --format '{{.Config.User}}' "$proof_proxy_image")" == "nginx" ]]

  docker image inspect "$proof_api_image" >"$proof_tmp/api-image.json"
  docker image inspect "$proof_proxy_image" >"$proof_tmp/proxy-image.json"
  docker run --rm --entrypoint cat "$proof_proxy_image" \
    /etc/nginx/nginx.conf >"$proof_tmp/proxy-runtime.conf"
  docker history --no-trunc "$proof_api_image" >"$proof_tmp/api-history.txt"
  docker history --no-trunc "$proof_proxy_image" >"$proof_tmp/proxy-history.txt"
  if grep --fixed-strings --quiet "$proof_token" \
    "$proof_tmp/api-image.json" "$proof_tmp/proxy-image.json" \
    "$proof_tmp/api-history.txt" "$proof_tmp/proxy-history.txt"; then
    return 1
  fi
  if grep --fixed-strings --quiet "$proof_bridge" \
    "$proof_tmp/api-image.json" "$proof_tmp/proxy-image.json" \
    "$proof_tmp/api-history.txt" "$proof_tmp/proxy-history.txt"; then
    return 1
  fi

  docker run --rm --entrypoint sh "$proof_api_image" -c \
    "! find /app /var/lib/deskboard -type f \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \) -print -quit | grep -q ."
  docker run --rm \
    --volume "$proof_root/deploy/test:/proof:ro" \
    "$proof_api_image" \
    node /proof/verify-fixture-mode.mjs

  local api_command proxy_command
  api_command="$(docker image inspect --format '{{json .Config.Cmd}}' "$proof_api_image")"
  proxy_command="$(docker image inspect --format '{{json .Config.Cmd}}' "$proof_proxy_image")"
  [[ "$api_command" == *"apps/api/dist/server.js"* ]]
  [[ "$api_command" != *"vite"* && "$api_command" != *"tsx"* ]]
  [[ "$proxy_command" == *"nginx"* ]]
  [[ "$proxy_command" != *"vite"* ]]
  grep --fixed-strings --quiet "access_log off;" "$proof_tmp/proxy-runtime.conf"
  grep --fixed-strings --quiet "error_log /dev/null" "$proof_tmp/proxy-runtime.conf"
  grep --fixed-strings --quiet "autoindex off;" "$proof_tmp/proxy-runtime.conf"
  grep --fixed-strings --quiet 'proxy_set_header Authorization "";' \
    "$proof_tmp/proxy-runtime.conf"
  [[ "$(grep --fixed-strings --count \
    'proxy_set_header Authorization $http_authorization;' \
    "$proof_tmp/proxy-runtime.conf")" == "2" ]]
  grep --fixed-strings --quiet "proxy_request_buffering off;" \
    "$proof_tmp/proxy-runtime.conf"
  grep --fixed-strings --quiet "proxy_buffering off;" \
    "$proof_tmp/proxy-runtime.conf"
  printf '%s\n' "Production non-root images and secret-free metadata: yes"
}

assert_fail_closed_database_errors() {
  local common_environment=(
    --env "DESKBOARD_APPLE_BRIDGE_ID=$proof_bridge"
    --env "DESKBOARD_APPLE_BRIDGE_TOKEN=$proof_token"
    --env DESKBOARD_BOARD_MODE=apple-mirror
    --env DESKBOARD_BOARD_TIME_ZONE=Etc/UTC
    --env DESKBOARD_API_HOST=0.0.0.0
  )

  set +e
  docker run --rm --read-only \
    "${common_environment[@]}" \
    --env DESKBOARD_APPLE_MIRROR_DATABASE_PATH=/root/inaccessible.sqlite \
    "$proof_api_image" >"$proof_tmp/inaccessible.log" 2>&1
  local inaccessible_status=$?
  set -e
  [[ "$inaccessible_status" -ne 0 ]]
  grep --fixed-strings --quiet "Deskboard API could not start." "$proof_tmp/inaccessible.log"
  ! grep --fixed-strings --quiet "$proof_token" "$proof_tmp/inaccessible.log"
  ! grep --fixed-strings --quiet "$proof_bridge" "$proof_tmp/inaccessible.log"

  install -d -m 0777 "$proof_tmp/corrupt"
  printf '%s' 'synthetic-corrupt-sqlite' >"$proof_tmp/corrupt/synthetic.sqlite"
  chmod 0666 "$proof_tmp/corrupt/synthetic.sqlite"
  set +e
  docker run --rm --read-only \
    "${common_environment[@]}" \
    --env DESKBOARD_APPLE_MIRROR_DATABASE_PATH=/var/lib/deskboard/synthetic.sqlite \
    --volume "$proof_tmp/corrupt:/var/lib/deskboard" \
    "$proof_api_image" >"$proof_tmp/corrupt.log" 2>&1
  local corrupt_status=$?
  set -e
  [[ "$corrupt_status" -ne 0 ]]
  grep --fixed-strings --quiet "Deskboard API could not start." "$proof_tmp/corrupt.log"
  ! grep --fixed-strings --quiet "$proof_token" "$proof_tmp/corrupt.log"
  ! grep --fixed-strings --quiet "$proof_bridge" "$proof_tmp/corrupt.log"
  printf '%s\n' "Inaccessible and corrupt database failure is content-free: yes"
}

assert_runtime_topology() {
  local api_id proxy_id
  api_id="$("${compose[@]}" ps --quiet api)"
  proxy_id="$("${compose[@]}" ps --quiet private-proxy)"
  docker inspect "$api_id" >"$proof_tmp/api-container.json"
  docker inspect "$proxy_id" >"$proof_tmp/proxy-container.json"
  docker network inspect "${proof_project}_private" >"$proof_tmp/private-network.json"
  node --input-type=module - \
    "$proof_tmp/api-container.json" \
    "$proof_tmp/proxy-container.json" \
    "$proof_tmp/private-network.json" \
    "$proof_port" <<'NODE'
import { readFileSync } from "node:fs";

const [, , apiPath, proxyPath, networkPath, expectedPort] = process.argv;
const api = JSON.parse(readFileSync(apiPath, "utf8"))[0];
const proxy = JSON.parse(readFileSync(proxyPath, "utf8"))[0];
const network = JSON.parse(readFileSync(networkPath, "utf8"))[0];
if (Object.keys(api.HostConfig.PortBindings ?? {}).length !== 0) process.exit(1);
const bindings = proxy.HostConfig.PortBindings?.["8080/tcp"];
if (
  !Array.isArray(bindings) ||
  bindings.length !== 1 ||
  bindings[0].HostIp !== "127.0.0.1" ||
  bindings[0].HostPort !== expectedPort
) process.exit(1);
if (!api.HostConfig.ReadonlyRootfs || !proxy.HostConfig.ReadonlyRootfs) process.exit(1);
if (!network.Internal) process.exit(1);
NODE
  [[ "$("${compose[@]}" exec --no-TTY api id -u)" != "0" ]]
  [[ "$("${compose[@]}" exec --no-TTY private-proxy id -u)" != "0" ]]
  [[ "$("${compose[@]}" exec --no-TTY api stat --format '%a:%u' /var/lib/deskboard)" == "700:1000" ]]
  printf '%s\n' "API host exposure: no" "Proxy host bind is loopback only: yes"
}

assert_proxy_surface() {
  local code
  code="$(proxy_request GET /health health.json health.headers - unauthenticated)"
  [[ "$code" == "200" ]]
  node --input-type=module - "$proof_tmp/health.json" <<'NODE'
import { readFileSync } from "node:fs";
const health = JSON.parse(readFileSync(process.argv[2], "utf8"));
if (health.status !== "ok" || health.service !== "deskboard-api") process.exit(1);
NODE

  for pass in first refresh; do
    code="$(proxy_request \
      GET \
      /board \
      "board-$pass.html" \
      "board-$pass.headers" \
      - \
      unauthenticated)"
    [[ "$code" == "200" ]]
    grep --ignore-case --quiet '^Cache-Control: no-store' "$proof_tmp/board-$pass.headers"
  done
  cmp "$proof_tmp/board-first.html" "$proof_tmp/board-refresh.html"

  local asset_path
  asset_path="$(node "$proof_root/deploy/test/find-static-asset.mjs" "$proof_tmp/board-first.html")"
  code="$(proxy_request GET "$asset_path" asset.body asset.headers - unauthenticated)"
  [[ "$code" == "200" ]]
  grep --ignore-case --quiet '^Cache-Control: public, max-age=604800, immutable' "$proof_tmp/asset.headers"

  code="$(proxy_request \
    GET \
    /v1/board \
    board-api.json \
    board-api.headers \
    - \
    unauthenticated)"
  [[ "$code" == "200" ]]
  grep --ignore-case --quiet '^Cache-Control: no-store' "$proof_tmp/board-api.headers"

  docker run --rm \
    --network "${proof_project}_private" \
    --volume "$proof_root/deploy/test:/proof:ro" \
    "$proof_api_image" \
    node /proof/verify-deployed-board.mjs

  for path in / /v1/raw /v1/apple-source-mirror /v1/apple-bridge-status; do
    code="$(proxy_request \
      GET \
      "$path" \
      "route-$RANDOM.body" \
      "route-$RANDOM.headers" \
      - \
      unauthenticated)"
    [[ "$code" == "404" || "$code" == "405" ]]
  done
  code="$(proxy_request \
    POST \
    /v1/board \
    board-post.body \
    board-post.headers \
    - \
    unauthenticated)"
  [[ "$code" == "405" ]]
  printf '%s\n' "Direct Board load, refresh, caching, no-store, and route allowlist: yes"
}

assert_proxy_body_limits() {
  node "$proof_root/deploy/test/make-limit-payloads.mjs" "$proof_tmp"
  local code path route expected
  for specification in \
    "source-at-limit.json:/v1/apple-source-snapshots:400" \
    "source-over-limit.json:/v1/apple-source-snapshots:413" \
    "status-at-limit.json:/v1/apple-bridge-status:400" \
    "status-over-limit.json:/v1/apple-bridge-status:413"; do
    IFS=: read -r path route expected <<<"$specification"
    code="$(proxy_request \
      POST \
      "$route" \
      "$path.response" \
      "$path.headers" \
      "/output/$path" \
      authenticated)"
    [[ "$code" == "$expected" ]]
  done
  printf '%s\n' "Source and status proxy body limits preserve Core limits: yes"
}

assert_initial_and_duplicate_delivery() {
  local code
  code="$(post_source "$proof_tmp/source-first.json")"
  [[ "$code" == "200" ]]
  assert_apply_result "$proof_tmp/source-first.json" applied sourceRevision 42
  code="$(post_source "$proof_tmp/source-duplicate.json")"
  [[ "$code" == "200" ]]
  assert_apply_result "$proof_tmp/source-duplicate.json" unchangedDuplicate sourceRevision 42

  code="$(post_status "$proof_tmp/status-first.json")"
  [[ "$code" == "200" ]]
  assert_apply_result "$proof_tmp/status-first.json" applied statusRevision 57
  code="$(post_status "$proof_tmp/status-duplicate.json")"
  [[ "$code" == "200" ]]
  assert_apply_result "$proof_tmp/status-duplicate.json" unchangedDuplicate statusRevision 57
}

assert_duplicate_delivery() {
  local code
  code="$(post_source "$proof_tmp/source-persisted.json")"
  [[ "$code" == "200" ]]
  assert_apply_result "$proof_tmp/source-persisted.json" unchangedDuplicate sourceRevision 42
  code="$(post_status "$proof_tmp/status-persisted.json")"
  [[ "$code" == "200" ]]
  assert_apply_result "$proof_tmp/status-persisted.json" unchangedDuplicate statusRevision 57
}

assert_restart_and_recreate() {
  local api_id exit_code
  api_id="$("${compose[@]}" ps --quiet api)"
  "${compose[@]}" stop --timeout 15 api
  exit_code="$(docker inspect --format '{{.State.ExitCode}}' "$api_id")"
  [[ "$exit_code" == "0" ]]
  "${compose[@]}" start api
  wait_for_health api
  assert_duplicate_delivery

  "${compose[@]}" up --detach --force-recreate api private-proxy
  wait_for_health api
  wait_for_health private-proxy
  assert_duplicate_delivery
  printf '%s\n' "Graceful stop, restart, and container recreation preserve data: yes"
}

assert_phase3c_migration() {
  "${compose[@]}" down --volumes --remove-orphans
  docker volume create "$proof_volume" >/dev/null
  install -d "$proof_tmp/phase3c"
  git -C "$proof_root" archive "$proof_baseline_commit" | tar -x -C "$proof_tmp/phase3c"
  install -d "$proof_tmp/phase3c/deploy"
  cp "$proof_root/deploy/api.Dockerfile" "$proof_tmp/phase3c/deploy/api.Dockerfile"
  docker build \
    --tag "$proof_baseline_image" \
    --file "$proof_tmp/phase3c/deploy/api.Dockerfile" \
    "$proof_tmp/phase3c"

  docker run --rm \
    --volume "$proof_volume:/var/lib/deskboard" \
    --volume "$proof_root/deploy/test:/proof:ro" \
    --volume "$proof_root/deploy/test-fixtures:/fixtures:ro" \
    "$proof_baseline_image" \
    node /proof/seed-phase3c-database.mjs \
      /var/lib/deskboard/synthetic.sqlite \
      /fixtures/source-envelope.json \
      /fixtures/status-snapshot.json

  "${compose[@]}" up --detach
  wait_for_health api
  wait_for_health private-proxy
  assert_duplicate_delivery
  printf '%s\n' "Synthetic existing Phase 3C database migration/reopen: yes"
}

printf '%s\n' "Building clean production images from the committed lockfile."
"${compose[@]}" build --pull --no-cache
assert_runtime_images
assert_fail_closed_database_errors

"${compose[@]}" up --detach
wait_for_health api
wait_for_health private-proxy
assert_runtime_topology
assert_proxy_surface
assert_proxy_body_limits
assert_initial_and_duplicate_delivery
assert_restart_and_recreate
assert_phase3c_migration

printf '%s\n' "Phase 3D synthetic deployment proof: PASS"
