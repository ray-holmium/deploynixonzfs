# configuration in this file only applies to exampleHost host
#
# only my-config.* and zfs-root.* options can be defined in this file.
#
# all others goes to `configuration.nix` under the same directory as
# this file. 

{ system, pkgs, ... }: {
  inherit pkgs system;
  zfs-root = {
    boot = {
      devNodes = "/dev/";
      bootDevices = [ "nvme0n1p2/mnt/bios" ];
      immutable = false;
      availableKernelModules = [ "kernelModules_placeholder" ];
      removableEfi = true;
      kernelParams = [ ];
      sshUnlock = {
        # read sshUnlock.txt file.
        enable = false;
        authorizedKeys = [ ];
      };
    };
    networking = {
      # read changeHostName.txt file.
      hostName = "exampleHost";
      timeZone = "America/Vancouver";
      hostId = "abcd1234";
    };
  };

  # To add more options to per-host configuration, you can create a
  # custom configuration module, then add it here.
  users = {
    exampleUser.enable = true;
  };
  desktop = {
    gnome.enable = true;
  };
}
