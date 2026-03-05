# Jeux de donnees ML Orchiviste

## Structure recommandee

- `raw/` : exports bruts ou anonymises en entree
- `derived/` : textes OCR / nettoyes / segmentes
- `labeled/` : corpus valides pour classification et similarite

## Formats recommandes

- `jsonl` pour les corpus
- schemas de reference dans `../contracts/`

## Fichiers cibles

- `labeled/classification_train.jsonl`
- `labeled/classification_eval.jsonl`
- `labeled/embedding_reference.jsonl`

## Regles de base

- ne pas committer de corpus sensible non anonymise
- privilegier des extraits et metadonnees valides humainement
- conserver `document_id`, `class_code`, `type_document`, `validated_filename`
- si le texte integral ne peut pas etre committe, stocker un `text_path` hors git

## Utilisation prevue

- le classifieur texte consomme `classification_*.jsonl`
- l'index de similarite consomme `embedding_reference.jsonl`
- les corrections de nommage validees servent a enrichir ces corpus

## Bootstrap local rapide

Quand les feedbacks humains sont encore peu nombreux, Orchiviste peut demarrer avec
un corpus faiblement supervise derive des fichiers deja routes :

```bash
python3 ml/scripts/bootstrap_training_dataset.py \
  --routed-dir runtime/routed \
  --output-train ml/datasets/labeled/classification_bootstrap_train.jsonl \
  --output-eval ml/datasets/labeled/classification_bootstrap_eval.jsonl
```

Puis construire l'index de references semantiques :

```bash
python3 ml/scripts/build_embedding_reference.py \
  --rules-dir OrchivisteAPI/configs/naming/rules \
  --taxonomy OrchivisteAPI/configs/analysis/taxonomy/syged_2026.json \
  --output ml/datasets/labeled/embedding_reference.jsonl
```

Et, dans un environnement Python 3.11 local avec `torch` et `coremltools` :

```bash
.venv-coreml311/bin/python ml/scripts/train_document_classifier.py \
  --train ml/datasets/labeled/classification_bootstrap_train.jsonl \
  --eval ml/datasets/labeled/classification_bootstrap_eval.jsonl \
  --label-field type_document \
  --vector-size 256 \
  --hidden-size 128 \
  --epochs 25 \
  --device cpu \
  --output-model ml/models-src/document_classifier_bootstrap.pt \
  --output-labels ml/models-src/document_classifier_bootstrap.labels.json \
  --output-metrics ml/models-src/document_classifier_bootstrap.metrics.json

.venv-coreml311/bin/python ml/scripts/convert_to_coreml.py \
  --source ml/models-src/document_classifier_bootstrap.pt \
  --output ml/models-coreml/document_classifier_bootstrap.mlpackage \
  --input-name input \
  --input-shape 1,256
```

Ce bootstrap reste un point de depart. Le corpus de production doit ensuite etre enrichi
avec des feedbacks humains valides et, idealement, du texte OCR ou natif reel.

## Evaluation locale du ranking de nommage

Pour mesurer l'impact des regles + similarite semantique (sans committer de PDF) :

```bash
python3 ml/scripts/evaluate_naming_quality.py \
  --dataset ml/datasets/labeled/classification_external_eval.jsonl \
  --rules-dir OrchivisteAPI/configs/naming/rules \
  --embedding-index ml/datasets/labeled/embedding_reference.jsonl \
  --output-report ml/datasets/labeled/naming_quality_report.json \
  --output-details-csv ml/datasets/labeled/naming_quality_details.csv
```

Le rapport JSON fournit notamment :

- `top1_accuracy` et `top3_accuracy`
- `deterministic_top1_accuracy`
- `semantic_improvements` (cas corriges grace a la couche semantique)
- `filename_validation_pass_rate`

## Corpus externes (familles separees)

Pour eviter de melanger des familles qui n'ont pas la meme regle de nommage
(ex.: `Entente` vs `Resolution`), utiliser le prepareur externe :

```bash
python3 ml/scripts/prepare_external_training_corpora.py \
  --resolution-folder "/Users/mathieubeaudin/Desktop/Résolution pour tester" \
  --entente-folder "/Users/mathieubeaudin/Desktop/Entente à tester" \
  --permis-folder "PDF Permis" \
  --output-dir ml/datasets/labeled
```

Ce script produit des jeux distincts :

- `classification_resolution_conseil_{train,eval}.jsonl`
- `classification_avis_motion_{train,eval}.jsonl`
- `classification_depot_{train,eval}.jsonl`
- `classification_entente_uniformisee_{train,eval}.jsonl`
- `classification_permis_construction_{train,eval}.jsonl` (si `--permis-folder` est fourni)
- `classification_external_{train,eval}.jsonl`

et un rapport d'inclusion/exclusion :

- `classification_external_report.json`
