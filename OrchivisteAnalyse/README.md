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
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_INPUT_VECTOR=input
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_OUTPUT_SCORES=var_123
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_LABELS_PATH=/chemin/vers/document_classifier.labels.json
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_LABELS=Resolution,ProcesVerbal,Facture,Permis,Entente,Depot,AvisMotion,Autre
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_VECTOR_SIZE=256
```

Le modele attendu peut etre :

- soit un classifieur texte Core ML deja compile, charge localement sur macOS
- soit un classifieur vectoriel Core ML recevant un `MLMultiArray`, avec une liste de labels externe

Exemple local avec le modele bootstrap genere dans le repo :

```bash
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_ENABLED=1
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_MODEL_PATH=ml/models-coreml/document_classifier_bootstrap.mlpackage
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_INPUT_VECTOR=input
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_OUTPUT_SCORES=var_14
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_LABELS_PATH=ml/models-src/document_classifier_bootstrap.labels.json
ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_VECTOR_SIZE=256
```

## Similarite semantique / embeddings

Une couche complementaire de similarite semantique peut maintenant etre activee pour comparer un document a :

- des classes du plan de classification
- des regles de nommage
- des exemples valides

Variables utiles:

```bash
ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_ENABLED=1
ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_INDEX_PATH=/chemin/vers/embedding_reference.jsonl
ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_TOP_K=5
ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_MIN_SCORE=0.18
```

Cette couche reste une aide a la decision. Le rendu final du nom et le routage restent gouvernes par les regles et validations deterministes.

La meme reference peut maintenant aussi alimenter le ranking de regles de nommage (couche `OrchivisteAnalyseCore`) :

```bash
ORCHIVISTE_NAMING_EMBEDDINGS_ENABLED=1
ORCHIVISTE_NAMING_EMBEDDINGS_INDEX_PATH=/chemin/vers/embedding_reference.jsonl
ORCHIVISTE_NAMING_EMBEDDINGS_TOP_K=8
ORCHIVISTE_NAMING_EMBEDDINGS_MIN_SCORE=0.12
```

## Outillage ML

Scripts ajoutes dans `ml/scripts/` :

- `export_training_dataset.py` : exporte un corpus JSONL a partir des feedbacks de nommage et des artefacts OCR
- `train_document_classifier.py` : entraine un premier classifieur PyTorch a vecteurs hashes, compatible conversion `Core ML`
- `build_embedding_reference.py` : construit un index JSONL de references semantiques a partir des regles et du plan de classification

Flux minimal recommande :

```bash
python ml/scripts/export_training_dataset.py \
  --ocr-artifact-dir /chemin/vers/ocr-artifacts

python ml/scripts/train_document_classifier.py \
  --train ml/datasets/labeled/classification_train.jsonl \
  --eval ml/datasets/labeled/classification_eval.jsonl

python ml/scripts/convert_to_coreml.py \
  --source ml/models-src/document_classifier.pt \
  --output ml/models-coreml/document_classifier.mlpackage \
  --input-name input \
  --input-shape 1,256

python ml/scripts/build_embedding_reference.py \
  --taxonomy OrchivisteAPI/configs/analysis/taxonomy/syged_2026.json \
  --output ml/datasets/labeled/embedding_reference.jsonl
```

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
