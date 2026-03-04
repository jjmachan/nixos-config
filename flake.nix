{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-openclaw.url = "github:openclaw/nix-openclaw";
    suika = {
      url = "path:/home/jjmachan/suika-module";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, nix-openclaw, suika }: {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      modules = [
        # Import the previous configuration.nix we used,
        # so the old configuration file still takes effect
        ./system/configuration.nix
        {
          nixpkgs.overlays = [ nix-openclaw.overlays.default ];
        }
        home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "hm-backup-2";

            home-manager.users.jjmachan = {
              home.stateVersion = "25.11";
              imports = [
                ./home.nix
                nix-openclaw.homeManagerModules.openclaw
              ];
            };
          }
        suika.nixosModules.default
      ];
    };
  };
}
