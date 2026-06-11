{ config, pkgs, lib, ... }: {
  # Module école — proxy réseau, DNS interne, canal MAJ école
  # À configurer selon l'établissement scolaire

  # Proxy HTTP (à définir par école)
  # networking.proxy.default = "http://proxy.ecole.re:3128";
  # networking.proxy.noProxy = "127.0.0.1,localhost,.local";

  # Canal MAJ école (branche git séparée)
  environment.variables.APPRENDYS_CHANNEL = "ecole";

  # DNS interne (si réseau école avec filtrage)
  # networking.nameservers = [ "10.0.0.1" "8.8.8.8" ];
}
