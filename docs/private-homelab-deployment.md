# Private homelab deployment and manual remote Board

Phase 3D deploys the accepted manual read path without changing Apple source authority, contracts, Bridge identity, revisions, pending envelope bytes, freshness rules, `BoardSnapshot` v1, or web-client behavior. Real homelab, retry, iPad, and Steam Deck acceptance remain review gates until the owner completes them privately.

## 1. Prerequisites

Before running the bootstrap, all of the following must already be true:

- the Mac checkout has a clean tracked `HEAD` that commits the root stack, both bootstrap scripts, and Bridge provisioning schema v1; no particular branch name is required;
- the reviewed production Bridge build containing provisioning schema v1 is signed with the existing authority and installed at `~/Applications/DeskboardAppleBridge.app`, with its valid state, Keychain item, source selections, TCC grants, revisions, history, and pending envelopes intact;
- the argument names one existing SSH configuration alias that connects noninteractively to the homelab account;
- that remote account has UID 1000, can use Docker without a password prompt, and can write the running Dockge container's stacks bind;
- Docker Compose and the authenticated Tailscale CLI are already installed on the host;
- the Mac and intended devices are authenticated members of the same tailnet.

Do not reset or export Bridge state. Do not retrieve the old token. Do not create a GitHub credential, clone, private `.env`, certificate, public ingress, second proxy, or second authentication system on the host.

The bootstrap discovers the configured Dockge stacks directory from the running container. If no custom stacks mount exists, the supported fallback is `/opt/stacks`. It leaves the tracked root `compose.yaml` and its build context at `<stacks-directory>/deskboard`, while using ordinary Docker Compose commands through SSH.

## 2. One bootstrap command

From the repository root on the Mac, run exactly:

```bash
./deploy/bootstrap-homelab.sh <existing-ssh-config-alias>
```

The command verifies a valid clean tracked `HEAD` and the required committed deployment/schema files, packages only `git archive HEAD` bytes, uploads them through SSH, safely replaces tracked stack files, preserves `.deskboard-private` and the named SQLite volume, and builds or recreates only what the tracked stack and token rotation require.

It generates a new token locally, streams it over SSH standard input into an owner-only API secret file, starts the root Compose stack, waits for content-free health, configures private Tailscale Serve for `http://127.0.0.1:18080`, obtains the `.ts.net` origin without printing it, and asks the signed Bridge process to import a strict one-time request. The request carries only `schemaVersion`, the approved Core origin, and the new token. After success the request is removed with one filesystem operation and the Bridge writes a separate content-free owner-only receipt. Core and Web both use `restart: unless-stopped`; this restores only the containers after a host reboot and does not initiate a Bridge sync.

After the private origin is healthy, the command atomically replaces `deploy/.private-origin` with the full private `/board` URL at mode `0600`, then attempts to copy that file to the Mac clipboard through standard input. It never prints the URL, hostname, or tailnet. The fixed completion output states whether local storage and clipboard copy succeeded, and no temporary predecessor remains after a successful replacement.

Rerunning the same command updates tracked files, rotates the one token in Core and the Bridge, retains the same Compose project and SQLite volume, preserves all Bridge operational state, and reapplies the same private Serve mapping without creating another mapping. No deployment step is performed through a web UI.

## 3. Normal OS or Tailscale consent

The installed Tailscale CLI may require one-time HTTPS Serve consent. If it does, the bootstrap privately opens the consent page and stops with one action: approve that page, then rerun the same bootstrap command.

The OS may also present its normal signed-application or Keychain authorization prompt when the Bridge updates its own credential. Approve only the identified installed Bridge. Do not browse, copy, reveal, or manually replace any Keychain value.

All other failures are content-free and fail closed. Preserve the stack, secret files, Bridge state, request, and pending envelopes, correct the stated prerequisite, and rerun the same command.

## 4. Phase 3D explicit Sync Now baseline

