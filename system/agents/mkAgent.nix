# mkAgent — factory for a hermes-agent assistant in an isolated MicroVM.
# Takes an agent spec and returns a NixOS host module: the declarative VM
# (guest config inlined), an isolated bridge with NAT egress, firewall
# isolation, and the host-side state + secrets directories.
#
# Every derived name (VM, bridge, tap, dirs, volume images, seeder unit) comes
# from `name`. NEVER rename an existing agent: the VM name keys the microvm
# state dir /var/lib/microvms/<name>-vm/ where its disks live — a rename means
# fresh disks and lost docker/store state.
#
# Network model: each VM sits on its own host-only bridge (192.168.<octet>.0/24,
# host .1, guest .2) with NAT to the internet. It is NOT on the LAN or Tailscale
# and exposes no inbound ports — Slack (Socket Mode) and Telegram (long-polling)
# are outbound-only.
{
  name,
  subnetOctet,                 # 192.168.<subnetOctet>.0/24
  mac,
  vcpu ? 4,
  mem ? 8192,
  homeChannelVar ? null,       # e.g. "TELEGRAM_HOME_CHANNEL"; with
  homeChannelDefault ? null,   # ..a default value, seeded only when unset
  extraDependencyGroups ? [ "messaging" ],
  extraPackages ? (pkgs: [ ]), # appended to the base [ git ripgrep curl jq ]
  soulFile ? null,             # checked-in soul.md, seeded ONCE to SOUL.md
  model ? "openai-codex/gpt-5.6-sol",
}:

let
  vmName = "${name}-vm";
  bridge = "br-${name}";
  tap = "tap-${name}";
  subnet = "192.168.${builtins.toString subnetOctet}";
  hostAddr = "${subnet}.1";
  guestAddr = "${subnet}.2";
  varLib = "/var/lib/${name}";
in
{ inputs, lib, ... }:

