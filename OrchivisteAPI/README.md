# Orchiviste — MVP

SwiftPM + Vapor monorepo containing:
- OrchivisteAPI (server API + SSR Leaf UI)
- OrchivisteAnalyse (separate analysis service)
- OrchivisteWorker (Redis worker CLI)
- OrchivisteSharedKit (shared DTOs)

## Quick start

Prerequisites:
- Swift 5.9+
- Redis (for worker queue) optional for MVP

Build products:
- `cd OrchivisteAPI && swift build -c debug --product OrchivisteAPI`
- `cd OrchivisteAnalyse && swift build -c debug --product OrchivisteAnalyse`
- `cd OrchivisteWorker && swift build -c debug --product OrchivisteWorker`

Run:
- API: `cd OrchivisteAPI && swift run OrchivisteAPI`
- Analyse: `cd OrchivisteAnalyse && swift run OrchivisteAnalyse` (default 127.0.0.1:28781; override `ORCHIVISTE_ANALYSE_PORT`)
- Worker: `cd OrchivisteWorker && ORCHIVISTE_REDIS_URL=redis://127.0.0.1:6379 WORKER_MAX_PARALLEL_PAGES=12 WORKER_TOTAL_PAGES=12 swift run OrchivisteWorker`

UI (SSR Leaf):
- http://127.0.0.1:28780/ui
- alias: http://127.0.0.1:28780/u
- workers: http://127.0.0.1:28780/ui/workers
- presets: http://127.0.0.1:28780/ui/presets
- viewer uses lazy preview (`/v1/preview/...`) and only downloads on explicit button

Docker compose:
- `docker compose up --build`
- API: http://127.0.0.1:28780/u
- Analyse: http://127.0.0.1:28781/v1/analyse
- Redis: `redis://127.0.0.1:6379`
- optional worker profile: `docker compose --profile worker up --build -d`

Smoke test MVP:
- `docker compose up --build -d`
- `./scripts/smoke_mvp.sh`
- optional override: `ORCHIVISTE_API_BASE=http://127.0.0.1:28780 ./scripts/smoke_mvp.sh`
- webhook HMAC end-to-end: `./scripts/smoke_webhook_hmac.sh`

## Environment variables

Database:
- `ORCHIVISTE_DB_PROVIDER` = postgres|sqlite (optional)
- `ORCHIVISTE_POSTGRES_URL` (optional)
- `ORCHIVISTE_SQLITE_PATH` (optional)

API:
- `ORCHIVISTE_API_HOST` (default 127.0.0.1; use 0.0.0.0 in Docker)
- `ORCHIVISTE_API_PORT` (default 28780)

Redis / Dispatcher:
- `ORCHIVISTE_REDIS_URL` (e.g. redis://127.0.0.1:6379)
- `ORCHIVISTE_DISPATCHER_ENABLED` = 1 to enable scheduler (MVP logs only)
- `ORCHIVISTE_DISPATCHER_INTERVAL` seconds (default 5)

Analysis:
- `ORCHIVISTE_ANALYSE_HOST` (default 127.0.0.1; use 0.0.0.0 in Docker)
- `ORCHIVISTE_ANALYSE_URL` (API proxies to this URL if set)
- `ORCHIVISTE_ANALYSE_PORT` (service port, default 28781)

SharePoint Graph routing (optional):
- `ORCHIVISTE_GRAPH_ENABLED` = 1
- `ORCHIVISTE_GRAPH_TENANT_ID`
- `ORCHIVISTE_GRAPH_CLIENT_ID`
- `ORCHIVISTE_GRAPH_CLIENT_SECRET`

Webhooks HMAC:
- `ORCHIVISTE_WEBHOOK_URL` (receiver URL)
- `ORCHIVISTE_WEBHOOK_SECRET` (shared secret)

Configs (optional, read from ./configs):
- Presets: `configs/presets/*.json`
- Taxonomy: `configs/analysis/taxonomy/*.json`
- Routing map: `configs/analysis/routing/routing.map.json`


DAL (hybrid):
- `ORCHIVISTE_DAL_READ` = memory|fluent (default: memory)
- `ORCHIVISTE_DAL_WRITE` = memory|fluent|both (default: both)
- `ORCHIVISTE_AUTO_MIGRATE` = 1 to run migrations at boot (dev convenience)

Examples (dev):
- SQLite (dev) with auto-migrate and hybrid read/write:
