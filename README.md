# Apprendys

**Un ordinateur bienveillant pour les enfants — et adultes — DYS, TDAH, TSA.**

Apprendys transforme un PC (même ancien) en un environnement épuré, hors-ligne et
sans distraction, taillé pour les troubles « dys ». Lecture à voix haute, dictée
vocale, police adaptée, couleurs syllabiques, et une interface qu'on choisit selon
son style — le tout sur une base **NixOS** déclarative, reproductible et qui se met
à jour toute seule (avec retour arrière automatique en cas de pépin).

> Projet de **CF-Informatik974** — La Réunion. Site : [apprendys.re](https://apprendys.re)

## Ce que ça fait

- 🔊 **Lis-moi** — lecture à voix haute du texte sélectionné (Piper, voix FR naturelle, offline)
- 🎙️ **Le Perroquet** — dictée vocale offline (Vosk)
- 🎨 **3 styles** au choix (Mignon / Classique / Monochrome) qui changent toute l'ambiance
- 📖 **LireCouleur** dans LibreOffice — colorisation syllabes/sons
- 🔠 Police **Luciole** (conçue pour les DYS) ou OpenDyslexic, taille et curseur réglables
- 🧰 **Mon Apprendys** — appli de réglages + espace parent (PIN) + mises à jour
- 📝 **Mes Devoirs** — Xournal++, sauvegarde automatique
- 🌐 Navigation filtrée (uBlock, pas de pub, pas de recommandations toxiques)

## Le produit

Une **clé USB installateur 3 clics** : on branche, on clique « Installer Apprendys »,
le vieux PC du placard devient l'ordinateur dédié de l'enfant. ~20 min, 100 % hors-ligne.

## Construire

```bash
# ISO installateur (le produit)
nix build .#apprendys-installer-iso

# ISO live (sans installation)
nix build .#apprendys-light-iso

# Système installé (pour inspection / VM)
nix build .#nixosConfigurations.apprendys-installed.config.system.build.toplevel
```

Flasher : `sudo dd if=result/iso/*.iso of=/dev/sdX bs=4M status=progress oflag=sync`

## Architecture

| Dossier | Rôle |
|---|---|
| `flake.nix` | sorties ISO + configs NixOS |
| `profiles/` | `installed` (PC dédié), `light`, `pro`, `ecole` |
| `modules/` | base, apps, accessibilité, installateur, OTA, quirks matériel |
| `packages/` | apprendys-tts, apprendys-stt, session-init, **apprendys-app**, installateur |
| `home/` | session XFCE (icônes, bureau, raccourcis) |

## Licence

Code propriétaire — © CF-Informatik974. Tous droits réservés.
