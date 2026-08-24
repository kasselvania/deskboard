# Private homelab deployment and manual remote Board

## Purpose and boundary

Phase 3D deploys the accepted manual read path to the existing private Ubuntu/CasaOS homelab. The iPad, Steam Deck, and signed macOS Bridge use one Tailscale HTTPS origin. This deployment does not change Apple source authority, contracts, Bridge identity, revision streams, outbox bytes, freshness, Board composition, `BoardSnapshot` v1, or web-client behavior.

The complete topology is:

```text
signed macOS Bridge / iPad / Steam Deck
                 |
       authenticated Tailscale HTTPS
                 |
        Tailscale Serve on host
                 |
       127.0.0.1:<proxy-port>
                 |
       private-proxy container
          |              |
 production PWA    private Compose network
                         |
                    API container
                         |
              deskboard-data named volume
```

Only the private proxy has a host port, bound to numeric loopback. The API is not host-published. The Compose network is internal. Tailscale Serve is the sole remote ingress; Funnel and public ingress remain absent.

## Build and private runtime configuration

Follow [`deploy/README.md`](../deploy/README.md) to create `deploy/.env`, validate the Compose file without printing its expansion, build clean images, and start the services.

The deployed Core receives exactly these private values at runtime:

```text
DESKBOARD_APPLE_BRIDGE_ID
DESKBOARD_APPLE_BRIDGE_TOKEN
DESKBOARD_APPLE_MIRROR_DATABASE_PATH
DESKBOARD_BOARD_MODE=apple-mirror
DESKBOARD_BOARD_TIME_ZONE=<owner-supplied-IANA-zone>
```

The environment file is ignored, mode `0600`, and local to the owner-controlled host. No value is a build argument or image layer. The API additionally receives the fixed deployment-only listener setting `DESKBOARD_API_HOST=0.0.0.0`; ordinary local use still defaults to `127.0.0.1`. Any other host, malformed port, partial mirror configuration, or invalid time zone fails before listening with a fixed content-free startup message.

The recommended first deployment uses a new empty named volume. Keep the existing Bridge identity, selections, TCC grants, Keychain token, source revisions, and status revisions. A higher current Bridge revision is valid against an empty remote Core because the remote scope has no accepted revision to reset.

## Proxy surface

The proxy serves the built PWA and exactly these API routes:

```text
GET  /health
GET  /v1/board
POST /v1/apple-source-snapshots
POST /v1/apple-bridge-status
```

Direct `/board` navigation and refresh both serve the production index. Hashed assets have a bounded seven-day immutable cache; the Board document and `GET /v1/board` are `no-store`. Source ingestion accepts up to 1 MiB and status ingestion up to 256 KiB, matching the accepted Core limits.

Proxy access logging is disabled. Its error log is discarded, and the API production logger is disabled. The proxy does not forward cookies or client-address headers. It forwards the existing Authorization header only to the two accepted ingestion routes. Unknown routes and upstream failures return fixed content-free errors. Directory listing and arbitrary file access are disabled.

## Tailscale Serve setup

On the homelab host, inspect the locally installed command before changing state:

```bash
tailscale version
tailscale serve --help
```

Use the exact locally documented private HTTPS reverse-proxy form. Its backend must be `http://127.0.0.1:<proxy-port>`. Do not infer syntax from another Tailscale version. Never invoke or enable Funnel. Do not bind Compose to a LAN address, tailnet IP, or `0.0.0.0`, and do not manage certificates manually.

Owner-only verification must establish all of the following without copying host or tailnet details into agent-visible output:

- private HTTPS Serve is configured;
- Funnel is disabled;
- the private origin reaches `/health` and `/board` from an authenticated tailnet device;
- a non-tailnet path cannot reach the service;
- neither the LAN nor tailnet interface reaches the API port directly;
- the only host-published container endpoint is the proxy on `127.0.0.1`.

Store the approved URL in `deploy/.private-origin`, mode `0600`. That file is ignored by Git and Docker build context.

## Bridge origin update

The Bridge accepts two origin classes only:

- existing numeric-loopback HTTP with an explicit port; or
- HTTPS at the default port with a strict ASCII `.ts.net` hostname.

It rejects paths other than the root origin form, user information, queries, fragments, non-default ports, redirects, remote HTTP, `localhost`, raw LAN or tailnet IPs, arbitrary public/DNS hosts, malformed labels, and internationalized lookalike suffixes. System TLS validation remains unchanged. The Bridge itself appends only `/v1/apple-source-snapshots` and `/v1/apple-bridge-status`.

Before saving the private origin, record only content-free state: permission categories, selected-source counts, acknowledged revisions, pending yes/no, and safe result kinds. After saving it, confirm those values are unchanged. Do not reveal the Bridge ID, token, source identifiers, source names, pending bytes, or origin.

## Manual remote Sync Now and uncertain retry

Phase 3D retains one explicit **Sync Now** action. There is no automatic trigger.

