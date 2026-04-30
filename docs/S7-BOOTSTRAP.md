# S7 - Bootstrap

## Objectif de phase

S7 vise a rapprocher le catalogue Muni d'un App Store local simple, sans
changer le contrat canonique ni transformer les modules Muni en workflow
generalise. Le but est de rendre les modules installes plus lisibles, plus
selectionnables et plus faciles a administrer localement.

## Plus petit perimetre utile

- exposer une page catalogue Muni lisible pour les modules connus ;
- afficher l'etat local d'un module : disponible, non disponible, pret pour
  employe, reserve expert ou incomplet ;
- montrer les actions principales deja existantes pour `MuniRenommage` et
  `MuniConversion` ;
- conserver `Pilotage > Lancer` comme interface expert / orchestrateur ;
- garder une administration locale simple, basee sur le registre Muni existant.

## Hors perimetre explicite

- aucun vrai App Store distant ;
- aucun telechargement ou installation de modules depuis Internet ;
- aucun marketplace public ;
- aucun changement du moteur metier des apps Muni ;
- aucun changement du contrat canonique `run --request --result` ;
- aucun retry generique multi-apps ;
- aucune refonte complete du cockpit expert ;
- aucun workflow CI ou release.

## Dependances sur S6

- registre Muni pilote par SQLite ;
- facades employe existantes pour `MuniRenommage` et `MuniConversion` ;
- composant partage de selection de chemin ;
- reprise employe minimale `MuniConversion` ;
- smoke cible de reprise employe ;
- `preflight_local.sh --full` couvrant la reprise en natif macOS.

## Risques immediats

- confondre catalogue local et installation distante ;
- dupliquer la logique de disponibilite deja presente dans le registre Muni ;
- etendre trop vite le modele a toutes les apps Muni ;
- melanger l'experience employe et l'interface expert ;
- ajouter des etats UI sans source de verite claire.

## Ordre minimal recommande

1. `S7.1` : creer une note de cadrage App Store Muni minimal avec les etats,
   actions et limites fonctionnelles attendues.
2. `S7.2` : ajouter ou ajuster une vue catalogue Muni locale en lecture seule,
   sans nouvelle logique metier.
3. `S7.3` : relier les actions employe existantes depuis le catalogue pour les
   modules deja couverts.
4. `S7.4` : documenter les criteres pour rendre un module visible comme
   "pret employe".

## Decision proposee

Ouvrir S7 comme phase courte, documentaire puis UI minimale, centree sur un
catalogue Muni local plus lisible. La phase doit rester bornee a la gestion
locale des modules deja declares et ne doit pas devenir un App Store distant.

## Pret a ouvrir S7.1

Le plus petit lot `S7.1` propose est :

`docs/S7.1-MUNI-APP-STORE-SCOPE.md`

Objectif de `S7.1` : definir le vocabulaire minimal de l'App Store Muni local
(`disponible`, `non disponible`, `pret employe`, `expert uniquement`,
`incomplet`), les actions visibles par type de module et les limites a ne pas
franchir avant toute modification applicative.
