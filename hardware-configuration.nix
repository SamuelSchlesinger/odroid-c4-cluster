{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  # Boot configuration for Tow-Boot (uses extlinux)
  boot = {
    loader.grub.enable = false;
    loader.generic-extlinux-compatible.enable = true;

    # Use mainline kernel - good S905X3 support
    kernelPackages = pkgs.linuxPackages_latest;

    # Serial console for Amlogic SoC
    kernelParams = [ "console=ttyAML0,115200n8" ];

    # Modules needed for boot
    initrd.availableKernelModules = [
      "usbhid"
      "usb_storage"
      "uas"
      "meson-gx-mmc"  # SD/eMMC controller
    ];

    kernelModules = [ ];
    extraModulePackages = [ ];
  };

  # SD card image configuration
  sdImage = {
    compressImage = true;
    expandOnBoot = true;
  };

  # Root filesystem
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  swapDevices = [ ];

  # Hardware settings
  hardware = {
    enableRedistributableFirmware = true;

    # Device tree for Odroid C4
    deviceTree = {
      enable = true;
      filter = "meson-sm1-odroid-c4.dtb";
    };
  };

  # CPU frequency scaling
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
}
