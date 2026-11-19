{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-26.05";
    claude-code.url = "github:sadjow/claude-code-nix";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    worktrunk = {
      url = "github:max-sixty/worktrunk";
    };
    # herdr — terminal workspace manager for AI coding agents (not in nixpkgs).
    # Follows ours: 26.05 ships the zig 0.16 its build needs (rust comes from
    # its own rust-overlay pin).
    herdr = {
      url = "github:herdrdev/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # MicroVM host for the agents (Penny).
    microvm = {
      url = "github:astro/microvm.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Hermes-agent provides its own NixOS module + uv2nix package.
    # Keep its own nixpkgs (uv2nix targets nixpkgs-unstable) — do NOT follow ours.
    hermes-agent.url = "github:NousResearch/hermes-agent";
    # Rex — the nixbox's personal Rex server (docs/rex.md). The preview channel,
    # like the Mac app; flake.lock pins the exact release. A prebuilt binary that
    # nixpkgs only patches against its glibc, so ours does.
    rex = {
      url = "https://pkgs.superlogical.com/rex/nix/preview.tar.gz";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, claude-code, home-manager, worktrunk, herdr, microvm, hermes-agent, rex }:
  let
    # Overlay to use claude-code from sadjow/claude-code-nix (new releases land
    # when we update the claude-code input; see docs/updating.md)
    claude-code-overlay = claude-code.overlays.default;

    # Our own packages (pkgs/), added to pkgs like any nixpkgs package.
    local-overlay = final: prev: {
      herdr-core = final.callPackage ./pkgs/herdr-core { };
    };

    # Standalone home-manager (the Mac, other Linux boxes) has no NixOS to hand
    # it pkgs, so build one per system with the same overlay and unfree setting.
    pkgsFor = system: import nixpkgs {
      inherit system;
      overlays = [ claude-code-overlay local-overlay ];
      config.allowUnfree = true;
    };

    mkHome = system: module: home-manager.lib.homeManagerConfiguration {
      pkgs = pkgsFor system;
      extraSpecialArgs = { inherit inputs; };
      modules = [ module ];
    };

    # The dev module's packages plus the programs it configures, as one bundle
    # for boxes that should get the tools without a home-manager takeover:
    #   nix shell github:jjmachan/nixos-config#dev-tools
    devTools = system: let
      pkgs = pkgsFor system;
      herdr' = herdr.packages.${system}.default;
    in pkgs.buildEnv {
      name = "dev-tools";
      paths = import ./modules/home/dev/packages.nix pkgs herdr' ++ (with pkgs; [
        neovim zellij zsh fzf direnv gh git nh
        worktrunk.packages.${system}.default
      ]);
    };

    nixbox = nixpkgs.lib.nixosSystem {
      # Expose flake inputs to modules (the agents need microvm + hermes-agent).
      specialArgs = { inherit inputs; };
      modules = [
        ./hosts/nixbox/configuration.nix
        {
          nixpkgs.overlays = [ claude-code-overlay local-overlay ];
        }
        home-manager.nixosModules.home-manager {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.backupFileExtension = "hm-backup-2";
            home-manager.extraSpecialArgs = { inherit inputs; };

            home-manager.users.jjmachan = ./hosts/nixbox/home.nix;
          }
        ./hosts/nixbox/agents
      ];
    };

  in {
    # nh and nixos-rebuild pick the output named after the hostname.
    nixosConfigurations = { inherit nixbox; };

    homeConfigurations = {
      "jjmachan@macbook" = mkHome "aarch64-darwin" ./hosts/macbook/home.nix;
      "jjmachan@linux" = mkHome "x86_64-linux" ./hosts/linux/home.nix;
    };

    packages = nixpkgs.lib.genAttrs [ "aarch64-darwin" "x86_64-linux" ] (system: {
      dev-tools = devTools system;
      # Build one package on its own: nix build .#herdr-core
      herdr-core = (pkgsFor system).herdr-core;
    });
  };
}
