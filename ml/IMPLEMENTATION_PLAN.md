# Plan ML Orchiviste

## Objectif

Construire Orchiviste comme un pipeline a deux niveaux :

1. Decision rapide
   - OCR `Vision`
   - extraction semantique
   - classification locale `Core ML`
2. Validation intelligente
   - embeddings semantiques
   - similarite document <-> classes / regles / exemples
   - reconciliation des signaux
   - `needs_review` si desaccord ou confiance insuffisante

Le rendu final du nom de fichier reste gouverne par :

1. extraction structuree
2. scoring / suggestion ML
3. application d'une regle declarative
4. normalisation deterministe
5. validation finale

## Etat actuel du repo

Points deja presents :

- `Vision` cote worker : `OrchivisteWorker/Sources/OrchivisteWorker/OrchivisteWorker.swift`
- provider `AppleCoreML` : `OrchivisteAnalyse/Sources/OrchivisteAnalyse/Providers/AppleNativeProviders.swift`
- provider `AppleFoundationModels` : `OrchivisteAnalyse/Sources/OrchivisteAnalyse/Providers/AppleNativeProviders.swift`
- fusion et confiance : `OrchivisteAnalyse/Sources/OrchivisteAnalyse/Services/WeightedFusionEngine.swift`
- base de test Core ML naming :
  - `ml/models-src/tiny_doc_classifier.pt`
  - `ml/models-coreml/tiny_doc_classifier.mlpackage`
  - `ml/scripts/create_test_torchscript.py`
  - `ml/scripts/convert_to_coreml.py`

Conclusion : le point d'entree `Core ML` existe deja. La prochaine etape n'est pas une refonte, mais l'industrialisation du jeu de donnees, du training et de la couche embeddings.

## Decision technique retenue

### Couche OCR / extraction

- Conserver `Vision` dans `OrchivisteWorker`
- Continuer a alimenter `AnalysisRequest` avec le meilleur texte disponible
- Garder les signaux de structure existants :
  - `capture.*`
  - `review.*`
  - `metadata.*`
  - `summary.*`

### Couche classification

- Entrainer les modeles en `PyTorch`
- Utiliser `mps` sur Mac pour accelerer l'entrainement local
- Convertir vers `Core ML` avec `coremltools`
- Executer les modeles en local dans `AppleCoreMLProvider`

### Couche similarite / embeddings

- Ajouter une couche separee de similarite semantique
- Encoder :
  - texte du document
  - descriptions de types documentaires
  - descriptions de classes du plan de classification
  - regles de nommage
  - exemples valides
- Utiliser cette couche pour :
  - reclasser des candidats
  - retrouver les exemples les plus proches
  - expliquer les suggestions
  - renforcer ou invalider le classifieur

### Couche de decision finale

- `Core ML` et embeddings restent des aides a la decision
- les regles declaratives gardent la responsabilite du nom final
- en cas de desaccord entre extraction / classifieur / similarite :
  - augmenter `needs_review`
  - conserver les preuves et les scores

## Phase 1 - Premier classifieur texte

### But

Predire au minimum :

- `type_document`
- `class_code` suggere
- `preset_id` suggere

### Sortie attendue

Le provider `AppleCoreML` doit continuer de renvoyer un `ProviderCandidate` compatible avec l'existant :

- `typeDoc`
- `suggestedClassCode`
- `suggestedPreset`
- `confidence`
- `champs["apple_coreml.*"]`

### Fichiers cibles dans le repo

- training :
  - `ml/scripts/train_document_classifier.py` (a creer dans la prochaine passe)
  - `ml/scripts/export_training_dataset.py` (a creer)
- modeles :
  - `ml/models-src/`
  - `ml/models-coreml/`
- inference :
  - `OrchivisteAnalyse/Sources/OrchivisteAnalyse/Providers/AppleNativeProviders.swift`

### Jeu de labels minimal

- `Resolution`
- `ProcesVerbal`
- `Facture`
- `Permis`
- `Entente`
- `Depot`
- `AvisMotion`
- `Autre`

Et un mapping stable vers :

