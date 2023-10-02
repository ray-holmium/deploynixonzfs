{ config, lib, pkgs, ... }:

with lib;

{
  options.users.exampleUser.enable = mkEnableOption "User account and configurations";

  config = mkIf config.users.exampleUser.enable {

    # imports = [  ];

    users.users.exampleUser = {
      initialHashedPassword = "userHash_placeholder";
      description = "exampleUser";
      extraGroups = [ "wheel" "NetworkManager"];
      isNormalUser = true;
    };    
    home-manager = {
      users.exampleUser = {
        programs.home-manager.enable = true;
        home.stateVersion = "23.05";
        # home.homeDirectory = "/home/exampleUser";
        home.packages = builtins.attrValues {
          inherit (pkgs)
            # vivaldi
          ;
        };
      };
    };
  };
} 
