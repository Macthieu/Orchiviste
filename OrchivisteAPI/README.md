# Orchiviste — MVP

Monorepo SwiftPM + Vapor comprenant :
- `OrchivisteAPI` (API serveur + UI SSR Leaf)
- `OrchivisteAnalyse` (service d'analyse separe)
- `OrchivisteWorker` (CLI worker Redis)
- `OrchivisteSharedKit` (DTO partages)

## Demarrage rapide

Prerequis :
- Swift 5.9+
- Redis (optionnel pour le MVP, requis pour la file worker)

Compilation :
- `cd OrchivisteAPI && swift build -c debug --product OrchivisteAPI`
- `cd OrchivisteAnalyse && swift build -c debug --product OrchivisteAnalyse`
- `cd OrchivisteWorker && swift build -c debug --product OrchivisteWorker`

Execution :
- API : `cd OrchivisteAPI && swift run OrchivisteAPI`
- Analyse : `cd OrchivisteAnalyse && swift run OrchivisteAnalyse` (defaut `127.0.0.1:28781`, surcharge via `ORCHIVISTE_ANALYSE_PORT`)
- Worker : `cd OrchivisteWorker && ORCHIVISTE_REDIS_URL=redis://127.0.0.1:6379 WORKER_MAX_PARALLEL_PAGES=12 WORKER_TOTAL_PAGES=12 swift run OrchivisteWorker`

UI (SSR Leaf) :
- http://127.0.0.1:28780/ui
- alias : http://127.0.0.1:28780/u
- agents : http://127.0.0.1:28780/ui/workers
- préréglages : http://127.0.0.1:28780/ui/presets
- la visionneuse utilise l'aperçu lazy-load (`/v1/preview/...`) et ne télécharge que sur action explicite

Docker Compose :
- démarrage standard : `docker compose up -d`
- rebuild forcé : `docker compose up --build -d`
- API : http://127.0.0.1:28780/u
- Analyse : http://127.0.0.1:28781/v1/analyse
- Redis : `redis://127.0.0.1:6379`
- profil worker optionnel : `docker compose --profile worker up --build -d`

Scripts d'exploitation locale recommandés :
- démarrage robuste (daemon Docker + stack + vérification santé) : `./scripts/dev_up.sh`
- démarrage avec rebuild forcé : `./scripts/dev_up.sh --build`
- fallback builder classique (si BuildKit instable) : `./scripts/dev_up.sh --build --classic-builder`
- rebuild ciblé plus rapide : `docker compose build api` (ou `analyse`, `worker`)
- validation release en une commande : `./scripts/validate_release.sh`
- arrêt propre : `./scripts/dev_down.sh`
- statut : `docker compose ps`
- logs API : `docker compose logs -f api`

Tests fumée MVP :
- `docker compose up -d`
- `./scripts/smoke_mvp.sh`
- surcharge optionnelle : `ORCHIVISTE_API_BASE=http://127.0.0.1:28780 ./scripts/smoke_mvp.sh`
- test webhook HMAC bout en bout : `./scripts/smoke_webhook_hmac.sh`
- exécution groupée recommandée : `./scripts/validate_release.sh`

## Variables d'environnement

Base de donnees :
- `ORCHIVISTE_DB_PROVIDER` = `postgres|sqlite` (optionnel)
- `ORCHIVISTE_POSTGRES_URL` (optionnel)
- `ORCHIVISTE_SQLITE_PATH` (optionnel)

API :
- `ORCHIVISTE_API_HOST` (defaut `127.0.0.1`, utiliser `0.0.0.0` en Docker)
- `ORCHIVISTE_API_PORT` (defaut `28780`)

Redis / ordonnanceur :
- `ORCHIVISTE_REDIS_URL` (ex. `redis://127.0.0.1:6379`)
- `ORCHIVISTE_DISPATCHER_ENABLED` = `1` pour activer l'ordonnanceur (MVP : logs uniquement)
- `ORCHIVISTE_DISPATCHER_INTERVAL` en secondes (defaut `5`)

Analyse :
- `ORCHIVISTE_ANALYSE_HOST` (defaut `127.0.0.1`, utiliser `0.0.0.0` en Docker)
- `ORCHIVISTE_ANALYSE_URL` (URL cible de proxy pour l'API)
- `ORCHIVISTE_ANALYSE_PORT` (defaut `28781`)

Routage SharePoint Graph (optionnel) :
- `ORCHIVISTE_GRAPH_ENABLED` = `1`
- `ORCHIVISTE_GRAPH_TENANT_ID`
- `ORCHIVISTE_GRAPH_CLIENT_ID`
- `ORCHIVISTE_GRAPH_CLIENT_SECRET`

Webhooks HMAC :
- `ORCHIVISTE_WEBHOOK_URL` (URL recepteur)
- `ORCHIVISTE_WEBHOOK_SECRET` (secret partage)

Configurations (optionnel, lues depuis `./configs`) :
- Préréglages : `configs/presets/*.json`
- Taxonomie : `configs/analysis/taxonomy/*.json`
- Table de routage : `configs/analysis/routing/routing.map.json`

DAL (hybride) :
- `ORCHIVISTE_DAL_READ` = `memory|fluent` (defaut : `memory`)
- `ORCHIVISTE_DAL_WRITE` = `memory|fluent|both` (defaut : `both`)
- `ORCHIVISTE_AUTO_MIGRATE` = `1` pour executer les migrations au demarrage
