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

