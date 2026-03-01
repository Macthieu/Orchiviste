# OrchivisteAnalyse

Service d'analyse heuristique/fusion pour le MVP Orchiviste.

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