After the bootstrap reports success, use the signed Bridge's existing **Sync Now** action. There is no timer, daemon, watcher, launch item, notification, or background retry.

Owner-only remote proof must confirm, without exposing real content or identifiers:

1. source and status deliveries apply or return `unchangedDuplicate` at the private origin;
2. one controlled Apple-side change produces a newer accepted revision;
3. uncertain transport preserves exact pending source and status bytes;
4. restored reachability plus explicit **Sync Now** retries those byte-equivalent bytes without rereading Apple under the uncertain revision;
5. Calendar and Reminders freshness remain truthful.

The bootstrap itself does not press **Sync Now** and does not perform this acceptance.

## 4A. Phase 3E unattended overlay

Phase 3E does not change the stack, private origin, proxy, authentication, database, Tailscale Serve mapping, or Board client. After the owner enables **Keep Board Current**, the same signed main Bridge app registers under **Open at Login** and requests scheduled work through the accepted delivery coordinator. Manual **Sync Now** remains available.

There is no shell scheduler, LaunchAgent, helper, daemon, notification, or aggressive retry loop. Sleep and network loss may make the Board stale. Wake or restored connectivity merely permits the next scheduled, wake, or manual opportunity; exact pending bytes remain authoritative until `applied` or `unchangedDuplicate`.

## 5. iPad and Steam Deck private acceptance

Use the full private `/board` URL stored locally at `deploy/.private-origin` for the iPad and Steam Deck, only after remote Sync Now proof. The bootstrap normally leaves the same URL on the Mac clipboard; if clipboard copy reports `no`, the owner may transfer the owner-only local file through a private channel without printing its contents. The owner may inspect the real Board privately. Do not provide the URL, screenshots, accessibility output, OCR, DOM dumps, API bodies, mirror rows, pending bytes, or remote-debug output to an agent.

Record only this content-free result for each device:

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

Both devices must agree on the same opaque Board version after one controlled update. A non-tailnet path must not reach the service, and the API port must remain unreachable directly.

## 6. Same-Mac rollback is not executable in Phase 3D

The bootstrap rotates one matching bearer token into the remote Core and Bridge Keychain. The previous same-Mac Core is not provisioned with that rotated token, so changing `coreOrigin` back to numeric loopback alone does not establish authenticated delivery. Phase 3D therefore has no supported executable same-Mac rollback procedure. Do not retrieve, inspect, copy, or expose a Keychain token, and do not claim a destination-only edit completes rollback.

Changing only destination-related runtime state remains byte-neutral for Bridge ID, Calendar and Reminder selections, TCC permission behavior, acknowledged source/status revisions, attempt/acknowledgement history, and exact pending source/status envelopes, but authentication at another Core remains unresolved. Preserve the private stack, Serve mapping, SQLite volume, and all Bridge state, and stop. A coordinated local fallback is deferred to a later separately reviewed slice; it is not part of the Phase 3D acceptance run.

## Security, persistence, and deferred work

The root [`compose.yaml`](../compose.yaml) is the single production stack. The API joins only the internal Compose network and has no host publication. The proxy joins that internal network plus one ordinary loopback-ingress bridge required for Docker Engine to materialize its sole `127.0.0.1:18080` host binding; no other service joins that bridge or publishes a port. `deskboard-data` persists SQLite outside image layers and tracked stack replacement. Never use `docker compose down --volumes` as a Phase 3D operating action.

Proxy and application logs remain content-free. Never publish a token, origin, hostname, tailnet, Compose expansion, database, Board body, source identity, pending envelope, screenshot, or receipt path/content beyond the fixed synthetic fixtures.

Health notifications, backup/restore automation, restore drills, the longer Phase 3F soak, public ingress, source administration, Board changes, and every Apple write remain deferred. Phase 3E unattended operation is documented in [`unattended-read-only-bridge.md`](unattended-read-only-bridge.md); its 24-hour private acceptance remains a gate.
