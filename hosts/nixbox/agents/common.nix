# Shared host plumbing for all hermes-agent MicroVMs — things that must be
# defined exactly once, regardless of how many agents are in the roster
# (per-agent wiring lives in mkAgent.nix).
{ inputs, lib, ... }:

{
  imports = [ inputs.microvm.nixosModules.host ];

  systemd.network.enable = lib.mkDefault true;

  # NAT egress for every agent bridge. internalInterfaces is contributed
  # per-agent by mkAgent (lists merge); the shared toggles are mkDefault so
  # the rest of the system config can still override them.
  # No externalInterface: masquerade VM traffic out of whichever interface
  # the default route picks. Pinning it to Wi-Fi (wlp0s20f3) silently cut
  # every agent off once a USB Ethernet adapter took over the default route
  # (Nov 2026): their packets left un-NATed and were dropped. The FORWARD
  # drops in mkAgent still keep the VMs off the LAN and Tailscale.
  networking.nat = {
    enable = lib.mkDefault true;
    externalInterface = lib.mkDefault null;
  };
}
