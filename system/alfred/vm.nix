# Alfred guest — the NixOS config that runs inside the alfred-vm MicroVM.
#
# Runs hermes-agent in *container mode*: hermes executes inside an OCI
# (docker) container that gives Alfred a writable Ubuntu userland to
# self-install tools, while the MicroVM contains the blast radius.
#
# Persistence: the MicroVM root FS is read-only/ephemeral. Everything that
# must survive a reboot lives on the /persist virtiofs share — hermes state
# (HERMES_HOME) AND docker's data-root (the container's writable layer).
{ config, pkgs, lib, inputs, ... }:

{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  networking.hostName = "alfred-vm";

  # --- MicroVM hardware ---
  microvm = {
    hypervisor = "qemu";
    vcpu = 4;
    mem = 8192;

    interfaces = [{
      type = "tap";
      # Unique, non-glob-matchable tap name (see host.nix).
      id = "tap-alfred";
      mac = "02:00:00:00:00:03";
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
        source = "/var/lib/alfred/persist";
        mountPoint = "/persist";
      }
      {
        # Read-only secrets (alfred.env): Slack tokens.
        proto = "virtiofs";
        tag = "secrets";
        source = "/var/lib/alfred/secrets";
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
        image = "alfred-docker.img";
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
    addresses = [{ Address = "192.168.102.2/24"; }];
    routes = [{ Gateway = "192.168.102.1"; }];
    networkConfig.DNS = [ "1.1.1.1" "8.8.8.8" ];
  };

  # --- Docker for hermes container mode ---
  # data-root is the default /var/lib/docker, backed by the dedicated ext4
  # volume above so the container's writable layer survives reboots.
  virtualisation.docker.enable = true;

  # --- Alfred (hermes-agent) ---
  services.hermes-agent = {
    enable = true;
    container.enable = true;
    container.backend = "docker";
    stateDir = "/persist/hermes";          # HERMES_HOME (.hermes/) + workspace
    environmentFiles = [ "/secrets/alfred.env" ];
    # Slim build: Slack lives in the "messaging" group; no other groups needed.
    package = inputs.hermes-agent.packages.x86_64-linux.minimal;
    extraDependencyGroups = [ "messaging" ];
    settings = {
      # GPT-5.6 Sol via the openai-codex provider, authed with the ChatGPT Pro
      # subscription (one-time device-code login → auth.json on /persist).
      model = "openai-codex/gpt-5.6-sol";
      terminal.backend = "local";          # tools run inside the container
      # Pin the compaction threshold explicitly: hermes' codex "autoraise"
      # (50%→85% for capped-context codex models) posts an FYI notice into the
      # chat every time it kicks in; an explicit value keeps the 85% behavior
      # without the auto-raise or its notice.
      compression.threshold = 0.85;
    };
  };

  # The hermes module seeds HERMES_HOME/.env from environmentFiles at NixOS
  # *activation* time, but in a MicroVM that races the virtiofs /persist +
  # /secrets mounts (HERMES_HOME doesn't exist yet), so the secrets silently
  # fail to land and the gateway starts with no tokens. Re-seed deterministically
  # after the mounts and before hermes starts.
  systemd.services.alfred-hermes-env = {
    description = "Seed Alfred hermes .env from /secrets (after virtiofs mounts)";
    before = [ "hermes-agent.service" ];
    wantedBy = [ "hermes-agent.service" ];
    unitConfig.RequiresMountsFor = "/persist /secrets";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      install -d -o hermes -g hermes -m 2770 /persist/hermes/.hermes

      # .env — always re-seed from the read-only secrets mount.
      env_file=/persist/hermes/.hermes/.env
      install -o hermes -g hermes -m 0640 /dev/null "$env_file"
      if [ -f /secrets/alfred.env ]; then
        cat /secrets/alfred.env >> "$env_file"
      fi

      # config.yaml — the module's activation merge also races the mounts, so
      # the declared model never lands. Write the canonical config when the
      # model is wrong/missing (preserves hermes' runtime keys once correct).
      cfg=/persist/hermes/.hermes/config.yaml
      if ! grep -q '^model: openai-codex/gpt-5.6-sol$' "$cfg" 2>/dev/null; then
        cat > "$cfg" <<'YAML'
model: openai-codex/gpt-5.6-sol
terminal:
  backend: local
compression:
  threshold: 0.85
YAML
        chown hermes:hermes "$cfg"
        chmod 0640 "$cfg"
      fi
    '';
  };

  # --- SSH for first-run/debug, key-only, reachable only on br-alfred ---
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    settings.PermitRootLogin = "prohibit-password";
  };
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDR8XpEeYELI+E4Kip6JV4V3Bh7vpv812kXX4eTPb+XA jamesjithin97@gmail.com"
  ];

  # Handy tools for poking around the VM (hermes provisions its own in-container).
  environment.systemPackages = with pkgs; [ git ripgrep curl jq ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  system.stateVersion = "25.11";
}
