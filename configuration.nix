# configuration in this file is shared by all hosts

{ pkgs, ... }: {
  # Enable NetworkManager for wireless networking,
  # You can configure networking with "nmtui" command.
  # networking.useDHCP = true;
  networking.networkmanager.enable = true;

  users.users = {
    root = {
      initialHashedPassword = "!";
      openssh.authorizedKeys.keys = [ "sshKey_placeholder" ];
    };
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    # vimAlias = true;
    configure = {
      customRC = ''
      	set cursorline
	      set shiftwidth=4
	      set tabstop=4
	      set expandtab
	      set nowrap
	      set incsearch
	      set ignorecase
	      set smartcase
	      set history=1000
	      set wildmenu
	      set wildignore=*.docx,*.jpg,*.png,*.gif,*.pdf,*.pyc,*.exe,*.flv,*.img,*.xlsx
      '';
      packages.myVimPackage = with pkgs.vimPlugins; {
        start = [ 
          vim-nix
          nvim-treesitter
        ];
      };
    };
  };

  services.openssh = {
    enable = true;
    settings = { PasswordAuthentication = false; };
  };

  boot.zfs.forceImportRoot = false;
  
  nixpkgs.config.allowUnfree = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  programs.git.enable = true;

  security.doas = {
    enable = true;
  };
  security.sudo.enable = false;
  
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      function fish_greeting
       pfetch
      end
    '';
  };

  users.defaultUserShell = pkgs.fish;

  environment.shells = with pkgs; [ fish ];

  environment.systemPackages = builtins.attrValues {
    inherit (pkgs)
      jq
      vim
      micro
      pfetch
      neofetch
      grc
      fzf
      htop
    ;
    fishplugin-tide = pkgs.fishPlugins.tide;
    fishplugin-z = pkgs.fishPlugins.z;
    fishplugin-sponge = pkgs.fishPlugins.sponge;
    fishplugin-puffer = pkgs.fishPlugins.puffer;
    fishplugin-git = pkgs.fishPlugins.plugin-git;
    fishplugin-pisces = pkgs.fishPlugins.pisces;
    fishplugin-grc = pkgs.fishPlugins.grc;
    fishplugin-fzf = pkgs.fishPlugins.fzf-fish;
    fishplugin-done = pkgs.fishPlugins.done;
  };

  fonts.packages = with pkgs; [
    nerdfonts
  ];

  nix.settings = {
    substituters = ["https://hyprland.cachix.org"];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };
}
