# Changelog

Toutes les modifications notables de ce projet seront documentées dans ce fichier.

Le format s'inspire de Keep a Changelog et le projet suit Semantic Versioning.

## [0.3.0] - 2026-03-16

### Added
- Officialisation du cockpit V1 comme point d'entree de la suite Orchiviste/Muni.
- Activation de `MuniAnalyse` en statut `active` (version affichee `0.2.0`).
- Activation de `MuniMetadonnees` en statut `active` (version affichee `0.2.0`).
- Activation de `MuniPreclassement` en statut `active` (version affichee `0.2.0`).
- Activation de `MuniControle` en statut `active` (version affichee `0.2.0`).

### Changed
- Alignement du catalogue cockpit (missions, capacites et actions par defaut) pour reflet operationnel des outils actifs.
- Alignement de la documentation Orchiviste sur le statut fonctionnel reel du cockpit V1.

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
