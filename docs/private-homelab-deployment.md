# Private homelab deployment and manual remote Board

Phase 3D deploys the accepted manual read path without changing Apple source authority, contracts, Bridge identity, revisions, pending envelope bytes, freshness rules, `BoardSnapshot` v1, or web-client behavior. Real homelab, retry, iPad, and Steam Deck acceptance remain review gates until the owner completes them privately.

## 1. Prerequisites

Before running the bootstrap, all of the following must already be true:

- the Mac checkout is on `feat/private-homelab-manual-board`, clean, and contains the commits to deploy;
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

The command verifies the branch and clean worktree, packages only tracked `HEAD` bytes, uploads them through SSH, safely replaces tracked stack files, preserves `.deskboard-private` and the named SQLite volume, and builds or recreates only what the tracked stack and token rotation require.

It generates a new token locally, streams it over SSH standard input into an owner-only API secret file, starts the root Compose stack, waits for content-free health, configures private Tailscale Serve for `http://127.0.0.1:8080`, obtains the `.ts.net` origin without printing it, and asks the signed Bridge process to import a strict one-time request. The request carries only `schemaVersion`, the approved Core origin, and the new token. After success the request is removed with one filesystem operation and the Bridge writes a separate content-free owner-only receipt.

Rerunning the same command updates tracked files, rotates the one token in Core and the Bridge, retains the same Compose project and SQLite volume, preserves all Bridge operational state, and reapplies the same private Serve mapping without creating another mapping. No deployment step is performed through a web UI.

## 3. Normal OS or Tailscale consent

The installed Tailscale CLI may require one-time HTTPS Serve consent. If it does, the bootstrap privately opens the consent page and stops with one action: approve that page, then rerun the same bootstrap command.

The OS may also present its normal signed-application or Keychain authorization prompt when the Bridge updates its own credential. Approve only the identified installed Bridge. Do not browse, copy, reveal, or manually replace any Keychain value.

All other failures are content-free and fail closed. Preserve the stack, secret files, Bridge state, request, and pending envelopes, correct the stated prerequisite, and rerun the same command.

## 4. Explicit Sync Now

After the bootstrap reports success, use the signed Bridge's existing **Sync Now** action. There is no timer, daemon, watcher, launch item, notification, or background retry.

Owner-only remote proof must confirm, without exposing real content or identifiers:

1. source and status deliveries apply or return `unchangedDuplicate` at the private origin;
2. one controlled Apple-side change produces a newer accepted revision;
3. uncertain transport preserves exact pending source and status bytes;
4. restored reachability plus explicit **Sync Now** retries those byte-equivalent bytes without rereading Apple under the uncertain revision;
5. Calendar and Reminders freshness remain truthful.

The bootstrap itself does not press **Sync Now** and does not perform this acceptance.

## 5. iPad and Steam Deck private acceptance

Load the same private `/board` origin on the iPad and Steam Deck only after remote Sync Now proof. The owner may inspect the real Board privately. Do not provide screenshots, accessibility output, OCR, DOM dumps, API bodies, mirror rows, pending bytes, or remote-debug output to an agent.

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

## 6. Rollback changes only the destination

Rollback the Bridge by changing only `coreOrigin` to the previously accepted explicit numeric-loopback HTTP origin. Do not change or reset the bearer credential, Bridge identity, Calendar or Reminder selections, TCC grants, source revisions, status revision, history, or pending source/status envelopes.

Pending envelopes contain neither destination nor token and remain byte-equivalent. Use explicit **Sync Now** only when the owner already knows that the rollback Core accepts the currently rotated credential; this continuity rollback does not retrieve, copy, or replace a token. The private stack, Serve configuration, and SQLite volume may remain intact for investigation; deleting them is not part of rollback.

## Security, persistence, and deferred work

The root [`compose.yaml`](../compose.yaml) is the single production stack. The API is internal-only, the proxy binds only `127.0.0.1:8080`, and `deskboard-data` persists SQLite outside image layers and tracked stack replacement. Never use `docker compose down --volumes` as a Phase 3D operating action.

Proxy and application logs remain content-free. Never publish a token, origin, hostname, tailnet, Compose expansion, database, Board body, source identity, pending envelope, screenshot, or receipt path/content beyond the fixed synthetic fixtures.

Background synchronization, automatic retry, health notifications, backup/restore automation, restore drills, soak, public ingress, source administration, Board changes, and every Apple write remain deferred to later accepted phases.
