# OrchivisteAnalyse

Service d'analyse heuristique/fusion pour le MVP Orchiviste.

## Orientation macOS

Le service est pensé pour une execution native sur macOS. Il peut maintenant exploiter deux briques Apple locales quand elles sont disponibles:

- `Vision` pour l'OCR via `OrchivisteWorker`
- `FoundationModels` pour enrichir le resume generatif et les metadonnees suggerees
- `CoreML` pour une classification locale si un modele compile est fourni

## Providers Apple natifs

### Foundation Models

Active par defaut si le framework est disponible et si Apple Intelligence est active sur la machine.

Variables utiles:

```bash
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_FM_ENABLED=1
ORCHIVISTE_ANALYSE_APPLE_TEXT_MAX_CHARS=12000
```

Le provider enrichit surtout:

- `summary.generated`
- `summary.title`
- `summary.highlights`
- `metadata.type_document`
- `metadata.numero_document`
- `metadata.objet`
- `metadata.date_document`
- `metadata.organisme_emetteur`
- `metadata.mots_cles`

### Core ML

Active seulement si un modele local est fourni.

Variables utiles:

```bash
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_ENABLED=1
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_MODEL_PATH=/chemin/vers/DocumentClassifier.mlmodelc
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_INPUT_TEXT=text
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_OUTPUT_LABEL=label
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_OUTPUT_PROBABILITIES=labelProbability
```

Le modele attendu est un classifieur texte Core ML deja compile, charge localement sur macOS.

## Capture intelligente

Le pipeline applique une logique "contenu d'abord" au lieu de gabarits OCR XY fixes:

- segmentation semantique des unites documentaires
- detection de sections, titres, clauses et signatures
- extraction de champs avec provenance (`field_sources`)
- signal `review` structure quand les champs requis sont absents ou ambigus
- preservation d'une sortie exploitable par renommage, classement et routage

La sortie `POST /v1/analyse` conserve le contrat existant et ajoute deux blocs optionnels:

- `capture`: strategie, sections, unites, warnings et provenance des champs
- `review`: `needs_review`, raisons, champs manquants, ambiguities

## Tests

```bash
cd OrchivisteAnalyse
swift test
```

Validation fonctionnelle du service :

```bash
cd ..
./scripts/smoke_analyse_semantic.sh
```
