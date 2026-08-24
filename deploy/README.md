# Private homelab deployment

This directory contains the Phase 3D production deployment. It runs the existing mirror-backed Core and built PWA behind one loopback-published private proxy. Tailscale Serve terminates private HTTPS on the host and forwards only to that loopback port.

```text
authenticated tailnet device
          |
   Tailscale Serve
          |
  127.0.0.1:<proxy-port>
          |
 private-proxy container ---- production PWA
          |
 internal Compose network
          |
       API container ---- private named SQLite volume
```

The API port is exposed only to the internal Compose network. Neither container provides TLS or public ingress. Tailscale Funnel is forbidden.

## Private configuration

Create the ignored runtime file on the homelab host; never commit or paste it into an issue or PR:

```bash
cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
```

Replace every placeholder in `deploy/.env` with the existing Bridge ID and bearer token, one private database filename, and the owner's IANA Board time zone. Keep these fixed values unchanged:

```text
DESKBOARD_BOARD_MODE=apple-mirror
DESKBOARD_APPLE_MIRROR_DATABASE_PATH=/var/lib/deskboard/<private-database-file>.sqlite
```

The database path must remain inside `/var/lib/deskboard`, which is backed by the private `deskboard-data` named volume. The proxy bind port may be changed, but Compose always binds it to `127.0.0.1`.

## Build and start

From the repository root on the homelab host:

```bash
docker compose --env-file deploy/.env -f deploy/compose.yaml config --quiet
docker compose --env-file deploy/.env -f deploy/compose.yaml build --pull --no-cache
docker compose --env-file deploy/.env -f deploy/compose.yaml up --detach
docker compose --env-file deploy/.env -f deploy/compose.yaml ps
```

Use `docker-compose` in place of `docker compose` only when that is the installed Compose command. Do not print the expanded Compose configuration: it can contain runtime values.

The images use pinned Node 24.19.0 and nginx runtime manifests. Both build stages install the committed dependency graph with `npm ci`; the running services use only production build output. Core and the proxy run as non-root users with read-only root filesystems.

Check the content-free loopback health response privately:

```bash
curl --fail --silent http://127.0.0.1:<proxy-port>/health >/dev/null
```

## Persistence and lifecycle

Normal restart and recreation preserve `deskboard-data`:

```bash
docker compose --env-file deploy/.env -f deploy/compose.yaml restart
docker compose --env-file deploy/.env -f deploy/compose.yaml up --detach --force-recreate
docker compose --env-file deploy/.env -f deploy/compose.yaml down
```

Do not add `--volumes` to `down`. That deletes the private database volume and is not a Phase 3D operating procedure. Backup and restore are deliberately deferred to Phase 3E.

Core handles `SIGTERM` and closes its shared mirror/status resource before exit. An inaccessible or corrupt database causes a fixed startup failure and no listener.

## Tailscale Serve

Do not copy a remembered Tailscale command. On the homelab host, first inspect the installed implementation:

```bash
tailscale version
tailscale serve --help
```

Using only the syntax shown by that local help, configure one private HTTPS Serve origin whose backend is exactly:

```text
http://127.0.0.1:<proxy-port>
```

Use Tailscale Serve, never Funnel. Do not publish the Compose port on a LAN or tailnet address, manually provision a certificate, or add another reverse proxy identity. Privately verify the resulting Serve state and confirm Funnel remains disabled. Store the resulting owner URL only in the ignored `deploy/.private-origin` file with mode `0600`.

## Bridge and manual Sync Now

In the installed signed Bridge, save only the approved origin:

```text
https://<private-device>.<private-tailnet>.ts.net
```

Do not include a path, query, fragment, user information, or non-default port. Saving the destination preserves Bridge identity, Keychain credential, selections, permissions, revisions, attempt history, acknowledgement history, and exact pending source/status envelopes.

Run **Sync Now** explicitly. The Bridge continues to append only the two accepted ingestion paths. There is no timer, daemon, watcher, launch item, or background retry.

For owner-only remote and device acceptance, rollback, and content-free troubleshooting, follow [the full Phase 3D runbook](../docs/private-homelab-deployment.md).

## Synthetic deployment proof

With a local Docker engine and Compose available:

```bash
./deploy/verify.sh
```

The proof uses synthetic values only. It builds clean images, inspects topology and image metadata, exercises the proxy allowlist and body limits, applies higher source/status revisions, verifies idempotency and persistence through restart/recreation, and opens a synthetic database created by the accepted Phase 3C code. It removes its temporary containers, volume, baseline image, and local proof directory on exit.
