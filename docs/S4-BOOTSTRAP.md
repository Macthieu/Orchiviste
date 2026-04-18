# S4 Bootstrap (stabilisation / exploitabilite legere post-S3)

Date: 2026-04-18
Perimetre initial: Orchiviste uniquement (documentaire + operationnel leger)

## Objectif de phase
Stabiliser l'usage operateur apres S3 en consolidant l'exploitabilite quotidienne
de la chaine documentaire, sans ouvrir de chantier technique large.

## Plus petit perimetre utile
- Clarifier un point d'entree operateur unique pour l'usage courant (preview/apply).
- Verifier la coherence entre guidage UI, runbook, checklist et diagnostics.
- Figer un lot minimal de checks de routine avant execution en production locale.

## Hors perimetre explicite
- Aucun changement backend.
- Aucun changement de contrats inter-outils.
- Aucun refactor UI global.
- Aucun nouveau workflow CI.
- Aucun nouveau smoke de fond.
- Aucun changement dans les autres depots Muni.
- Le stash reste hors perimetre et inchange:
  - `stash@{0}: wip(ui): cockpit.leaf en attente validation visuelle`

## Dependances sur S2 et S3
- S2: durcissement de la chaine Analyse -> Regles -> Renommage.
- S3.1: runbook + profils operatoires + playbook incident.
- S3.2: referentiel diagnostics + matrice + contrat UI.
- S3.3: patch UI minimal diagnostics.
- S3.4: signaux UI `Decision Apply` et notes operations.
- S3.5: checklist unique avant apply + cloture legere.

## Risques immediats
- Derive de scope vers des evolutions techniques non necessaires.
- Decalage entre documentation et usage operateur reel.
- Multiplication de regles operatoires redondantes.
- Reouverture implicite de sujets clos en S3.x.

## Ordre minimal recommande
1. Ouvrir S4-T1 en documentaire/operatoire minimal (routine de verification avant run).
2. Valider que cette routine couvre les cas courants sans ajouter de nouvelle logique.
3. Decider ensuite si un micro-lot UI supplementaire est necessaire ou non.

## Decision proposee
Ouvrir S4 comme phase courte de stabilisation/exploitabilite legere, avec livraisons
petites et reversibles, prioritairement documentaires.

## Pret a ouvrir S4-T1
Oui. Lot minimal propose:
- ajouter une note `docs/S4.1-OPS-RUN-RHYTHM.md` de routine operateur courte
  (pre-run, run, post-run) alignee sur les artefacts et diagnostics deja existants.
