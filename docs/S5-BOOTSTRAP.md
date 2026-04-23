# S5 Bootstrap (durcissement technique cible post-S4)

Date: 2026-04-23
Perimetre initial: Orchiviste uniquement (documentaire + robustesse technique ciblee)

## Objectif de phase
Ouvrir une phase courte de durcissement technique cible afin d'ameliorer la
robustesse, la non-regression et l'exploitabilite sure, sans relancer de chantier
large UI/backend.

## Plus petit perimetre utile
- Identifier les points de fragilite technique encore ouverts ou mal bornes.
- Prioriser un nombre tres limite de validations utiles contre la non-regression.
- Clarifier les preuves minimales attendues avant toute evolution technique ciblee.
- Eviter les corrections diffuses sans critere d'entree ni de sortie.

## Hors perimetre explicite
- Aucun changement applicatif dans ce bootstrap.
- Aucun refactor backend.
- Aucun refactor UI.
- Aucun nouveau smoke de fond.
- Aucun nouveau workflow CI dans ce lot.
- Aucun elargissement de perimetre hors `Orchiviste`.
- Le stash reste hors perimetre et inchange:
  - `stash@{0}: On main: wip(ui): cockpit.leaf en attente validation visuelle`

## Dependances sur les acquis S2 / S3 / S4
- S2: base technique durcie de la chaine Analyse -> Regles -> Renommage.
- S3: corpus operatoire, referentiel diagnostics et patch UI minimal deja poses.
- S4: socle operateur minimal en place pour le rythme, le controle quotidien et
  les escalades.

## Risques immediats
- Derive vers un chantier de fiabilisation trop large ou mal borne.
- Confusion entre durcissement technique cible et refonte applicative.
- Multiplication de validations peu utiles ou non reliees a un risque reel.
- Ouverture prematuree de changements techniques sans criteres de non-regression.

## Ordre minimal recommande
1. Cadrer les risques techniques prioritaires encore ouverts.
2. Definir pour chacun la validation minimale utile et le niveau de preuve attendu.
3. Ouvrir seulement ensuite un micro-lot technique cible si un risque concret le justifie.

## Decision proposee
Ouvrir S5 comme phase courte de durcissement technique cible, avec entrees
strictes, validations limitees et livraisons petites, sans refactor ni relance de
chantier large.

## Pret a ouvrir S5.1
Oui. Plus petit lot propose:
- ajouter une note `docs/S5.1-TARGETED-HARDENING-SCOPE.md` qui liste un tres petit
  nombre de risques techniques prioritaires, leur impact, la validation minimale
  attendue et les criteres de non-regression avant toute modification applicative.
