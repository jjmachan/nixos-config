{pkgs, ...}: {
  home.packages = with pkgs; [
  zellij
  neovim
  ghostty
  yazi
  git
  ];

  programs.claude-code.enable = true;
    programs.gh = {
          enable = true;
          gitCredentialHelper.enable = true;
        };

        programs.git = {
          enable = true;

          settings = {
            user = {
              name = "Jithin James";
              email = "jamesjithin97@gmail.com";
            };

            init.defaultBranch = "main";
          };
        };
}