- `class_code`
- `preset_id`

## Phase 2 - Embeddings semantiques

### But

Ajouter une deuxieme source de decision, plus robuste sur les cas ambigus.

### Ce que la couche embeddings doit comparer

- document <-> type documentaire
- document <-> classe du plan
- document <-> regle de nommage
- document <-> exemples valides

### Sorties attendues

Sans casser l'API actuelle, preparer une sortie interne du type :

- `embedding.top_class_codes`
- `embedding.top_rule_ids`
- `embedding.top_examples`
- `embedding.similarity_score`
- `embedding.disagreement_with_coreml`

### Point d'integration futur

- nouveau provider ou service dans `OrchivisteAnalyse`
- fusion dans `WeightedFusionEngine`
- exploitation en UI pour expliquer "pourquoi cette classe / cette regle"

## Phase 3 - Reconciliation et review

Le score final de confiance doit tenir compte de :

- extraction semantique
- `AppleCoreML`
- embeddings
- presence / absence des champs requis
- compatibilite avec la regle de nommage candidate

Exemples de declenchement `needs_review` :

- classifieur fort mais embeddings contradictoires
- bonne similarite mais type documentaire faible
- numero/date manquants
- regle candidate plausible mais validation finale echoue

## Contrat de donnees d'entrainement

Le contrat de donnees vit dans :

- `ml/contracts/document_training_record.schema.json`
- `ml/contracts/embedding_reference_record.schema.json`

Format recommande :

- fichiers `jsonl`
- un document valide par ligne
- pas de texte integral brut si la politique de conservation ne le permet pas
- possibilite de stocker soit le texte, soit un chemin vers un texte OCR derive

## Jeux de donnees recommandes

### `classification_train.jsonl`

Pour entrainer le classifieur :

- texte OCR / texte natif
- `type_document`
- `class_code`
- `preset_id`
- statut de validation humaine

### `embedding_reference.jsonl`

Pour la similarite semantique :

- description de classes
- description de regles
- exemples valides
- texte de reference court / long

## Repartition repo recommandee

### `ml/`

- `ml/contracts/`
- `ml/datasets/raw/`
- `ml/datasets/derived/`
- `ml/datasets/labeled/`
- `ml/models-src/`
- `ml/models-coreml/`
- `ml/scripts/`

### `OrchivisteAnalyse`

Sans casser l'existant :

- garder `AppleCoreMLProvider`
- ajouter ensuite un `EmbeddingSimilarityProvider`
- garder `WeightedFusionEngine` comme lieu de reconciliation

## Variables d'environnement proposees

### Classifieur Core ML

Variables deja existantes :

- `ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_ENABLED`
- `ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_MODEL_PATH`
- `ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_INPUT_TEXT`
- `ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_OUTPUT_LABEL`
- `ORCHIVISTE_ANALYSE_PROVIDER_APPLE_COREML_OUTPUT_PROBABILITIES`

### Couche embeddings future

Variables a ajouter plus tard :

- `ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_ENABLED`
- `ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_MODEL_PATH`
- `ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_INDEX_PATH`
- `ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_TOP_K`
- `ORCHIVISTE_ANALYSE_PROVIDER_EMBEDDINGS_MIN_SCORE`

## Ordre de mise en oeuvre recommande

1. Stabiliser le contrat de donnees d'entrainement
2. Exporter un premier corpus valide depuis des documents corriges
3. Entrainer un premier classifieur `PyTorch`
4. Convertir vers `Core ML`
5. Mesurer dans `AppleCoreMLProvider`
6. Ajouter la couche embeddings
7. Brancher la reconciliation dans `WeightedFusionEngine`
8. Exposer les preuves en UI

## Definition de fini pour la phase 1

- modele local chargeable sur macOS
- score exploitable dans `AppleCoreMLProvider`
- logs et champs explicables
- pas de regression sur le pipeline existant
- `needs_review` en dessous du seuil

## Definition de fini pour la phase 2

- index embeddings chargeable localement
- top `k` voisins exploitables
- comparaison document / classe / regle / exemple
- explication visible en UI et dans le JSON d'analyse

