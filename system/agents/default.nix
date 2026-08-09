# The agent roster — every hermes-agent MicroVM on this host.
#
# Each agent gets its own /24 (192.168.<octet>.0/24), MAC, bridge and state
# dirs, all derived from `name` by mkAgent. To add an agent: pick the next
# free octet + MAC, add a block, rebuild, then provision
# /var/lib/<name>/secrets/<name>.env by hand (see mkAgent.nix).
let
  mkAgent = import ./mkAgent.nix;
in
{
  imports = [
    ./common.nix

    # Penny — personal assistant (Slack + Telegram). Agent #1.
    (mkAgent {
      name = "penny";
      subnetOctet = 101;
      mac = "02:00:00:00:00:02";
      # Default home channel: the Telegram DM with jjmachan (chat 322721507).
      homeChannelVar = "TELEGRAM_HOME_CHANNEL";
      homeChannelDefault = "322721507";
      # "anthropic" predates the switch to openai-codex; kept for parity.
      extraDependencyGroups = [ "messaging" "anthropic" ];
      extraPackages = pkgs: [ pkgs.ffmpeg ];
    })

    # Alfred — work assistant (sales research/outreach), work Slack only.
    # Agent #2.
    (mkAgent {
      name = "alfred";
      subnetOctet = 102;
      mac = "02:00:00:00:00:03";
      # Default home channel: jjmachan's Slack DM with Alfred.
      homeChannelVar = "SLACK_HOME_CHANNEL";
      homeChannelDefault = "D0BF8CP0TJS";
    })

    # Iris — Telegram guide for friends exploring what AI agents can do.
    # Agent #3. Her persona is checked in (iris/soul.md) and seeded ONCE on
    # first boot; from then on she evolves it herself.
    # Home channel = jjmachan's DM: cron results go to each job's ORIGIN chat
    # (per-user already); home is only the fallback sink + restart notices.
    # Seeding it also stops friends from /sethome-ing the global value.
    (mkAgent {
      name = "iris";
      subnetOctet = 103;
      mac = "02:00:00:00:00:04";
      homeChannelVar = "TELEGRAM_HOME_CHANNEL";
      homeChannelDefault = "322721507";
      soulFile = ./iris/soul.md;
    })
  ];
}
