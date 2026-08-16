# DERIV.WTF production site

This directory turns the supplied self-contained design export into the public `deriv.wtf` site.
The design runtime, visual system, interactions, copy and simulations are preserved; the build adds
clean routes, durable metadata, indexing assets, version evidence and a reproducible static release.

## Build and verify

```sh
BUILD_ID=20260816T180000Z pnpm --dir apps/deriv-site build
pnpm --dir apps/deriv-site check
```

Public routes:

- `/` — landing and risk disclosure
- `/root-space/` — lifecycle simulator
- `/mint/` — buyer and settlement demo
- `/holders/` — holder consent demo
- `/protocol/` — trust and transparency console
- `/mobile/` — mobile product preview (excluded from search indexing)

The visible wallet balances, settlement counts and operator states are demonstration data. The
pages retain the upstream `PRE-AUDIT`, `NO MAINNET` and risk-disclosure language. This static site
does not connect to wallets, RPC endpoints, contracts or a database.

## Runtime and security boundary

The upstream export reconstructs its page from self-contained, compressed browser blobs and runs
an inline design runtime. That requires `blob:`, inline scripts/styles and `unsafe-eval` in the CSP.
All network origins remain self-only, framing is denied, forms are disabled and the container has
no credentials or writable application filesystem. Replacing the export runtime with compiled,
external JavaScript is the main remaining step toward a stricter CSP.

The image is pinned to the exact Nginx Alpine digest already cached on the VPS. It runs as the
unprivileged `nginx` user on port 8080, with all Linux capabilities dropped, a read-only root
filesystem, `no-new-privileges`, memory/CPU/PID limits and a health check. The shared Caddy edge is
the only public listener and owns TLS renewal and response hardening.

## Rollback

Each deployment is stored under `/opt/deriv.wtf/releases/<build-id>` and tagged
`deriv-wtf:<build-id>`. The previous release id is recorded in `/opt/deriv.wtf/PREVIOUS_RELEASE`.
Rollback means recreating `deriv-wtf-site` from that image on the `deploy_default` network; the
tenant edge file does not change between releases.

The deployment and rollback entry points are:

```sh
apps/deriv-site/scripts/deploy.sh
ssh root@187.124.169.200 /opt/deriv.wtf/releases/<release>/scripts/rollback-remote.sh
```

Rollout builds the pinned image on the VPS, starts the least-privilege container, waits for its
Docker health check, validates the complete shared Caddy configuration, reloads the edge without
restarting unrelated tenants, and restores the prior image/config automatically on failure.
