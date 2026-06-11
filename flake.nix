{
  description = "Apprendys V2 — NixOS live USB pour enfants DYS — CF-Informatik974";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence.url = "github:nix-community/impermanence";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, impermanence, nixos-generators }:
  let
    system = "x86_64-linux";

    # Modules communs à toutes les variantes (ISO, VM, etc.)
    commonModules = [
      ./modules/base.nix
      ./modules/apps.nix
      ./modules/accessibility.nix
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.users.apprendys = import ./home/apprendys.nix;
      }
    ];

    # Modules spécifiques aux builds USB live (SquashFS + persistence sur P4)
    # NB : hardware/usb-key.nix, persistence.nix et gnuramage.nix nécessitent /mnt/apprendys
    # → réservés au flash physique, pas pour le format ISO live (qui gère son propre fs)
    usbModules = [
      impermanence.nixosModules.impermanence
      # ./modules/persistence.nix    # à réintégrer après refonte hardware
      # ./modules/gnuramage.nix      # à réintégrer après refonte userland
    ];

    # Génère une ISO live (SquashFS demand-paged) pour un canal donné
    mkApprendysIso = { profile, extraModules ? [] }:
      nixos-generators.nixosGenerate {
        inherit system;
        format = "iso";
        modules = commonModules ++ usbModules ++ [ profile ] ++ extraModules;
      };

  in {
    # ──────────────────────────────────────────────────────────────────
    # Sorties ISO — flashables sur clé USB via dd
    # Build : nix build .#apprendys-light-iso
    # Résultat : result/iso/nixos.iso (SquashFS demand-paged)
    # ──────────────────────────────────────────────────────────────────
    packages.${system} = {
      # Clé standard — vieux PC, Vosk small, ≥4Go RAM
      apprendys-light-iso = mkApprendysIso {
        profile = ./profiles/light.nix;
      };

      # Clé pro — PC récent, Whisper small, ≥8Go RAM
      apprendys-pro-iso = mkApprendysIso {
        profile = ./profiles/pro.nix;
      };

      # Clé école — proxy + restrictions
      apprendys-ecole-iso = mkApprendysIso {
        profile = ./profiles/light.nix;
        extraModules = [ ./modules/school.nix ];
      };

      # ISO installeur — LE produit du Masterplan V3 (clé 79 €)
      # Embarque la closure de apprendys-installed → nixos-install 100 % offline.
      apprendys-installer-iso = nixos-generators.nixosGenerate {
        inherit system;
        format = "iso";
        specialArgs = {
          installedSystem =
            self.nixosConfigurations.apprendys-installed.config.system.build.toplevel;
        };
        modules = commonModules ++ usbModules ++ [
          ./profiles/light.nix
          ./modules/installer.nix
          ./modules/release.nix
        ];
      };

      # Alias par défaut (pour `nix build` sans cible)
      default = mkApprendysIso { profile = ./profiles/light.nix; };
    };

    # ──────────────────────────────────────────────────────────────────
    # VM de développement — installation NixOS classique sur disque virtuel
    # Build/run : nixos-rebuild switch --flake .#apprendys-dev
    # Pas d'ISO ici — c'est une VM normale qu'on rebuild en place
    # ──────────────────────────────────────────────────────────────────
    nixosConfigurations = {
      apprendys-dev = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = commonModules ++ [
          ./modules/dev-vm.nix
          ./hardware/dev-vm.nix
        ];
      };

      # Système installé sur PC dédié — cible de l'installateur 3-clics (Masterplan V3)
      apprendys-installed = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = commonModules ++ [ ./profiles/installed.nix ];
      };
    };
  };
}
