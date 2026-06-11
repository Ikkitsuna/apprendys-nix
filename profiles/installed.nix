{ config, pkgs, lib, ... }: {
  # Apprendys installé sur PC dédié (le « vieux PC du placard »)
  imports = [ ../modules/hardware-quirks.nix ../modules/ota-installed.nix ];

  networking.hostName = "apprendys";

  # L'installateur (apprendys-installer) crée ces labels — montage générique,
  # aucun UUID machine-spécifique.
  fileSystems."/" = { device = "/dev/disk/by-label/APPRENDYS"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/APPR-EFI"; fsType = "vfat"; };

  boot.loader.grub = {
    enable = true;
    device = "nodev";              # legacy BIOS : grub-install manuel par l'installateur
    efiSupport = true;
    efiInstallAsRemovable = true;  # pas d'écriture NVRAM (vieux UEFI fragiles)
    configurationLimit = 5;        # rollback OTA : 5 générations au menu
  };
  boot.loader.efi.canTouchEfiVariables = false;

  # Couverture initrd large — vieux portables hardware inconnu à l'avance
  # (SATA, NVMe, USB legacy, contrôleurs SCSI-like des ères 2005-2015)
  boot.initrd.availableKernelModules = [
    "ahci" "sd_mod" "sr_mod" "nvme" "xhci_pci" "ehci_pci" "uhci_hcd" "usb_storage" "usbhid" "ata_piix" "isci"
  ];

  # WiFi des vieux portables (Intel iwlwifi, Realtek rtl8xxxu, Broadcom b43 open)
  # Critique produit : la WiFi est souvent le seul réseau disponible sur les vieux PC
  hardware.enableRedistributableFirmware = true;

  # Disque interne : logs persistants utiles au SAV (base.nix les met en RAM pour la clé)
  services.journald.extraConfig = lib.mkForce ''
    Storage=auto
    SystemMaxUse=200M
  '';

  environment.variables.APPRENDYS_PROFILE = "installed";

  # Prod : SSH off, sudo off (défauts base.nix — ne PAS importer light.nix qui les force)
}
