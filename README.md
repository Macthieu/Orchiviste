# Orchiviste

**Orchiviste** est une plateforme modulaire de services documentaires intelligents pour le milieu municipal.

Le logiciel aide à **analyser, normaliser, nommer, enrichir, préclasser et préparer** les documents avant leur classement, leur conservation, leur versement ou leur diffusion dans les systèmes officiels.

Orchiviste n’est **ni une GED complète**, ni un orchestrateur de flux généraliste.  
L’orchestration des processus demeure du ressort d’outils comme **Power Automate** ou **n8n**.  
Orchiviste agit plutôt comme un **moteur documentaire spécialisé**, appelé à l’intérieur de ces flux pour exécuter des traitements avancés sur les documents.

---

## Vision

Dans un environnement municipal moderne, les documents circulent entre plusieurs systèmes :

- Microsoft 365, SharePoint et OneDrive pour le travail courant
- les logiciels métiers
- les GED comme SyGED, Ultima ou un équivalent
- les dossiers papier numérisés
- les espaces de travail temporaires ou techniques

Orchiviste se place **entre les sources documentaires et les systèmes cibles** afin d’améliorer la qualité documentaire en amont.

Son rôle est de transformer des lots hétérogènes en documents :

- analysés
- nommés correctement
- enrichis de métadonnées utiles
- préclassés
- traçables
- prêts pour la revue humaine, le routage ou le versement

---

## Ce qu’Orchiviste est

Orchiviste est un **moteur documentaire spécialisé** pour les besoins archivistiques et administratifs municipaux.

Il sert notamment à :

- analyser des documents numériques ou numérisés
- extraire du texte, des signaux documentaires et des métadonnées
- proposer un nom conforme aux règles de dénomination
- assister le préclassement selon un plan de classification
- détecter les cas ambigus, les anomalies ou les besoins de revue
- préparer le routage vers une arborescence cible ou SharePoint
- conserver une traçabilité des traitements et des décisions

---

## Ce qu’Orchiviste n’est pas

Orchiviste n’est pas :

- un orchestrateur de flux
- un remplacement de Power Automate ou n8n
- une GED complète
- un remplacement direct de SharePoint
- le dépôt officiel final de conservation

En pratique :

- **Power Automate / n8n** pilotent les flux
- **Orchiviste** exécute les traitements documentaires experts
- **SharePoint / OneDrive / M365** servent au travail actif et collaboratif
- **SyGED ou un équivalent** servent à la gouvernance documentaire officielle, au classement, à la conservation et à la gestion intégrée papier/numérique

---

## Valeur apportée

Orchiviste vise à :

- réduire les manipulations manuelles de renommage et de classement
- appliquer des règles métier déclaratives, modifiables sans recoder
- améliorer la cohérence documentaire
- préparer les documents avant leur dépôt final
- soutenir la gouvernance documentaire municipale
- préserver une validation humaine pour les cas sensibles ou ambigus
- favoriser un traitement local sur macOS pour certaines charges d’analyse, d’OCR et d’IA

---

## Flux fonctionnel

Flux général :

`ingestion → aperçu serveur → extraction du contenu et des métadonnées → proposition de nom → enrichissement documentaire → préclassement / routage → revue humaine si nécessaire`

Principe fondamental :

- si le niveau de confiance est insuffisant, Orchiviste ne force pas une décision et place le dossier en **revue humaine**
- la gouvernance documentaire, la validation métier et les décisions finales demeurent sous contrôle humain

---

## Principes documentaires

Orchiviste est conçu autour de principes archivistiques et documentaires clairs :

- un nom de fichier doit être **significatif, précis et concis**
- le nom final ne doit pas contenir de mentions techniques inutiles comme `signé`, `numérisé`, `OCR`, `PDF/A`, `version finale`, sauf exception métier explicite
- les règles doivent être **explicables, auditables et révisables**
- un système documentaire municipal doit rester compatible avec :
  - le plan de classification
  - le calendrier de conservation
  - les exigences de traçabilité
  - la cohabitation papier / numérique
  - les besoins de migration, versement et archivage

---

## Positionnement du projet

Par rapport aux outils OCR, IDP, ECM ou EDMS génériques, Orchiviste cible un besoin plus précis :

**le traitement documentaire municipal en amont du dépôt officiel.**

Le projet est pensé comme une **plateforme documentaire modulaire** pouvant travailler avec d’autres outils spécialisés, notamment :

- MuniRenommage
- MuniConversion
- MuniMiseEnForme
- MuniAnalyse
- MuniMetadonnees
- MuniPreclassement
- MuniControle

Orchiviste peut servir de **cockpit documentaire**, de point d’entrée ou de service expert, sans fusionner tous les dépôts dans un seul système.

