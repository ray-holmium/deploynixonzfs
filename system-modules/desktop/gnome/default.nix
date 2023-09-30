{ config, lib, pkgs, ... }:

with lib;

{
  options.desktop.gnome.enable = mkEnableOption "Gnome desktop";

  config = mkIf config.desktop.gnome.enable {
    services.xserver = {
      enable = true;
      desktopManager.gnome.enable = true;
      displayManager.gdm.enable = true;
    };
  };
}