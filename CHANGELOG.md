# Changelog

Toutes les modifications notables de ce projet seront documentées dans ce fichier.

Le format s'inspire de Keep a Changelog et le projet suit Semantic Versioning.

## [0.2.0] - 2026-03-14

### Added
- Cockpit V1 Orchiviste avec catalogue des outils Muni et fiches de capacités/version/statut.
- Lancement canonique des outils via contrat OrchivisteKit (`run --request <file> --result <file>`).
- Historique local cockpit au format `history.jsonl`.
- Routes API cockpit (`/v1/cockpit/tools`, `/v1/cockpit/config`, `/v1/cockpit/history`, `/v1/cockpit/runs`).
- Vue UI cockpit (`/ui/cockpit`) avec garde-fous explicites pour actions potentiellement destructives.
- Smoke test dédié cockpit V1 (`scripts/smoke_cockpit_v1.sh`).

### Changed
- Alignement toolchain `OrchivisteAPI` vers Swift tools `6.0` et baseline macOS `14`.
- Alignement de la dépendance `OrchivisteKit` pour l'intégration canonique.

## [0.1.0] - 2026-03-14

### Added
- Première base de normalisation documentaire pour publication GitHub.
- Harmonisation README/licence/processus de contribution.
