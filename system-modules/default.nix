{ config, lib, pkgs, ... }: {
  imports = [ ./boot ./fileSystems ./networking ./users ./desktop ];
}
