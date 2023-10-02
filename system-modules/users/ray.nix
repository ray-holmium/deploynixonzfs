{ config, lib, pkgs, ... }:

with lib;

{
  options.users.ray.enable = mkEnableOption "User account and configurations";

  config = mkIf config.users.ray.enable {

    # imports = [  ];

    users.users.ray = {
      initialHashedPassword = "$6$KAtiCuHo5fmAPKMW$0SMXx7mH5yK9fkx5ByRNHKFSdLxV/JCKW6p7wjr2tV0ptIVgDP8FERXZ93ljutviffbfWeLtIZdMDDjZ1D/Kt0";
      description = "ray";
      extraGroups = [ "wheel" "NetworkManager"];
      isNormalUser = true;
    };    
    home-manager = {
      users.ray = {
        programs.home-manager.enable = true;
        home.stateVersion = "23.05";
        # home.homeDirectory = "/home/ray";
        home.packages = builtins.attrValues {
          inherit (pkgs)
            # vivaldi
          ;
        };
      };
    };
  };
} 
