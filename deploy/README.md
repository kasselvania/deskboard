# Private homelab deployment

Phase 3D has one supported production deployment entrypoint:

```bash
./deploy/bootstrap-homelab.sh <existing-ssh-config-alias>
```

Run it from a clean tracked `HEAD` on the Mac that owns the existing signed Bridge state. `HEAD` must commit the root stack, both bootstrap scripts, and Bridge provisioning schema v1; no particular branch name is required. Do not manually recreate its steps.

The bootstrap sends only `git archive HEAD` bytes over the supplied SSH alias. It discovers the running Dockge container's configured stacks bind, uses `/opt/stacks` only when no custom stacks mount is present, and installs the tracked tree as `<stacks-directory>/deskboard`. The root [`compose.yaml`](../compose.yaml) is the sole production stack definition and remains in that directory for a later Dockge scan or view. The command itself uses ordinary `docker compose` over SSH and does not call a Dockge API or require web UI interaction.

The production topology remains:

```text
authenticated tailnet device
          |
 private Tailscale Serve
          |
  127.0.0.1:8080
          |
 loopback-ingress bridge
          |
 private-proxy container ---- production PWA
          |
 internal Compose network
          |
       API container ---- deskboard-data named SQLite volume
```

The API has no host-published port and joins only the internal Compose network. The proxy also joins a dedicated ordinary bridge so Linux Docker Engine can materialize its one numeric-loopback host publication; only the proxy joins that bridge, and its binding remains exactly `127.0.0.1:8080`. Both pinned production images run non-root with read-only root filesystems and use the bounded `unless-stopped` restart policy so Core and Web return after a host reboot. Tailscale Serve is the sole private HTTPS ingress; Funnel and public ingress are absent.

## Private runtime boundary

Each bootstrap run generates one new 256-bit bearer token as exactly 64 lowercase hexadecimal characters. The token is never printed, placed in a process argument, committed, or written to an environment file. It is streamed over SSH standard input into an owner-only remote file and mounted only into the API service at `/run/secrets/apple_bridge_token`. Core reads it through `DESKBOARD_APPLE_BRIDGE_TOKEN_FILE`; that setting and `DESKBOARD_APPLE_BRIDGE_TOKEN` are mutually exclusive.

The ignored `.deskboard-private` directory holds only the remote token file and content-free runtime configuration. The token is absent from Compose output, container environment, image history, logs, and the proxy service. The persistent `deskboard-data` volume is independent of tracked stack replacement and survives reruns.

On the Mac, the bootstrap places one exact-key, owner-only provisioning request in the production Bridge sandbox. The signed Bridge process validates it, updates the Keychain token, changes only `coreOrigin`, consumes the request, and writes a content-free receipt. Bridge identity, source selections, permission behavior, revision streams, delivery history, and exact pending source/status envelope bytes remain unchanged.

After private-origin health succeeds, the bootstrap atomically replaces the ignored `deploy/.private-origin` file at mode `0600` with the full private `/board` URL. It never prints that value and attempts to copy the same file to the Mac clipboard through standard input. Output reports only fixed yes/no handoff statements. The file and its temporary predecessor pattern are excluded from both Git and the Docker build context.

## Synthetic proof

The focused bootstrap proof uses synthetic values and no SSH, Tailscale, Bridge, or homelab state:

```bash
./deploy/test/verify-bootstrap.sh
```

The complete synthetic deployment proof additionally builds and runs the root Compose stack:

```bash
./deploy/verify.sh
```

It verifies the root stack shape, secret-file configuration, proxy allowlist and limits, source/status idempotency, restart/recreate persistence, Phase 3C database reopen, secret-free metadata/output, and graceful shutdown. It removes its synthetic containers, volume, baseline image, and temporary files on exit.

For prerequisites, the one-command owner procedure, normal consent, explicit **Sync Now**, device acceptance, and the explicit rollback authentication limitation, see [the Phase 3D deployment guide](../docs/private-homelab-deployment.md).
