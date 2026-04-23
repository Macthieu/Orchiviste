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
- Standardiser une transmission d'escalade courte, complete et exploitable.

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

## Socle operateur S4
Le socle operateur S4 est fige autour de trois notes courtes et complementaires:
- [S4.1 Ops Run Rhythm](S4.1-OPS-RUN-RHYTHM.md): rythme operatoire court.
- [S4.2 Daily Operations Check](S4.2-DAILY-OPERATIONS-CHECK.md): verification quotidienne minimale.
- [S4.3 Escalation Handoff](S4.3-ESCALATION-HANDOFF.md): transmission d'escalade normalisee.

## Couverture du socle
Ce socle couvre explicitement:
- un rythme operatoire court
- une verification quotidienne minimale
- une transmission d'escalade normalisee

## Decision proposee
Ouvrir S4 comme phase courte de stabilisation/exploitabilite legere, avec livraisons
petites et reversibles, prioritairement documentaires.

## Statut
Socle operateur S4 maintenant en place.
