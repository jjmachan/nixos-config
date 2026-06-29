# Penny — Hermes-agent personal assistant in an isolated MicroVM.
#
# Host-side wiring: imports the microvm host module, declares the penny-vm,
# sets up an isolated bridge (br-penny) with NAT egress, and bootstraps the
# host-side state + secrets directories.
#
# Network model: penny-vm sits on its own host-only bridge (192.168.101.0/24)
# with NAT to the internet. It is NOT on the LAN or Tailscale and exposes no
# inbound ports — Slack (Socket Mode) and WhatsApp (Baileys) are outbound-only.
{ inputs, lib, ... }:

{
  imports = [ inputs.microvm.nixosModules.host ];

  # Host-side persistent state + read-only secrets for Penny.
  # secrets/ is provisioned by hand (penny.env) and never committed.
  systemd.tmpfiles.rules = [
    "d /var/lib/penny 0755 root root -"
    "d /var/lib/penny/persist 0755 root root -"
    "d /var/lib/penny/secrets 0700 root root -"
  ];

  # Declarative MicroVM, built and deployed with the host.
  microvm.vms.penny-vm = {
    specialArgs = { inherit inputs; };
    config = import ./vm.nix;
  };

  # --- Isolated bridge + NAT (mirrors the suika pattern, different subnet) ---
  systemd.network.enable = lib.mkDefault true;

  systemd.network.netdevs."10-br-penny" = {
    netdevConfig = {
      Kind = "bridge";
      Name = "br-penny";
    };
  };

  systemd.network.networks."10-br-penny" = {
    matchConfig.Name = "br-penny";
    addresses = [{ Address = "192.168.101.1/24"; }];
    networkConfig.ConfigureWithoutCarrier = true;
  };

  # Attach the VM's tap interface to the bridge. The tap is named "tap-penny"
  # (not "vm-penny") so it does NOT match suika's "vm-*" rule.
  systemd.network.networks."11-penny-tap" = {
    matchConfig.Name = "tap-penny";
    networkConfig.Bridge = "br-penny";
  };

  # NAT: enable + externalInterface are equal to suika's (mergeEqualOption
  # allows identical definitions); internalInterfaces is a list and merges.
  # Using mkDefault on the shared toggles keeps Penny self-sufficient if suika
  # is later removed, without conflicting while both coexist.
  networking.nat = {
    enable = lib.mkDefault true;
    externalInterface = lib.mkDefault "wlp0s20f3";
    internalInterfaces = [ "br-penny" ];
  };

  networking.networkmanager.unmanaged = [ "br-penny" "tap-penny" ];

  # Isolation: Penny may reach the internet but NOT the host LAN, Tailscale,
  # other private networks, OR the host itself.
  #  - FORWARD drops: VM -> other machines on private ranges (routed traffic).
  #  - INPUT drops:   VM -> the host's own services (host LAN/Tailscale/bridge
  #    IPs). Established/related is accepted first so host->VM debug SSH still
  #    works (the host initiates; only the VM's reply hits the host INPUT).
  networking.firewall.extraCommands = ''
    iptables -I FORWARD -i br-penny -d 10.0.0.0/8 -j DROP
    iptables -I FORWARD -i br-penny -d 172.16.0.0/12 -j DROP
    iptables -I FORWARD -i br-penny -d 192.168.0.0/16 -j DROP
    iptables -I FORWARD -i br-penny -d 100.64.0.0/10 -j DROP
    iptables -I FORWARD -i br-penny -d 169.254.0.0/16 -j DROP
    iptables -I INPUT -i br-penny -j DROP
    iptables -I INPUT -i br-penny -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D FORWARD -i br-penny -d 10.0.0.0/8 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i br-penny -d 172.16.0.0/12 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i br-penny -d 192.168.0.0/16 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i br-penny -d 100.64.0.0/10 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i br-penny -d 169.254.0.0/16 -j DROP 2>/dev/null || true
    iptables -D INPUT -i br-penny -j DROP 2>/dev/null || true
    iptables -D INPUT -i br-penny -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
  '';
}
