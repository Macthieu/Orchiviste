# S3 Bootstrap (cadrage minimal)

Date: 2026-04-16
Perimetre initial: Orchiviste (cadrage seulement, pas de developpement applicatif)

## Objectif de S3
Passer de la chaine V1 "fonctionnelle et smokee" a une execution plus operationnelle, lisible et pilotable dans Orchiviste, sans casser les contrats canoniques entre:
- MuniAnalyse
- MuniRegles
- MuniRenommage

## Sous-phases prevues (proposition)

### S3.1 - Pilotage operatoire de la chaine
- Clarifier et standardiser le runbook Orchiviste pour la chaine rename.
- Definir les profils de lancement minimaux (preview/apply controle) dans Pilotage.
- Rendre les preconditions explicites (bundle, metadata, regle, garde-fous).

### S3.2 - Robustesse produit et diagnostics
- Normaliser les diagnostics operatoires visibles (fallbacks, warnings, provenance, plan_digest).
- Uniformiser les criteres d'echec exploitable (messages actionnables, raisons stables).
- Renforcer les verifications de non-regression sur le flux Orchiviste -> Muni*.

### S3.3 - Cadence de release et exploitation
- Formaliser le package de validation de release de la chaine.
- Definir le niveau minimal de preuve avant publication (smokes, tracabilite, checklists).
- Stabiliser la documentation d'usage "demo -> production guidee".

## Depots probablement concernes
- Orchiviste (point d'entree S3, prioritaire)
- MuniRenommage
- MuniAnalyse
- MuniRegles

## Dependances sur les acquis S2
- S2 a livre les contrats et traces minimales inter-outils.
- S2 a livre les smokes E2E positif et negatif.
- S2 a ajoute le workflow manuel de smoke rename-chain.
- S2 a clarifie la couverture indirecte de l'ancien bloc S2.4.

## Risques / points de vigilance immediats
- Derive de scope (ouvrir trop tot des chantiers hors S3.1).
- Divergence entre UX Orchiviste et comportement reel des CLI.
- Regression sur les garde-fous destructifs si specification de lancement ambigue.
- Inflation documentaire sans impact operatoire.

## Ordre d'execution minimal propose
1. Valider le contour strict de S3.1 (Orchiviste d'abord, sans refactor).
2. Produire une specification d'execution operatoire unique (inputs, preconditions, sorties attendues).
3. Implementer le lot S3.1 minimal dans Orchiviste.
4. Rejouer smokes positif/negatif et verifier la lisibilite des diagnostics en Pilotage.
5. Ouvrir ensuite S3.2 uniquement si S3.1 est stabilisee.

## Decision proposee
S3 peut etre ouverte avec un premier lot limite a S3.1 sur Orchiviste.

**Pret a ouvrir S3.1.**
