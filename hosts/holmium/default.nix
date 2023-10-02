# configuration in this file only applies to holmium host
#
# only my-config.* and zfs-root.* options can be defined in this file.
#
# all others goes to `configuration.nix` under the same directory as
# this file. 

{ system, pkgs, ... }: {
  inherit pkgs system;
  zfs-root = {
    boot = {
      devNodes = "/dev/disk/by-id/";
      bootDevices = [ "nvme-ADATA_SX8200PNP_2K1520130319_1" ];
      immutable = false;
      availableKernelModules = [  "xhci_pci" "thunderbolt" "nvme" "usb_storage" "sd_mod" ];
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
      hostName = "holmium";
      timeZone = "America/Vancouver";
      hostId = "cb48aef1";
    };
  };

  # To add more options to per-host configuration, you can create a
  # custom configuration module, then add it here.
  users = {
    ray.enable = true;
  };
  desktop = {
    gnome.enable = true;
  };
}
