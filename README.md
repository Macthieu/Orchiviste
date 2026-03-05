# Orchiviste

Orchiviste est une plateforme documentaire municipale orientée `Analyse -> Renommage -> Classement/Routage`, construite en monorepo Swift Package Manager + Vapor.

## But du logiciel

Orchiviste sert à traiter des documents administratifs (résolutions, ententes, factures, permis, procès-verbaux, etc.) avec un flux auditable et reproductible:

- ingestion des fichiers
- aperçu serveur (sans téléchargement par défaut)
- extraction de contenu et métadonnées
- proposition de nom final
- classement/routage local et SharePoint
- revue humaine lorsque la confiance est insuffisante

## Objectifs produit

- réduire les manipulations manuelles de renommage et de classement
- normaliser les noms de fichiers selon des règles métier déclaratives
- conserver une traçabilité complète (événements, raisons de revue, historique de routage)
- permettre une évolution sans recoder (presets, thésaurus, brouillons de règles)
- opérer en priorité sur macOS (Apple Silicon) avec OCR/analyse locale

## Principes de nommage

- nom significatif, précis et concis
- longueur visée courte, limite technique gérée côté moteur
- aucune mention technique dans le nom final (`signé`, `numérisé`, `OCR`, `PDF/A`, etc.)
- en cas d'incertitude, passer en `needs_review` plutôt qu'inventer

## Cible d'exécution

Le produit est pensé `macOS native-first`.

- `OrchivisteWorker` est un binaire macOS
- `OrchivisteAnalyse` peut exploiter `FoundationModels` et `CoreML` sur macOS
- Docker reste utile pour des smokes et une démo technique, mais le conteneur Linux n'active pas les frameworks Apple natifs

## Modules

- `OrchivisteAPI`: API Vapor, UI SSR Leaf, preview, presets, jobs, events/webhooks, routage local et Graph
- `OrchivisteAnalyse`: service d'analyse sémantique et de fusion, avec signaux `capture` et `review`
- `OrchivisteWorker`: worker CLI macOS/Redis pour OCR et traitements asynchrones
- `OrchivisteSharedKit`: DTO partagés

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

Local:

```bash
cd OrchivisteAnalyse
swift build -c debug --product OrchivisteAnalyse

cd ../OrchivisteAPI
swift build -c debug --product OrchivisteAPI

cd ..
./scripts/preflight_local.sh --full
```

Docker:

```bash
docker compose up -d --build redis analyse api
./scripts/check_openapi_mvp.sh
./scripts/smoke_mvp.sh
```

Pour utiliser `FoundationModels` et `CoreML`, lance `OrchivisteAnalyse` nativement sur macOS au lieu du conteneur `analyse`.

UI:

- `http://127.0.0.1:28780/ui`
- alias `http://127.0.0.1:28780/u`

## Documentation

- API et exploitation: [OrchivisteAPI/README.md](OrchivisteAPI/README.md)
- Analyse sémantique: [OrchivisteAnalyse/README.md](OrchivisteAnalyse/README.md)
- Déploiement Mac mini: [deploy/mac-mini/README.md](deploy/mac-mini/README.md)
- Feuille de route ML: [ml/IMPLEMENTATION_PLAN.md](ml/IMPLEMENTATION_PLAN.md)

## Validation recommandée

```bash
./scripts/check_openapi_mvp.sh
./scripts/smoke_analyse_semantic.sh
./scripts/smoke_regression_dataset.sh
./scripts/smoke_graph_router.sh
./scripts/smoke_webhook_hmac.sh
./scripts/smoke_mvp.sh
```

## Licence

Ce projet est distribué sous licence `GNU GPL v3.0`.
Voir [LICENSE](LICENSE).

La branche `main` est la branche livrée. Les PR empilées existantes servent de support de review et ne reflètent pas nécessairement l'état intégral courant.
