{ config, pkgs, lib, ... }: {
  # VM de développement ApprendysV2-Dev (10.1.0.26)
  # Diffère de la prod : SSH activé, user florent, qemu-guest-agent

  networking.hostName = "apprendys-dev";

  # SSH activé pour dev
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;
      PermitRootLogin = "yes";
    };
  };

  # QEMU guest agent pour Proxmox
  services.qemuGuest.enable = true;

  # Bootloader pour VM EFI
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 5;

  # Sudo pour dev (florent = admin)
  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  # User florent pour le dev (en plus d'apprendys)
  users.users.florent = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "audio" "video" ];
    hashedPassword = "$6$crjaOeenOX1WFwZk$UcX/YkjV6qAJ2Cz4caE/pvCU9TQr6ktAKV10QBG3x.kq/9z.7x52c/ncspA8LO5bXZZNmTe0fKd5XthdPdhMp1";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINTm9zyJh4iYkeiNEIiUx7v/twH0e8IyTpz9DjwQRzCs florent@ArchWork"
    ];
  };

  # Paquets dev supplémentaires
  environment.systemPackages = with pkgs; [
    git vim curl wget
    htop tree file lsof
    python3
    nix-tree     # explorer le store Nix
  ];

  # Nix — trusted-users pour dev
  nix.settings.trusted-users = lib.mkForce [ "root" "florent" ];
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
}
