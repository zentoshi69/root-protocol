# Deploying HoodPups to srv1505584

> **This stack is designed to be impossible to collide with anything already on the box.**
> It publishes **no host ports** and creates **no proxy**. It attaches to the existing edge network
> and adds exactly one new file to the sanctioned tenants directory.

## Why it is safe by construction, not by care

Two properties do the work:

**It binds nothing.** No `ports:` anywhere. Caddy reaches the container by name over the shared edge
network. A stack that publishes no host port cannot produce "address already in use", cannot take
80/443 from the edge, and cannot be affected by another stack's bindings. The entire class of
port-collision failure is removed rather than avoided.

**It writes one new file and edits zero existing ones.** The live edge is the container
`deploy-caddy-1`, whose main Caddyfile belongs to the FINE TRADER repo and is destroyed by their
next `git pull`. The bind-mounted `tenants/` directory is the escape hatch their author built for
exactly this. `deploy/tenants/hoodpups.caddy` is created fresh; the main Caddyfile and every other
tenant file are untouched in every branch of deploy *and* rollback.

## What I could not verify from here

The build environment has no Docker daemon and is not the VPS, so **no identifier in this stack was
proven free by a live command**. `preflight.sh` exists precisely because that proof has to happen on
the box, in the session doing the work. It is read-only and refuses to proceed if anything is off.

Do not skip it.

## Run order

```bash
sudo ./deploy/preflight.sh                    # read-only; must PASS
export EDGE_NET=<value printed by preflight>  # never guess this
export HOODPUPS_DOMAIN=<your domain>

cp deploy/.env.example deploy/.env            # put the RPC URL here — gitignored
sudo ./deploy/deploy.sh
```

`deploy.sh` sequences: preflight → up → prove the edge can reach the app → hostname-collision check
→ write one tenant file → **validate** → reload → curl the new site *and* every existing one.

The validate step is the gate. If it fails, the tenant file is removed and nothing is reloaded, so
the box is left exactly as it was.

## Rollback

```bash
sudo ./deploy/rollback.sh
```

Removes only our tenant file, validates, reloads, stops our containers, then curls the other sites
to confirm they are still up.

## Red flags — stop if you see any of these

| | |
|---|---|
| `docker compose up` says it is **recreating** a container this stack does not define | Name collision. Investigate before continuing. |
| `caddy validate` does not print a valid configuration | Do **not** reload. Usually a duplicate hostname, which invalidates the entire config and downs every site. |
| Anything other than `docker-proxy` owns 80 or 443 | A host proxy was started. It will fight the container. |
| `import tenants/*.caddy` missing from the edge Caddyfile | That is an incident, not a deploy. Stop. |

Never `docker restart deploy-caddy-1` for a config change — that drops every site for the duration.
`reload` is zero-downtime and is what both scripts use.

## Secrets

`deploy/.env` is gitignored and is the only place a real RPC URL or key belongs. CI hard-fails on
committed key material and this repository is public. A credential pasted into a chat, an issue or a
commit should be treated as compromised and rotated.