Owner-only acceptance sequence:

1. Confirm the approved private origin is stored and identity, credential, selections, permissions, revisions, and pending state are continuous.
2. Run **Sync Now** and record only masked entity/source ordinals, revision numbers, and `applied` or `unchangedDuplicate` result kinds.
3. Make one controlled Apple-side source change.
4. Run **Sync Now** and confirm a newer remote accepted revision.
5. Make the homelab origin unreachable after a request may have begun.
6. Confirm exact pending source/status envelopes remain present without inspecting or printing their bytes.
7. Relaunch the Bridge when useful and confirm the same pending revisions remain.
8. Restore reachability and run **Sync Now**.
9. Confirm the pending revisions succeed as byte-equivalent retries without rereading Apple under those uncertain revisions.
10. Confirm Calendar and Reminders freshness remain truthful.

Source and status pending envelopes stay independent. Only `applied` and `unchangedDuplicate` acknowledge them. Changing origin does not encode a destination or token into pending bytes and does not clear attempt or acknowledgement history.

## iPad and Steam Deck acceptance

Both devices must use the same private HTTPS origin. The owner may inspect the real Board privately. Agents must not use screenshots, accessibility inspection, OCR, DOM dumps, API-body inspection, mirror rows, remote debugging, or real-data logs.

Record exactly this content-free report for each device:

```text
Device: iPad | Steam Deck
Private origin reachable: yes/no
Direct /board load: yes/no
/board refresh: yes/no
Board schema valid: yes/no
Board version agreement: yes/no
Vertical overflow: yes/no
Calendar freshness: fresh/stale/unavailable
Reminders freshness: fresh/stale/unavailable
Recognizable: yes/no
Calm: yes/no
No private content shared: yes/no
```

After one controlled manual source update, both devices must agree on the same opaque Board version. Privately exercise stale or unavailable source presentation and the accepted saved/unreachable client behavior. Confirm no public or unauthenticated non-tailnet path reaches the Board.

## Restart, recreation, and migration

The `deskboard-data` named volume is outside image layers and survives ordinary `restart`, `up --force-recreate`, and `down`. Never use `down --volumes` as a normal operation. Core handles termination by closing the shared SQLite mirror/status resource.

`deploy/verify.sh` proves with synthetic data that:

- a new empty deployment accepts higher source and status revisions;
- duplicate delivery remains idempotent;
- restart and container recreation preserve accepted data;
- the current runtime opens a database created by accepted Phase 3C code;
- inaccessible and corrupt database storage fails closed with content-free output;
- no database exists in an image layer.

Do not copy the Mac acceptance database to the homelab through Git or agent-visible tooling. Backup and restore automation are not part of Phase 3D.

## Content-free troubleshooting

Use only health state, exit status, fixed errors, masked ordinals, revision numbers, permission/freshness categories, and result kinds.

- If startup fails, validate the private environment file locally without printing it, confirm its mode is `0600`, and confirm the named volume is writable by the non-root API container.
- If `/health` is unavailable, inspect container health and fixed exit state. Do not enable access logs or dump expanded configuration.
- If the Bridge rejects an origin, remove all paths, query, fragment, credentials, and non-default ports; accept only the owner-approved `.ts.net` HTTPS origin.
- If delivery is uncertain, preserve pending state, restore reachability, and use **Sync Now**. Do not reset identity or revisions and do not delete pending bytes.
- If the Board is stale or unavailable, treat that as truthful operational state. Do not delete mirror data or fabricate freshness.

Never paste a populated environment, Compose expansion, URL, token, database row, pending envelope, Tailscale state, Board body, screenshot, or browser inspection into an issue or PR.

## Rollback to same-Mac loopback

Rollback changes only the approved destination:

1. Using the locally installed Tailscale help, remove or disable the private Serve mapping without enabling Funnel.
2. Stop the homelab Compose services without deleting the named volume.
3. Start the accepted same-Mac mirror-backed Core with its existing private configuration.
4. Save its explicit numeric-loopback HTTP origin in the Bridge.
5. Run **Sync Now**; any existing pending bytes may be sent to the newly approved loopback destination.

Do not reset Bridge identity, Keychain, selections, TCC, revisions, history, or pending state during rollback.

## Secret rotation limitations

Phase 3D has one bearer token and no dual-token grace period. Token rotation is a coordinated manual operation: replace the Keychain value and private Core runtime value, restart Core, then use **Sync Now**. Pending envelope bytes contain neither destination nor token and remain valid, but delivery cannot succeed while the two runtime values disagree.

Bridge identity is not a routine secret-rotation field. Changing it would create a different authenticated authority and revision scope, so Phase 3D does not rotate or reset it.

## Deferred to Phase 3E

The following remain absent: background synchronization, a daemon or launch item, automatic retry, health notifications, backup/restore automation, restore drills, and soak. Public ingress, source administration, Board contract or web-client features, automatic conflict recovery, and every Apple write also remain absent.
