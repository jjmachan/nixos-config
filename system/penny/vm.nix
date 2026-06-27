# Penny guest — the NixOS config that runs inside the penny-vm MicroVM.
#
# Runs hermes-agent in *container mode*: hermes executes inside an OCI
# (docker) container that gives Penny a writable Ubuntu userland to
# self-install tools, while the MicroVM contains the blast radius.
#
# Persistence: the MicroVM root FS is read-only/ephemeral. Everything that
# must survive a reboot lives on the /persist virtiofs share — hermes state
# (HERMES_HOME) AND docker's data-root (the container's writable layer).
{ config, pkgs, lib, inputs, ... }:

{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  networking.hostName = "penny-vm";

  # --- MicroVM hardware ---
  microvm = {
    hypervisor = "qemu";
    vcpu = 4;
    mem = 8192;

    interfaces = [{
      type = "tap";
      id = "vm-penny";
      mac = "02:00:00:00:00:02";
    }];

    shares = [
      {
        # Share the host's nix store (read-only) to keep the image small.
        proto = "virtiofs";
        tag = "ro-store";
        source = "/nix/store";
        mountPoint = "/nix/.ro-store";
      }
      {
        # Persistent state: hermes HOME + docker data-root live under here.
        proto = "virtiofs";
        tag = "persist";
        source = "/var/lib/penny/persist";
        mountPoint = "/persist";
      }
      {
        # Read-only secrets (penny.env): OAuth + Slack tokens.
        proto = "virtiofs";
        tag = "secrets";
        source = "/var/lib/penny/secrets";
        mountPoint = "/secrets";
        readOnly = true;
      }
    ];

    volumes = [
      {
        # Writable overlay for the nix store (needed by NixOS inside the VM).
        image = "nix-store-overlay.img";
        mountPoint = "/nix/.rw-store";
        size = 20480;
        autoCreate = true;
      }
      {
        # Dedicated ext4 volume for docker's data-root. docker's overlay2
        # driver needs a real fs (ext4) — it does NOT work on virtiofs — and
        # this image persists the container's writable layer across reboots.
        image = "penny-docker.img";
        mountPoint = "/var/lib/docker";
        fsType = "ext4";
        size = 30720;
        autoCreate = true;
      }
    ];
    writableStoreOverlay = "/nix/.rw-store";
  };

  # --- Network: static on the isolated bridge, NAT egress via the host ---
  systemd.network.enable = true;
  systemd.network.networks."10-eth" = {
    matchConfig.Type = "ether";
    addresses = [{ Address = "192.168.101.2/24"; }];
    routes = [{ Gateway = "192.168.101.1"; }];
    networkConfig.DNS = [ "1.1.1.1" "8.8.8.8" ];
  };

  # --- Docker for hermes container mode ---
  # data-root is the default /var/lib/docker, backed by the dedicated ext4
  # volume above so the container's writable layer survives reboots.
  virtualisation.docker.enable = true;

  # --- Penny (hermes-agent) ---
  services.hermes-agent = {
    enable = true;
    container.enable = true;
    container.backend = "docker";
    stateDir = "/persist/hermes";          # HERMES_HOME (.hermes/) + workspace
    environmentFiles = [ "/secrets/penny.env" ];
    # Slim build: just Slack (messaging) + Anthropic instead of the full
    # package (which pulls voice/tts/matrix/etc). Trims build time & surface.
    package = inputs.hermes-agent.packages.x86_64-linux.minimal;
    extraDependencyGroups = [ "messaging" "anthropic" ];
    settings = {
      # Opus 4.8 via Anthropic subscription OAuth (CLAUDE_CODE_OAUTH_TOKEN in
      # penny.env is auto-detected and routed "as Claude Code").
      # NOTE: confirm the exact model id with `hermes model` after first boot.
      model = "anthropic/claude-opus-4.8";
      terminal.backend = "local";          # tools run inside the container
    };
  };

  # --- SSH for first-run/debug, key-only, reachable only on br-penny ---
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDR8XpEeYELI+E4Kip6JV4V3Bh7vpv812kXX4eTPb+XA jamesjithin97@gmail.com"
  ];

  # Handy tools for poking around the VM (hermes provisions its own in-container).
  environment.systemPackages = with pkgs; [ git ripgrep ffmpeg curl jq ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11";
}
