# S6 - Cloture

## Statut final

S6 est terminee dans son perimetre de deploiement minimal exploitable.

| Lot | Role | Livrable |
| --- | --- | --- |
| S6.1 | Socle catalogue Muni | Registre Muni pilote par SQLite |
| S6.2 | Premiere facade employe | `MuniRenommage` accessible hors pilotage expert |
| S6.3 | Composant UI partage | Selection de chemin `Choisir / Serveur` reutilisable |
| S6.4 | Deuxieme facade employe | `MuniConversion` accessible hors pilotage expert |
| S6.5 | Lisibilite resultat | Resultat employe `MuniConversion` enrichi et exploitable |
| S6.6 | Reprise minimale | Relance employe `MuniConversion` depuis un run precedent |
| S6.7 | Preuve scriptable | Smoke cible de reprise employe `MuniConversion` |
| S6.8 | Routine locale complete | Smoke S6.7 branche dans `preflight_local.sh --full` |
| S6.9 | Lisibilite routine | Note locale `--quick` vs `--full` |

## Resultat obtenu

S6 livre un premier parcours Muni exploitable par un employe sans passer par
`Pilotage > Lancer` pour les cas cibles :

- consulter les apps Muni disponibles depuis le registre ;
- utiliser une facade employe pour `MuniRenommage` ;
- utiliser une facade employe pour `MuniConversion` ;
- lire un resultat de conversion avec sorties, journal court et diagnostics ;
- reprendre une conversion apres collision ou erreur en changeant seulement
  `collision_policy` et/ou `destination_directory` ;
- verifier durablement cette reprise par un smoke cible ;
- executer la routine locale en natif macOS sans dependance Docker obligatoire.

Le contrat canonique interne reste conserve : les executions passent par
`run --request --result`, sans logique metier parallele dans les facades
employe.

## Hors perimetre maintenu

S6 ne couvre pas :

- une refonte generale de toutes les apps Muni ;
- un retry generique multi-apps ;
- de nouveaux profils de conversion ;
- une nouvelle logique metier dans `MuniConvert` ;
- une refonte complete du pilotage expert ;
- un App Store Muni ;
- une extension CI ou workflow de release.

## Conclusion

S6 est declaree terminee dans son perimetre minimal exploitable.
