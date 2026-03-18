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
      url = "path:/home/jjmachan/suika-module";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    worktrunk = {
      url = "github:max-sixty/worktrunk";
    };
  };

  outputs = { self, nixpkgs, claude-code, home-manager, suika, worktrunk }:
  let
    system = "x86_64-linux";

    # Overlay to use claude-code from sadjow/claude-code-nix (hourly updates)
    claude-code-overlay = claude-code.overlays.default;
  in {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
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
      ];
    };
  };
}
