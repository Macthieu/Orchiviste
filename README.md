# Orchiviste

Monorepo Swift Package Manager + Vapor pour le MVP "Analyse -> Renommage -> Classement/Routage".

## Modules

- `OrchivisteAPI` : API Vapor, UI SSR Leaf, preview, presets, jobs, events/webhooks, routage local et Graph.
- `OrchivisteAnalyse` : service d'analyse sémantique et de fusion, avec signaux `capture` et `review`.
- `OrchivisteWorker` : worker CLI macOS / Redis pour OCR et traitements asynchrones.
- `OrchivisteSharedKit` : DTO partagés.

## Périmètre MVP livré

- ingestion locale et SharePoint
- preview serveur sans téléchargement par défaut
- analyse avec `needs_review` si confiance faible ou ambiguïté métier
- presets JSON, exemple téléchargeable et apprentissage depuis dossier
- support MVP PDF, images et documents Office
- routage local et SharePoint Graph
- option d'export PDF/A-2b avec fallback journalisé
- OpenAPI 3.1, `/v1/events`, webhooks HMAC, métriques et smoke tests

## Démarrage rapide

Local :

```bash
cd OrchivisteAnalyse
swift build -c debug --product OrchivisteAnalyse

cd ../OrchivisteAPI
swift build -c debug --product OrchivisteAPI

cd ..
./scripts/preflight_local.sh --full
```

Docker :

```bash
docker compose up -d --build redis analyse api
./scripts/check_openapi_mvp.sh
./scripts/smoke_mvp.sh
```

UI :

- `http://127.0.0.1:28780/ui`
- alias `http://127.0.0.1:28780/u`

## Documentation

- API et exploitation : [OrchivisteAPI/README.md](/Volumes/MAC_HDD/Logiciel%20test/Orchiviste/OrchivisteAPI/README.md)
- Analyse sémantique : [OrchivisteAnalyse/README.md](/Volumes/MAC_HDD/Logiciel%20test/Orchiviste/OrchivisteAnalyse/README.md)
- Déploiement Mac mini : [deploy/mac-mini/README.md](/Volumes/MAC_HDD/Logiciel%20test/Orchiviste/deploy/mac-mini/README.md)

## Validation recommandée

```bash
./scripts/check_openapi_mvp.sh
./scripts/smoke_analyse_semantic.sh
./scripts/smoke_regression_dataset.sh
./scripts/smoke_graph_router.sh
./scripts/smoke_webhook_hmac.sh
./scripts/smoke_mvp.sh
```

La branche `main` est la branche livrée. Les PR empilées existantes servent de support de review et ne reflètent pas nécessairement l'état intégral courant.
