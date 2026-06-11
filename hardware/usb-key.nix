{ config, pkgs, lib, modulesPath, ... }: {
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Layout partitions clé USB Apprendys (identique V1)
  # P1 : BIOS Boot (1Mo)
  # P2 : APPR-BOOT (1Go, FAT32) — EFI
  # P3 : APPRENDYS-OS (6Go, ext4) — Nix store
  # P4 : APPRENDYS (15Go, ext4, LABEL=APPRENDYS) — persistance
  # P5 : DEVOIRS (reste, NTFS, LABEL=DEVOIRS) — devoirs enfant

  fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    options = [ "defaults" "size=2G" "mode=755" ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-label/APPRENDYS-OS";
    fsType = "ext4";
    options = [ "ro" "noatime" ];
  };

  fileSystems."/mnt/apprendys" = {
    device = "/dev/disk/by-label/APPRENDYS";
    fsType = "ext4";
    options = [ "noatime" "nofail" ];
  };

  fileSystems."/mnt/devoirs" = {
    device = "/dev/disk/by-label/DEVOIRS";
    fsType = "ntfs";
    options = [ "uid=1000" "gid=100" "dmask=007" "fmask=117" "nofail" "x-systemd.automount" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/APPR-BOOT";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-intel" "kvm-amd" ];

  # Kernel params identiques V1
  boot.kernelParams = [ "quiet" "splash" "loglevel=0" "systemd.show_status=0" ];

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
