# Orchiviste — MVP

Monorepo SwiftPM + Vapor comprenant :
- `OrchivisteAPI` (API serveur + UI SSR Leaf)
- `OrchivisteAnalyse` (service d'analyse separe)
- `OrchivisteWorker` (CLI worker Redis)
- `OrchivisteSharedKit` (DTO partages)

## Cible d'execution

Le produit vise d'abord une execution native sur macOS.

- `OrchivisteWorker` s'appuie sur des frameworks Apple (`Vision`)
- `OrchivisteAnalyse` peut enrichir l'analyse avec `FoundationModels` et `CoreML` sur macOS
- Docker et les images Linux restent utiles pour la CI, les smoke tests et une demo technique, mais ils n'activent pas les frameworks Apple natifs

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
- téléchargement de l'exemple de preset : `GET /v1/presets/example/download`
- la visionneuse utilise l'aperçu lazy-load (`/v1/preview/...`) et ne télécharge que sur action explicite
- important : l'aperçu est une image JPG (sélection de texte impossible directement dans la page).  
  Le texte OCR est disponible via `GET /v1/preview/{id}/text`, et les PDF routés peuvent être régénérés en PDF sélectionnable.
- téléchargement PDF OCR explicite : `GET /v1/jobs/{id}/download/searchable` (bouton dans la page tâche `/ui/jobs/{id}`)
- apprentissage d'un preset depuis un dossier : `POST /v1/presets/learn`

Docker Compose :
- démarrage standard : `docker compose up -d`
- rebuild forcé : `docker compose up --build -d`
- API : http://127.0.0.1:28780/u
- Analyse : http://127.0.0.1:28781/v1/analyse
- Redis : `redis://127.0.0.1:6379`
- profil worker optionnel : `docker compose --profile worker up --build -d`
- les variables Graph, webhook et PDF/A sont propagées dans le conteneur API via l'environnement Compose

Scripts d'exploitation locale recommandés :
- démarrage robuste (daemon Docker + stack + vérification santé) : `./scripts/dev_up.sh`
- démarrage avec rebuild forcé : `./scripts/dev_up.sh --build`
- fallback builder classique (si BuildKit instable) : `./scripts/dev_up.sh --build --classic-builder`
- contournement blocage `docker-credential-desktop` : `./scripts/dev_up.sh --anon-auth`
- timeout ping daemon Docker : `ORCHIVISTE_DOCKER_INFO_TIMEOUT=8 ./scripts/dev_up.sh`
- rebuild ciblé plus rapide : `docker compose build api` (ou `analyse`, `worker`)
- préflight local (mode rapide/complet) : `./scripts/preflight_local.sh --quick` ou `./scripts/preflight_local.sh --full`
- validation release en une commande : `./scripts/validate_release.sh`
- validation release + contournement auth Docker : `./scripts/validate_release.sh --anon-auth`
- démarrage Mac mini (wrapper env + health checks) : `./scripts/macmini_demo_up.sh --build`
- backup Mac mini (SQLite volume + configs + runtime routé) : `./scripts/macmini_backup.sh`
- arrêt propre : `./scripts/dev_down.sh`
- statut : `docker compose ps`
- logs API : `docker compose logs -f api`

Tests fumée MVP :
- `docker compose up -d`
- test capture intelligente Analyse : `./scripts/smoke_analyse_semantic.sh`
- `./scripts/smoke_mvp.sh`
- surcharge optionnelle : `ORCHIVISTE_API_BASE=http://127.0.0.1:28780 ./scripts/smoke_mvp.sh`
- test webhook HMAC bout en bout : `./scripts/smoke_webhook_hmac.sh`
- test Graph SharePoint simulé (cross-drive/cross-site) : `./scripts/smoke_graph_router.sh`
- dataset de régression métier : `./scripts/smoke_regression_dataset.sh`
- contrôle OpenAPI MVP (endpoints + webhook) : `./scripts/check_openapi_mvp.sh`
- exécution groupée recommandée : `./scripts/preflight_local.sh --full`
- alias de compatibilité : `./scripts/validate_release.sh`
- alias OpenAPI racine : `GET /openapi.json` (conserve aussi `GET /v1/openapi.json`)

Support multi-formats MVP :
- PDF : preview image + texte natif, OCR fallback si necessaire
- Word / Excel / PowerPoint (`.doc`, `.docx`, `.xlsx`, `.pptx`) : extraction texte Office avec conversion preview PDF via `soffice` (OOXML lu nativement pour `docx/xlsx/pptx`)
- Images (`.png`, `.jpg`, `.jpeg`, `.tif`, `.tiff`) : OCR direct + preview image/placeholder selon la plateforme
- l'ingestion UI locale et par dossier accepte maintenant ces formats

Preset JSON riche :
- lecture/ecriture compatible avec l'ancien format `id/name/name_format/class_code/postprocess`
- support du format enrichi (`preset_id`, `detect`, `extract`, `naming`, `classification`, `export`, `review`)
- exemple modifiable sur disque : `OrchivisteAPI/configs/presets/example-resolution.json`
- recuperation d'un preset : `GET /v1/presets/{id}`
- apprentissage d'un draft depuis un dossier : `POST /v1/presets/learn`

Fondation règles de nommage / thésaurus :
- règles déclaratives : `OrchivisteAPI/configs/naming/rules/*.json`
- thésaurus de nommage : `OrchivisteAPI/configs/naming/thesaurus/*.json`
- brouillons de règles : `OrchivisteAPI/configs/naming/drafts/rules/*.json`
- brouillons d'import de thésaurus : `OrchivisteAPI/configs/naming/drafts/thesaurus/*.json`
- lister les règles : `GET /v1/naming/rules`
- récupérer une règle : `GET /v1/naming/rules/{id}`
- créer/modifier une règle : `POST /v1/naming/rules`
- valider une règle sur un extrait : `POST /v1/naming/rules/validate`
- apprendre une règle depuis un dossier : `POST /v1/naming/rules/learn`
- alias plus explicite : `POST /v1/naming/folder/learn`
- lister les brouillons : `GET /v1/naming/drafts`
- lister les thésaurus : `GET /v1/naming/thesaurus`
- récupérer un thésaurus : `GET /v1/naming/thesaurus/{id}`
- créer/modifier un thésaurus : `POST /v1/naming/thesaurus`
- prévisualiser un import JSON/YAML : `POST /v1/naming/thesaurus/import/preview`
- confirmer une fusion/remplacement : `POST /v1/naming/thesaurus/import/confirm`

Ajouter une 3e règle :
- copier un JSON de `configs/naming/rules/`
- définir `conditions`, `fields`, `template`, `normalization`, `forbidden_terms`, `validations`
- tester avec `POST /v1/naming/rules/validate`
- enregistrer avec `POST /v1/naming/rules`

Ajouter un nouvel importeur de thésaurus :
- implémenter `ThesaurusImporting` dans `OrchivisteAnalyse/Sources/OrchivisteAnalyseCore/`
- déclarer le format supporté
- enregistrer l'importeur dans `ThesaurusImportService`
- réutiliser le même flux `preview -> confirm`

Analyse semantique / HIL :
- `POST /v1/analyse` renvoie maintenant, en plus du contrat MVP initial, des blocs optionnels `capture` et `review`
- `capture` expose la strategie (`native_text_semantic` / `ocr_semantic_assisted`), les unites detectees, les titres de section et la provenance des champs
- `review` expose `needs_review`, les raisons (`low_confidence`, `multi_document_units`, `missing_required_fields`, etc.) et les champs ambigus/manquants

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
- `ORCHIVISTE_API_QUEUE_CONCURRENCY` (optionnel) : nombre de workers ingest en parallele dans l'API (defaut auto, borné 1..16)

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
  - `ORCHIVISTE_PREVIEW_MAX_PAGES` (`12` par défaut) : limite de pages rendues pour l'aperçu (accélère les gros lots)
  - `ORCHIVISTE_OCR_DPI` (`220` par défaut)
  - `ORCHIVISTE_OCR_MIN_TEXT_CHARS` (`140` par défaut; sous ce seuil, OCR tenté)
- OCR PDF sélectionnable au routage local :
  - `ORCHIVISTE_ROUTE_OCR_SEARCHABLE_PDF` (`1` par défaut)
  - `ORCHIVISTE_ROUTE_OCR_LANG` (hérite de `ORCHIVISTE_OCR_LANG` par défaut)
  - `ORCHIVISTE_ROUTE_OCR_MAX_PAGES` (hérite de `ORCHIVISTE_OCR_MAX_PAGES`)
  - `ORCHIVISTE_ROUTE_OCR_DPI` (hérite de `ORCHIVISTE_OCR_DPI`)
  - `ORCHIVISTE_ROUTE_OCR_MIN_TEXT_CHARS` (hérite de `ORCHIVISTE_OCR_MIN_TEXT_CHARS`)
- conversion Office optionnelle :
  - `ORCHIVISTE_OFFICE_CONVERSION_ENABLED` (`1` par défaut)
  - `ORCHIVISTE_OFFICE_CONVERSION_TIMEOUT_SECONDS` (`45` par défaut) : timeout dur pour `soffice/libreoffice` (évite qu'un `.docx` bloque le worker)
  - `ORCHIVISTE_OFFICE_CONVERSION_CONCURRENCY` (`1` par défaut, borné 1..4) : limite locale de conversions Office simultanées
  - `ORCHIVISTE_OFFICE_ARCHIVE_TIMEOUT_SECONDS` (`10` par défaut) : timeout de lecture archive `docx/xlsx/pptx` (`zipinfo`/`unzip`)
  - installer `soffice` / LibreOffice si vous voulez un preview PDF reel pour `doc/docx/xlsx/pptx`
- export PDF/A :
  - `ORCHIVISTE_EXPORT_PDFA_ENABLED` (`0` par défaut, peut etre active par preset)
  - `ORCHIVISTE_EXPORT_PREFERRED_PDF_FORMAT` (`PDF/A-2b`)
  - `ORCHIVISTE_PDFA_FAILURE_NEEDS_REVIEW` (`0` par défaut; si `1`, un fallback PDF normal force `needs_review`)
  - Ghostscript est requis pour l'export PDF/A (`gs`, installe dans l'image Docker API)
  - override explicite possible au routage : `POST /v1/route/{file_id}` avec `{ "export_type": "pdfa" }`

Routage SharePoint Graph (optionnel) :
- `ORCHIVISTE_GRAPH_ENABLED` = `1`
- `ORCHIVISTE_GRAPH_TENANT_ID`
- `ORCHIVISTE_GRAPH_CLIENT_ID`
- `ORCHIVISTE_GRAPH_CLIENT_SECRET`
- `ORCHIVISTE_GRAPH_BASE_URL` (optionnel, défaut `https://graph.microsoft.com/v1.0`)
- `ORCHIVISTE_GRAPH_AUTH_BASE_URL` (optionnel, défaut `https://login.microsoftonline.com`)
- `ORCHIVISTE_GRAPH_COPY_TIMEOUT_MS` (défaut `20000`)
- `ORCHIVISTE_GRAPH_COPY_POLL_INTERVAL_MS` (défaut `250`)
- `ORCHIVISTE_GRAPH_DELETE_SOURCE_AFTER_COPY` (`1` par défaut, passe à `0` pour un mode copie)
- le routage Graph supporte maintenant le renommage cohérent avec les presets et les déplacements cross-drive/cross-site; un échec de nettoyage de la source force `needs_review`

Webhooks HMAC :
- `ORCHIVISTE_WEBHOOK_URL` (URL recepteur)
- `ORCHIVISTE_WEBHOOK_SECRET` (secret partage)

## Déploiement Mac mini

Les fichiers d'exemple sont dans `deploy/mac-mini/` :
- `deploy/mac-mini/orchiviste.macmini.env.example`
- `deploy/mac-mini/Caddyfile.example`
- `deploy/mac-mini/README.md`

Flux recommandé pour une démo Mac mini :
- copier l'env exemple vers `deploy/mac-mini/orchiviste.macmini.env`
- adapter les secrets et, si requis, les identifiants Graph / webhook
- démarrer avec `./scripts/macmini_demo_up.sh --build`
- sauvegarder régulièrement avec `./scripts/macmini_backup.sh`

Configurations (optionnel, lues depuis `./configs`) :
- Préréglages : `configs/presets/*.json`
- Taxonomie : `configs/analysis/taxonomy/*.json`
- Table de routage : `configs/analysis/routing/routing.map.json`

DAL (hybride) :
- `ORCHIVISTE_DAL_READ` = `memory|fluent` (defaut : `memory`)
- `ORCHIVISTE_DAL_WRITE` = `memory|fluent|both` (defaut : `both`)
- `ORCHIVISTE_AUTO_MIGRATE` = `1` pour executer les migrations au demarrage
