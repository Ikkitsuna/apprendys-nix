{ config, pkgs, lib, ... }: {
  # Module impermanence — remplace gnuramage + mount-partitions.sh de V1
  # P4 (APPRENDYS, ext4) est monté sur /mnt/apprendys
  # Tout ce qui est déclaré ici survit entre les boots
  # Tout le reste est effacé (tmpfs sur /)

  environment.persistence."/mnt/apprendys/persist" = {
    directories = [
      # Home complet (bind-mount depuis P4, même logique V1)
      "/home/apprendys"

      # Réseau WiFi (remplace gnuramage whitelist nm-connections)
      "/etc/NetworkManager/system-connections"

      # Bluetooth (remplace gnuramage whitelist bluetooth)
      "/var/lib/bluetooth"

      # Machine ID stable (pour NM et systemd)
      # Note : fichier, pas directory
    ];
    files = [
      "/etc/machine-id"
    ];
  };
}
