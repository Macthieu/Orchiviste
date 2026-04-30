# Post-S6 Milestone

Date: 2026-04-30
Perimetre: Orchiviste (jalon programme post-S6)

## Phases cloturees

- `S2`: cloturee.
- `S3`: cloturee.
- `S4`: cloturee.
- `S5`: cloturee.
- `S6`: cloturee dans son perimetre minimal exploitable.

## Livrables concrets obtenus par phase

- `S2`: base technique stabilisee pour la chaine Analyse -> Regles -> Renommage, avec garde-fous et diagnostics de base.
- `S3`: pack operatoire, referentiel diagnostics et patch UI minimal sur Pilotage/Historique.
- `S4`: socle operateur minimal documentaire pour le rythme de run, la verification quotidienne et la transmission d'escalade.
- `S5`: cadrage strict du durcissement technique cible puis micro-lot utile sur l'integrite `preview/apply`.
- `S6`: socle Muni exploitable avec registre SQLite, facades employe `MuniRenommage` et `MuniConversion`, selection de chemin partagee, resultat conversion lisible, reprise employe minimale, smoke cible et preflight local natif macOS sans Docker obligatoire.

## Hors perimetre restant

- aucune refonte large backend ou UI ;
- aucun retry generique multi-apps ;
- aucun App Store Muni ;
- aucune extension generale a tous les logiciels Muni ;
- aucun nouveau workflow CI ou release ;
- aucune modification du contrat canonique `run --request --result` ;
- aucune modification du moteur metier `MuniConvert`.

## Stash UI

Le stash UI reste inchange et toujours hors perimetre :

- `stash@{0}: On main: wip(ui): cockpit.leaf en attente validation visuelle`

## Conclusion

Le programme est stabilise au palier post-S6.
Toute phase suivante devra faire l'objet d'une decision explicite.
