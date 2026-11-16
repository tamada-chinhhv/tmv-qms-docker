# tmv-qms-docker — agent notes

**User-facing documentation in this repo (`README.md`, script usage messages on the host) is written in Vietnamese.** Keep `AGENTS.md` and code comments in English.

## Scope

Docker Compose, Nginx edge config, Postgres init roles, backup/deploy scripts. **Not** application code (`../tmv-qms-be`, `../tmv-qms`).

## Constraints

- Do not commit `.env`, TLS private keys, or backup artifacts.
- Production compose uses **pre-built** images (`pull_policy: never` for app images).
- Postgres: `qms_migrator` (migrate/DDL at deploy), `qms_app` (runtime DML).
- Redis: `volatile-lru`, `128mb`, `requirepass`, `appendonly` — not HRM `allkeys-lru`.
- Socket proxy: `proxy_read_timeout 75s`, `limit_conn` 1000/IP + handshake 20r/s burst 300 (NAT); not HRM 86400s.
- Nginx `limit_req` zone `auth` (2r/s) only on `location =` `/api/auth/login` and `/api/auth/change-password`; `/api/auth/session`, refresh, me use `api` zone (plan 4.9, H14).
- **Windows dev**: prefer `scripts/*.ps1`; LF via `.gitattributes` for `*.sh` / compose / nginx. **Do not rely on git executable bit** for container entrypoints — `Dockerfile.backend` runs `chmod 755` on the entrypoint.
- **Postgres init** (`postgres/init/*.sh`): works without `+x` (official image sources non-executable `.sh`).

## Contracts (sibling repos)

| Service | Port | Notes |
|---------|------|--------|
| BE | 3001 | Prefix `/api`; health `/api/health/live`, `/api/health/ready` |
| FE | 3000 | Next `standalone` → `node server.js` |
| Socket.IO | — | Path `/socket.io`, namespace `/realtime`, websocket-only |

Env names: `PUBLIC_ORIGIN`, `MIGRATE_DATABASE_URL`, `STORAGE_DIR=/data/storage`, `JWT_SECRETS`, `COOKIE_SECURE`.

Nginx timeouts/rates follow plan §10.2, §5.3, §10.11 (`nginx/qms.conf`). Postgres role timeouts §10.7 in `postgres/init/01-qms-init.sh`; server params via compose `command`.

## When changing this repo

1. Run `docker compose -f docker-compose.yml config` and dev config with `.env.example`-shaped values.
2. `nginx -t` via `nginx:1.27-alpine` with `--add-host` for upstream names.
3. On Windows: validate new/changed `*.ps1` with `[System.Management.Automation.Language.Parser]::ParseFile`; ensure UTF-8 BOM on `.ps1` for PS 5.1.
4. CRLF check on LF-tracked paths (`*.sh`, `*.conf`, `Dockerfile*`, `*.yml`).
5. Align with workspace plan `qms_subplan_docker.md` (sections 4.1, 4.9, 5.3 of the master QMS plan).
6. Do not weaken rate limits or WS timeouts without explicit product approval.