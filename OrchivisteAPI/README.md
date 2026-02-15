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
- Analyse: `cd OrchivisteAnalyse && swift run OrchivisteAnalyse` (default 127.0.0.1:18081; override `ORCHIVISTE_ANALYSE_PORT`)
- Worker: `cd OrchivisteWorker && ORCHIVISTE_REDIS_URL=redis://127.0.0.1:6379 WORKER_MAX_PARALLEL_PAGES=12 WORKER_TOTAL_PAGES=12 swift run OrchivisteWorker`

UI (SSR Leaf):
- http://127.0.0.1:18080/ui

## Environment variables

Database:
- `ORCHIVISTE_DB_PROVIDER` = postgres|sqlite (optional)
- `ORCHIVISTE_POSTGRES_URL` (optional)
- `ORCHIVISTE_SQLITE_PATH` (optional)

Redis / Dispatcher:
- `ORCHIVISTE_REDIS_URL` (e.g. redis://127.0.0.1:6379)
- `ORCHIVISTE_DISPATCHER_ENABLED` = 1 to enable scheduler (MVP logs only)
- `ORCHIVISTE_DISPATCHER_INTERVAL` seconds (default 5)

Analysis:
- `ORCHIVISTE_ANALYSE_URL` (API proxies to this URL if set)
- `ORCHIVISTE_ANALYSE_PORT` (service port, default 18081)

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
