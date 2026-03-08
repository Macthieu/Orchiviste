# Roadmap Orchiviste (PR1 -> PR8)

Mise à jour: 2026-03-07

## Objectif global

Livrer un pipeline robuste pour l'archivistique municipale:

- ingestion et aperçu serveur
- extraction de métadonnées utiles
- renommage métier déclaratif
- classement/routage local et SharePoint
- revue humaine traçable pour les cas ambigus

## Contraintes de gouvernance

- stabilité du moteur compilé (Swift/Vapor)
- règles et thésaurus modifiables sans recoder
- `needs_review` privilégié en cas d'incertitude
- compatibilité licence maintenue en `GPLv3`
- inspiration externe permise, copie de code encadrée par la licence

## Cadence recommandée

- PR courtes et testables
- 1 PR = 1 objectif principal
- validation locale + smoke scripts avant merge

## PR1 — Positionnement et documentation (terminé)

Objectif: clarifier la mission, le public cible et la valeur métier.

Livrables:

- README consolidé (mission, valeur apportée, positionnement, méthodologie)
- suppression des références non pertinentes en docs
- licence GPLv3 en place

Critères d'acceptation:

- README compréhensible en moins de 2 minutes
- message produit cohérent avec l'usage archivistique municipal

## PR2 — Fiabilisation Ententes/Résolutions

Objectif: améliorer la qualité de nommage sur les champs critiques.

Statut: en cours (implémentation backend déjà appliquée le 2026-03-07, validation UI lot réel en cours)

Livrables:

- extraction renforcée de `cocontractant`, `objet`, `période` (ententes)
- extraction renforcée de `numero`, `titre`, `date de séance` (résolutions)
- règles JSON ajustées pour ces familles documentaires

Critères d'acceptation:

- baisse visible des corrections manuelles sur lot de test
- cohérence accrue du nom final proposé

Validation:

- `./scripts/smoke_analyse_semantic.sh`
- lot réel Ententes/Résolutions en UI

## PR3 — Apprentissage par corrections (visionneuse)

Objectif: transformer les corrections utilisateur en apprentissage réutilisable.

Statut: en cours (replay feedback et persistance renforcés côté moteur, validation sur lot réel à compléter)

Livrables:

- persistance fiable des corrections mémorisées
- réutilisation automatique sur cas similaires
- traçabilité des corrections appliquées

Critères d'acceptation:

- une correction mémorisée influence les prochaines propositions
- aucun impact régressif sur routes existantes

Validation:

- tests manuels via visionneuse
- `./scripts/smoke_mvp.sh`

## PR4 — OCR/HTR pour documents difficiles (permis, scans anciens)

Objectif: mieux traiter manuscrit et scans de faible qualité.

Livrables:

- pipeline OCR plus robuste avec timeouts et garde-fous
- meilleure extraction sur permis historiques
- gestion propre des échecs sans blocage global

Critères d'acceptation:

- baisse des tâches bloquées ou en attente infinie
- amélioration du rappel sur champs clés des permis

Validation:

- lot `PDF Permis` en batch
- `./scripts/smoke_regression_dataset.sh`

## PR5 — Scoring sémantique (CoreML/embeddings en assistance)

Objectif: améliorer la sélection de règle et de code de classement.

Livrables:

- ranking des règles enrichi par signaux sémantiques
- fallback déterministe conservé
- séparation stricte: ML assiste, règle déclarative décide le rendu final

Critères d'acceptation:

- meilleure pertinence du preset/règle proposée
- comportement stable sans modèle ML

Validation:

- `./scripts/smoke_coreml_naming.sh`
- tests comparatifs avant/après sur même lot

## PR6 — UX archiviste (viewer + classification)

Objectif: réduire la friction de revue et de routage.

Livrables:

- panneau de droite viewer optimisé (lisibilité JSON/OCR/métadonnées)
- sélection code de classement avec libellé exploitable
- champs de correction plus ergonomiques

Critères d'acceptation:

- temps moyen de revue manuel réduit
- moins d'erreurs de sélection de code

Validation:

- parcours manuel UI
- contrôle des routes `/ui/*` et `/v1/*` concernées

## PR7 — Performance et stabilité des lots

Objectif: augmenter le débit sans dégrader la fiabilité.

Livrables:

- parallélisme contrôlé (queues, limites de concurrence)
- meilleure gestion des retries/timeout
- mise à jour des compteurs dashboard plus fluide

Critères d'acceptation:

- traitement de gros lots sans blocage
- métriques stables en charge

Validation:

- `./scripts/smoke_mvp.sh`
- `./scripts/smoke_metrics.sh`
- import lot massif depuis UI

## PR8 — Gouvernance licence et réutilisation

Objectif: garantir que l'évolution reste juridiquement propre et compatible GPLv3.

Livrables:

- politique interne de réutilisation de code externe
- traçabilité locale des inspirations/composants retenus
- revue licence avant toute intégration de code tiers

Critères d'acceptation:

- aucune dépendance ajoutée sans vérification de licence
- copie de code externe uniquement si compatible et attribuée

Règle opérationnelle:

- projets Apache-2.0 ou GPL-3.0: réutilisation possible avec obligations respectées
- projets AGPL/GPL-2.0/MPL: préférer inspiration ou usage en outil externe selon cas
- modèles/datasets: valider séparément la licence des poids et des données

## Définition de terminé (DoD) pour chaque PR

- build OK des modules modifiés
- smoke tests pertinents exécutés
- pas de rupture des endpoints existants
- documentation mise à jour si comportement changé
- checklist manuelle courte jointe dans la PR
