# Documentation Apprendys OS

Doc technique pour **reprendre la main à tout moment** sur le système. À lire dans cet ordre :

| Doc | Quand l'ouvrir |
|---|---|
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | Le **modèle mental**. Tu reviens après des mois → commence ici. Le flake, profils vs modules vs packages, le flux de boot, l'OTA, les priorités NixOS, les optimisations clé USB. |
| **[OPERATIONS.md](OPERATIONS.md)** | Le **runbook** : build chaque ISO, flasher, tester en VM, **pousser une MAJ OTA au parc**, rollback, debug, checklist « avant de livrer une clé ». |
| **[MODULES.md](MODULES.md)** | La **référence fichier par fichier** : chaque module/package, son rôle, ses pièges, et ce qu'il ne faut PAS casser. |

> `superpowers/plans/` = historique de construction (plans + preuves de boot), pas de la doc de référence.

## Réflexes essentiels (le condensé)

- **Le produit** = `nix build .#apprendys-installer-iso` → clé installateur 3-clics, 100 % offline.
- **Mettre à jour tout le parc** = `git push origin main` (l'OTA des machines va chercher `main`).
  → **Toujours** `nix build .#nixosConfigurations.apprendys-installed…toplevel` AVANT de pousser.
- **Itérer vite** = VM de dev `sudo nixos-rebuild switch --flake .#apprendys-dev`.
- **Ne jamais livrer** l'ISO `…-sshtest` (SSH ouvert). L'ISO livrée a `release.nix` (tout fermé).
- **Repo public** : aucun secret dedans.
