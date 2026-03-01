# Déploiement Mac mini

Ce dossier fournit un socle simple pour une démo ou un MVP hébergé sur Mac mini.

## Fichiers

- `orchiviste.macmini.env.example` : variables d'environnement à copier dans `orchiviste.macmini.env`
- `Caddyfile.example` : reverse proxy TLS minimal pour exposer l'API

## Mise en route

1. Copier `deploy/mac-mini/orchiviste.macmini.env.example` vers `deploy/mac-mini/orchiviste.macmini.env`
2. Ajuster les secrets, les URLs webhook et les identifiants Graph si requis
3. Démarrer la stack :
   `./scripts/macmini_demo_up.sh --build`
4. Vérifier :
   `./scripts/check_openapi_mvp.sh`
   `./scripts/smoke_mvp.sh`

## Sauvegarde

- lancer `./scripts/macmini_backup.sh`
- le backup contient les configs, l'env Mac mini, les répertoires runtime et le volume SQLite Docker si présent

## Reverse proxy

Copier `deploy/mac-mini/Caddyfile.example` vers `deploy/mac-mini/Caddyfile`, adapter le domaine, puis lancer Caddy sur la machine hôte.
