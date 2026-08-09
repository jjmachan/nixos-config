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
  networking.nat = {
    enable = lib.mkDefault true;
    externalInterface = lib.mkDefault "wlp0s20f3";
  };
}