---

## Architecture actuelle

Le dépôt est organisé en monorepo Swift Package Manager + Vapor.

### Modules principaux

- **OrchivisteAPI**  
  API Vapor, interface SSR Leaf, preview, presets, jobs, événements, webhooks, routage local et Microsoft Graph

- **OrchivisteAnalyse**  
  service d’analyse sémantique et documentaire

- **OrchivisteWorker**  
  worker CLI macOS / Redis pour OCR et traitements asynchrones

- **OrchivisteSharedKit**  
  DTO et composants partagés

---

## Orientation technique

Le projet est pensé **macOS native-first** pour les traitements documentaires avancés.

Cela permet notamment de tirer parti de l’écosystème Apple Silicon pour certains traitements d’analyse, d’OCR et d’IA locale.

Docker reste utile pour :

- les smokes
- les tests d’intégration
- les démonstrations techniques
- certaines exécutions API

Mais certaines capacités natives demeurent mieux servies par une exécution directe sur macOS.

---

## Capacités visées

Le périmètre visé comprend notamment :

- ingestion locale et SharePoint
- preview serveur sans téléchargement par défaut
- analyse documentaire avec revue humaine en cas d’ambiguïté
- préréglages JSON
- apprentissage depuis un dossier ou un lot de fichiers
- prise en charge des PDF, images et documents Office
- routage local et SharePoint Graph
- journalisation des traitements
- événements, webhooks et métriques
- export et préparation de livrables documentaires

---

## Cas d’usage typiques

Orchiviste est particulièrement pertinent pour des cas comme :

- lots de documents à renommer selon une directive municipale
- documents numérisés à vérifier, normaliser et préparer
- contrats, résolutions, procès-verbaux, appels d’offres et dossiers administratifs
- préparation de documents avant dépôt dans SharePoint ou SyGED
- contrôle qualité documentaire avant versement ou migration
- enrichissement de lots hétérogènes avant réorganisation archivistique

---

## Méthodologie de développement

Le projet est développé avec une approche pilotée par le besoin métier archivistique.

Principes de développement :

- conception modulaire
- validation humaine des décisions importantes
- logique explicable plutôt que boîte noire opaque
- compatibilité avec les pratiques réelles du greffe et des archives
- intégration avec les outils existants plutôt que remplacement brutal
- développement assisté par IA sous supervision humaine

---

## Démarrage rapide

### Local

```bash
cd OrchivisteAnalyse
swift build -c debug --product OrchivisteAnalyse

cd ../OrchivisteAPI
swift build -c debug --product OrchivisteAPI

cd ..
./scripts/preflight_local.sh --full
```

### Docker

```bash
docker compose up -d --build redis analyse api
./scripts/check_openapi_mvp.sh
./scripts/smoke_mvp.sh
```

Pour utiliser les capacités natives Apple, lancer `OrchivisteAnalyse` directement sur macOS plutôt que dans le conteneur `analyse`.

---

## Démo macOS

Dossier recommandé :

```text
/Volumes/MAC_HDD/Logiciel test/Orchiviste-demo-macOS
```

Construire / mettre à jour la démo :

```bash
./scripts/build_native_demo_bundle.sh "/Volumes/MAC_HDD/Logiciel test/Orchiviste-demo-macOS"
```

Démarrer :

```bash
"/Volumes/MAC_HDD/Logiciel test/Orchiviste-demo-macOS/start-orchiviste.sh"
```

Arrêter :

```bash
"/Volumes/MAC_HDD/Logiciel test/Orchiviste-demo-macOS/stop-orchiviste.sh"
```

Interface :

- `http://127.0.0.1:28780/ui`
- `http://127.0.0.1:28780/u`

---

## Documentation

- `OrchivisteAPI/README.md`
- `OrchivisteAnalyse/README.md`
- `deploy/mac-mini/README.md`
- `ROADMAP.md`
- `ml/IMPLEMENTATION_PLAN.md`

---

## Feuille de route

Les prochaines étapes du projet visent notamment à renforcer :

- l’analyse sémantique
- l’assistance au classement et au repérage
- les métadonnées
- les règles déclaratives
- la revue humaine
- l’intégration aux environnements documentaires municipaux
- les utilitaires spécialisés de l’écosystème Muni

---

## Licence

Ce projet est distribué sous licence **GNU GPL v3.0**.  
Voir le fichier `LICENSE`.

---

## Résumé

**Orchiviste est un moteur documentaire municipal spécialisé.**  
Il aide à préparer les documents avant leur classement, leur conservation, leur routage ou leur versement.  
Il ne remplace ni les outils d’orchestration, ni les dépôts documentaires officiels : il les complète.

