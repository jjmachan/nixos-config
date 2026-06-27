{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    claude-code.url = "github:sadjow/claude-code-nix";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    suika = {
      url = "path:/home/jjmachan/workspace/personal/suika-module";
      inputs.nixpkgs.follows = "nixpkgs";
      # Share ONE microvm instance with Penny so microvm.nixosModules.host
      # is imported once (module-system dedup) — no double-import conflict.
      inputs.microvm.follows = "microvm";
    };
    worktrunk = {
      url = "github:max-sixty/worktrunk";
    };
    # MicroVM host for Penny (Penny owns this import; suika follows it above).
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Hermes-agent provides its own NixOS module + uv2nix package.
    # Keep its own nixpkgs (uv2nix targets nixpkgs-unstable) — do NOT follow ours.
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  outputs = inputs@{ self, nixpkgs, claude-code, home-manager, suika, worktrunk, microvm, hermes-agent }:
  let
    system = "x86_64-linux";

    # Overlay to use claude-code from sadjow/claude-code-nix (hourly updates)
    claude-code-overlay = claude-code.overlays.default;
  in {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      # Expose flake inputs to modules (Penny needs microvm + hermes-agent).
      specialArgs = { inherit inputs; };
      modules = [
        ./system/configuration.nix
        {
          nixpkgs.overlays = [ claude-code-overlay ];
        }
        home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "hm-backup-2";

            home-manager.users.jjmachan = {
              home.stateVersion = "25.11";
              imports = [
                ./home.nix
                worktrunk.homeModules.default
              ];
            };
          }
        suika.nixosModules.default
        ./system/penny/host.nix
      ];
    };
  };
}