{
  # Host-side persistent state + read-only secrets for the agent.
  # secrets/ is provisioned by hand (<name>.env) and never committed.
  systemd.tmpfiles.rules = [
    "d ${varLib} 0755 root root -"
    "d ${varLib}/persist 0755 root root -"
    "d ${varLib}/secrets 0700 root root -"
  ];

  # Declarative MicroVM, built and deployed with the host.
  #
  # Guest config: runs hermes-agent in *container mode* — hermes executes
  # inside an OCI (docker) container that gives the agent a writable Ubuntu
  # userland to self-install tools, while the MicroVM contains the blast
  # radius. The MicroVM root FS is read-only/ephemeral; everything that must
  # survive a reboot lives on the /persist virtiofs share — hermes state
  # (HERMES_HOME) AND docker's data-root (the container's writable layer).
  microvm.vms.${vmName} = {
    specialArgs = { inherit inputs; };
    config = { config, pkgs, lib, inputs, ... }: {
      imports = [ inputs.hermes-agent.nixosModules.default ];

      networking.hostName = vmName;

      # --- MicroVM hardware ---
      microvm = {
        hypervisor = "qemu";
        inherit vcpu mem;

        interfaces = [{
          type = "tap";
          # Taps need globally unique, non-glob-matchable names (tap-<name>)
          # so no other agent's networkd rule steals them.
          id = tap;
          inherit mac;
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
            source = "${varLib}/persist";
            mountPoint = "/persist";
          }
          {
            # Read-only secrets (<name>.env): messaging tokens + allowlists.
            proto = "virtiofs";
            tag = "secrets";
            source = "${varLib}/secrets";
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
            image = "${name}-docker.img";
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
        addresses = [{ Address = "${guestAddr}/24"; }];
        routes = [{ Gateway = hostAddr; }];
        networkConfig.DNS = [ "1.1.1.1" "8.8.8.8" ];
      };

      # --- Docker for hermes container mode ---
      # data-root is the default /var/lib/docker, backed by the dedicated ext4
      # volume above so the container's writable layer survives reboots.
      virtualisation.docker.enable = true;

      # --- hermes-agent ---
      services.hermes-agent = {
        enable = true;
        container.enable = true;
        container.backend = "docker";
        stateDir = "/persist/hermes";          # HERMES_HOME (.hermes/) + workspace
        environmentFiles = [ "/secrets/${name}.env" ];
        # Slim build: messaging (Slack + Telegram) instead of the full package
        # (which pulls voice/tts/matrix/etc). Trims build time & surface.
        package = inputs.hermes-agent.packages.x86_64-linux.minimal;
        inherit extraDependencyGroups;
        settings = {
          # GPT-5.6 Sol via the openai-codex provider, authed with the ChatGPT
          # Pro subscription (one-time device-code login → auth.json on
          # /persist). Unlike Anthropic OAuth, this draws from the included
          # subscription quota.
          inherit model;
          terminal.backend = "local";          # tools run inside the container
          # Explicit compaction threshold: keeps the 85% behavior of hermes'
          # codex "autoraise" without the FYI notice it posts into the chat.
          compression.threshold = 0.85;
        };
      };

      # The hermes module seeds HERMES_HOME/.env from environmentFiles at NixOS
      # *activation* time, but in a MicroVM that races the virtiofs /persist +
      # /secrets mounts (HERMES_HOME doesn't exist yet), so the secrets silently
      # fail to land and the gateway starts with no tokens. Re-seed
      # deterministically after the mounts and before hermes starts.
      systemd.services."${name}-hermes-env" = {
        description = "Seed ${name} hermes .env from /secrets (after virtiofs mounts)";
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
          # /sethome persists the home channel as *_HOME_CHANNEL* lines in this
          # same .env, so carry those over across the re-seed or every reboot
          # silently resets the home channel.
          env_file=/persist/hermes/.hermes/.env
          home_lines=$(grep -hE '^[A-Z_]*HOME_CHANNEL[A-Z_]*=' "$env_file" 2>/dev/null || true)
          install -o hermes -g hermes -m 0640 /dev/null "$env_file"
          if [ -f /secrets/${name}.env ]; then
            cat /secrets/${name}.env >> "$env_file"
          fi
          if [ -n "$home_lines" ]; then
            printf '%s\n' "$home_lines" >> "$env_file"
          fi
        ''
        + lib.optionalString (homeChannelVar != null && homeChannelDefault != null && homeChannelDefault != "") ''
          # Default home channel. Only seeded when unset so a later /sethome
          # still wins.
          if ! grep -q '^${homeChannelVar}=' "$env_file"; then
            echo '${homeChannelVar}=${homeChannelDefault}' >> "$env_file"
          fi
        ''
        + lib.optionalString (soulFile != null) ''
          # SOUL.md — seed ONCE from the checked-in soul (a /nix/store path,
          # visible in-guest via the ro-store share). Never clobber: the agent
          # evolves its own soul at runtime, same preserve-user-state rule as
          # the home channel. Reseeding requires deleting the file in the VM.
          soul=/persist/hermes/.hermes/SOUL.md
          if [ ! -e "$soul" ]; then
            install -o hermes -g hermes -m 0640 ${soulFile} "$soul"
          fi
        ''
        + ''

          # config.yaml — the module's activation merge also races the mounts,
          # so the declared model never lands. Write the canonical config when
          # the model is wrong/missing (preserves hermes' runtime keys once
          # correct).
          cfg=/persist/hermes/.hermes/config.yaml
          if ! grep -q '^model: ${model}$' "$cfg" 2>/dev/null; then
            cat > "$cfg" <<'YAML'
          model: ${model}
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

      # --- SSH for first-run/debug, key-only, reachable only on the bridge ---
      services.openssh = {
        enable = true;
        settings.PasswordAuthentication = false;
        settings.PermitRootLogin = "prohibit-password";
      };
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDR8XpEeYELI+E4Kip6JV4V3Bh7vpv812kXX4eTPb+XA jamesjithin97@gmail.com"
      ];

      # Handy tools for poking around the VM (hermes provisions its own
      # in-container).
      environment.systemPackages = (with pkgs; [ git ripgrep curl jq ]) ++ extraPackages pkgs;

      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      system.stateVersion = "25.11";
    };
  };

  # --- Isolated bridge + NAT ---
  systemd.network.netdevs."10-${bridge}" = {
    netdevConfig = {
      Kind = "bridge";
      Name = bridge;
    };
  };

  systemd.network.networks."10-${bridge}" = {
    matchConfig.Name = bridge;
    addresses = [{ Address = "${hostAddr}/24"; }];
    networkConfig.ConfigureWithoutCarrier = true;
  };

  # Attach the VM's tap interface to the bridge.
  systemd.network.networks."11-${name}-tap" = {
    matchConfig.Name = tap;
    networkConfig.Bridge = bridge;
  };

  networking.nat.internalInterfaces = [ bridge ];

  networking.networkmanager.unmanaged = [ bridge tap ];

  # Isolation: the VM may reach the internet but NOT the host LAN, Tailscale,
  # other private networks (including the other agents' subnets), OR the host
  # itself.
  #  - FORWARD drops: VM -> other machines on private ranges (routed traffic).
  #  - INPUT drops:   VM -> the host's own services (host LAN/Tailscale/bridge
  #    IPs). Established/related is accepted first so host->VM debug SSH still
  #    works (the host initiates; only the VM's reply hits the host INPUT).
  networking.firewall.extraCommands = ''
    iptables -I FORWARD -i ${bridge} -d 10.0.0.0/8 -j DROP
    iptables -I FORWARD -i ${bridge} -d 172.16.0.0/12 -j DROP
    iptables -I FORWARD -i ${bridge} -d 192.168.0.0/16 -j DROP
    iptables -I FORWARD -i ${bridge} -d 100.64.0.0/10 -j DROP
    iptables -I FORWARD -i ${bridge} -d 169.254.0.0/16 -j DROP
    iptables -I INPUT -i ${bridge} -j DROP
    iptables -I INPUT -i ${bridge} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D FORWARD -i ${bridge} -d 10.0.0.0/8 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i ${bridge} -d 172.16.0.0/12 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i ${bridge} -d 192.168.0.0/16 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i ${bridge} -d 100.64.0.0/10 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i ${bridge} -d 169.254.0.0/16 -j DROP 2>/dev/null || true
    iptables -D INPUT -i ${bridge} -j DROP 2>/dev/null || true
    iptables -D INPUT -i ${bridge} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
  '';
}
