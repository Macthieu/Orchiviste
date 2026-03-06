# Orchiviste

Orchiviste est une plateforme documentaire municipale orientée `Analyse -> Renommage -> Classement/Routage`, construite en monorepo Swift Package Manager + Vapor.

## Mission

Orchiviste est une plateforme de traitement documentaire municipal conçue pour aider le travail d'archiviste: transformer des lots hétérogènes en documents analysés, nommés, classés et traçables.

Flux opérationnel: ingestion -> aperçu serveur -> extraction contenu/métadonnées -> proposition de nom -> classement/routage (local/SharePoint) -> revue humaine si confiance insuffisante.

## Valeur apportée

- réduit les manipulations manuelles de renommage et de classement
- applique des règles métier déclaratives, modifiables sans recoder
- conserve une traçabilité complète (événements, raisons de revue, historique)
- priorise un fonctionnement local macOS (Apple Silicon) pour OCR/analyse
- sépare la décision automatique de la validation humaine (`needs_review`)

## Positionnement

Par rapport aux outils OCR/IDP/EDMS génériques, Orchiviste cible l'usage archivistique municipal avec:

- règles de nommage métier + préréglages orientés administration publique
- extraction de métadonnées utiles au classement documentaire
- routage intégré vers arborescence cible et SharePoint
- workflow de revue auditable pour les cas ambigus

## Principes de nommage

- nom significatif, précis et concis
- longueur visée courte, limite technique gérée côté moteur
- aucune mention technique dans le nom final (`signé`, `numérisé`, `OCR`, `PDF/A`, etc.)
- en cas d'incertitude, passer en `needs_review` plutôt qu'inventer

## Méthodologie de développement

Le projet est piloté par le besoin métier archivistique et développé dans `Visual Studio Code`, avec assistance d'IA (`OpenAI Codex`/`ChatGPT`) sous supervision humaine.

Les décisions fonctionnelles, la validation des règles de nommage, la revue des résultats et la gouvernance documentaire restent sous contrôle humain.

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
