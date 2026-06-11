{ config, pkgs, lib, ... }: {
  # ISO de production : pas de porte d'entrée.
  # mkOverride 40 : priorité PLUS HAUTE que mkForce (50) de profiles/light.nix.
  # Rappel : numéro plus petit = priorité plus haute (mkForce=50, mkDefault=1000).

  # SSH désactivé — light.nix l'active en mkForce true (50), on écrase.
  services.openssh.enable = lib.mkOverride 40 false;

  # wheelNeedsPassword : light.nix met false (prio 100), on force true.
  # installer.nix utilise une règle NOPASSWD par user+commande (pas par wheel)
  # → cette restriction ne casse PAS l'auto-élévation de l'installateur.
  security.sudo.wheelNeedsPassword = lib.mkOverride 40 true;

  # Clé debug Florent retirée — base.nix la définit à prio 100.
  users.users.apprendys.openssh.authorizedKeys.keys = lib.mkOverride 40 [ ];

  # Retirer wheel du live ISO — light.nix ajoute "wheel" (prio 100) à la liste de base.nix.
  # Avec wheelNeedsPassword=true et le mot de passe connu "apprendys", laisser wheel
  # serait une faiblesse inutile sur l'ISO expédiée.
  # L'installateur utilise sudo via règle NOPASSWD (user+commande), pas via wheel.
  # On surclasse les deux définitions (base.nix prio 100, light.nix prio 100) avec prio 40.
  users.users.apprendys.extraGroups = lib.mkOverride 40 [
    "audio" "video" "networkmanager" "plugdev" "lp"
  ];
}
