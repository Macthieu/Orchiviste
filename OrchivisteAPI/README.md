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
- important : l'aperçu est une image JPG (sélection de texte impossible directement dans la page).  
  Le texte OCR est disponible via `GET /v1/preview/{id}/text`, et les PDF routés peuvent être régénérés en PDF sélectionnable.
- téléchargement PDF OCR explicite : `GET /v1/jobs/{id}/download/searchable` (bouton dans la page tâche `/ui/jobs/{id}`)

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
- contournement blocage `docker-credential-desktop` : `./scripts/dev_up.sh --anon-auth`
- rebuild ciblé plus rapide : `docker compose build api` (ou `analyse`, `worker`)
- préflight local (mode rapide/complet) : `./scripts/preflight_local.sh --quick` ou `./scripts/preflight_local.sh --full`
- validation release en une commande : `./scripts/validate_release.sh`
- validation release + contournement auth Docker : `./scripts/validate_release.sh --anon-auth`
- arrêt propre : `./scripts/dev_down.sh`
- statut : `docker compose ps`
- logs API : `docker compose logs -f api`

Tests fumée MVP :
- `docker compose up -d`
- `./scripts/smoke_mvp.sh`
- surcharge optionnelle : `ORCHIVISTE_API_BASE=http://127.0.0.1:28780 ./scripts/smoke_mvp.sh`
- test webhook HMAC bout en bout : `./scripts/smoke_webhook_hmac.sh`
- contrôle OpenAPI MVP (endpoints + webhook) : `./scripts/check_openapi_mvp.sh`
- exécution groupée recommandée : `./scripts/preflight_local.sh --full`
- alias de compatibilité : `./scripts/validate_release.sh`

Tests de renommage PDF (local -> routage) :
- fichier unique : `./scripts/test_pdf_rename.sh "/chemin/vers/fichier.pdf"`
- lot de fichiers ou dossier : `./scripts/test_pdf_rename_batch.sh "/chemin/dossier-ou-fichier"`
- rapport CSV batch (optionnel) : `ORCHIVISTE_BATCH_REPORT=/tmp/rename-report.csv ./scripts/test_pdf_rename_batch.sh "/chemin/dossier"`
- surcharge dossier/nom à la volée : `ORCHIVISTE_ROUTE_DESTINATION_FOLDER='Archives/{year}/{class_code}/{type_doc}/{sujet}' ORCHIVISTE_ROUTE_NAME_FORMAT='{class_code}-{type_doc}-{sujet}-{date}-{numero}' ./scripts/test_pdf_rename.sh "/chemin/fichier.pdf"`
- règles automatiques par type/sujet :
  - formulaire guidé UI : `http://127.0.0.1:28780/ui/presets` section **Ajouter une règle type/sujet**
  - mode JSON avancé : section **Règles automatiques type/sujet (JSON)** (`configs/analysis/routing/local.rules.json`)
  - en Docker, ces fichiers sont persistés sur l'hôte via le montage `./OrchivisteAPI/configs:/app/OrchivisteAPI/configs`
- chemin des PDF traités (hôte) : `${ORCHIVISTE_ROUTED_EXPORT_DIR:-./runtime/routed}`
- récupération des anciens PDF stockés dans le volume Docker : `./scripts/recover_routed_from_volume.sh`
- lister les derniers fichiers réellement routés (côté hôte) : `./scripts/show_routed_files.sh 50`
- les scripts `test_pdf_rename*.sh` fonctionnent depuis n'importe quel dossier (pas besoin d'être à la racine)

Dépannage Docker :
- en cas de blocage sur `error getting credentials` ou `docker-credential-desktop get`, exécuter : `ORCHIVISTE_DOCKER_ANON_AUTH=1 ./scripts/dev_up.sh --build`
- ce mode force une authentification registre anonyme temporaire uniquement pour l'exécution du script

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
- fournisseur Coginov (optionnel) :
  - `ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_ENABLED` (`0`/`1`)
  - `ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_URL`
  - `ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_TOKEN`
  - `ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_TIMEOUT_MS`
  - `ORCHIVISTE_ANALYSE_PROVIDER_COGINOV_MODEL`
- OCR fallback (API) :
  - `ORCHIVISTE_OCR_ENABLED` (`1` par défaut)
  - `ORCHIVISTE_OCR_LANG` (`fra+eng` par défaut)
  - `ORCHIVISTE_OCR_MAX_PAGES` (`12` par défaut)
  - `ORCHIVISTE_OCR_DPI` (`220` par défaut)
  - `ORCHIVISTE_OCR_MIN_TEXT_CHARS` (`140` par défaut; sous ce seuil, OCR tenté)
- OCR PDF sélectionnable au routage local :
  - `ORCHIVISTE_ROUTE_OCR_SEARCHABLE_PDF` (`1` par défaut)
  - `ORCHIVISTE_ROUTE_OCR_LANG` (hérite de `ORCHIVISTE_OCR_LANG` par défaut)
  - `ORCHIVISTE_ROUTE_OCR_MAX_PAGES` (hérite de `ORCHIVISTE_OCR_MAX_PAGES`)
  - `ORCHIVISTE_ROUTE_OCR_DPI` (hérite de `ORCHIVISTE_OCR_DPI`)
  - `ORCHIVISTE_ROUTE_OCR_MIN_TEXT_CHARS` (hérite de `ORCHIVISTE_OCR_MIN_TEXT_CHARS`)

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
