# Alfred — Hermes-agent work assistant (sales research/outreach) in an
# isolated MicroVM. Agent #2, cloned from the Penny pattern.
#
# Host-side wiring: declares the alfred-vm, sets up an isolated bridge
# (br-alfred) with NAT egress, and bootstraps the host-side state + secrets
# directories.
#
# NOTE: relies on Penny's host.nix for the microvm host module import and the
# shared NAT defaults (enable/externalInterface are mkDefault there). If Penny
# is ever retired, move `imports = [ inputs.microvm.nixosModules.host ]` and
# those NAT toggles here.
#
# Network model: alfred-vm sits on its own host-only bridge (192.168.102.0/24)
# with NAT to the internet. It is NOT on the LAN or Tailscale and exposes no
# inbound ports — Slack (Socket Mode) is outbound-only.
{ inputs, lib, ... }:

{
  # Host-side persistent state + read-only secrets for Alfred.
  # secrets/ is provisioned by hand (alfred.env) and never committed.
  systemd.tmpfiles.rules = [
    "d /var/lib/alfred 0755 root root -"
    "d /var/lib/alfred/persist 0755 root root -"
    "d /var/lib/alfred/secrets 0700 root root -"
  ];

  # Declarative MicroVM, built and deployed with the host.
  microvm.vms.alfred-vm = {
    specialArgs = { inherit inputs; };
    config = import ./vm.nix;
  };

  # --- Isolated bridge + NAT (mirrors the penny pattern, different subnet) ---
  systemd.network.enable = lib.mkDefault true;

  systemd.network.netdevs."10-br-alfred" = {
    netdevConfig = {
      Kind = "bridge";
      Name = "br-alfred";
    };
  };

  systemd.network.networks."10-br-alfred" = {
    matchConfig.Name = "br-alfred";
    addresses = [{ Address = "192.168.102.1/24"; }];
    networkConfig.ConfigureWithoutCarrier = true;
  };

  # Attach the VM's tap interface to the bridge. Taps need globally unique,
  # non-glob-matchable names (tap-alfred) so no other agent's rule steals them.
  systemd.network.networks."11-alfred-tap" = {
    matchConfig.Name = "tap-alfred";
    networkConfig.Bridge = "br-alfred";
  };

  # NAT: enable + externalInterface merge with Penny's identical mkDefault
  # definitions; internalInterfaces is a list and merges.
  networking.nat = {
    enable = lib.mkDefault true;
    externalInterface = lib.mkDefault "wlp0s20f3";
    internalInterfaces = [ "br-alfred" ];
  };

  networking.networkmanager.unmanaged = [ "br-alfred" "tap-alfred" ];

  # Isolation: Alfred may reach the internet but NOT the host LAN, Tailscale,
  # other private networks (including penny-vm's 192.168.101.0/24), OR the
  # host itself.
  #  - FORWARD drops: VM -> other machines on private ranges (routed traffic).
  #  - INPUT drops:   VM -> the host's own services (host LAN/Tailscale/bridge
  #    IPs). Established/related is accepted first so host->VM debug SSH still
  #    works (the host initiates; only the VM's reply hits the host INPUT).
  networking.firewall.extraCommands = ''
    iptables -I FORWARD -i br-alfred -d 10.0.0.0/8 -j DROP
    iptables -I FORWARD -i br-alfred -d 172.16.0.0/12 -j DROP
    iptables -I FORWARD -i br-alfred -d 192.168.0.0/16 -j DROP
    iptables -I FORWARD -i br-alfred -d 100.64.0.0/10 -j DROP
    iptables -I FORWARD -i br-alfred -d 169.254.0.0/16 -j DROP
    iptables -I INPUT -i br-alfred -j DROP
    iptables -I INPUT -i br-alfred -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D FORWARD -i br-alfred -d 10.0.0.0/8 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i br-alfred -d 172.16.0.0/12 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i br-alfred -d 192.168.0.0/16 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i br-alfred -d 100.64.0.0/10 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i br-alfred -d 169.254.0.0/16 -j DROP 2>/dev/null || true
    iptables -D INPUT -i br-alfred -j DROP 2>/dev/null || true
    iptables -D INPUT -i br-alfred -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
  '';
}
