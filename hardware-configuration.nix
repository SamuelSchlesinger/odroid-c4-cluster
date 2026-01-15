{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  # Boot configuration for Tow-Boot (uses extlinux)
  boot = {
    loader.grub.enable = false;
    loader.generic-extlinux-compatible.enable = true;

    # Use LTS kernel for stability
    kernelPackages = pkgs.linuxPackages_6_6;

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
    # Device tree included in kernel, no filtering needed
  };

  # CPU frequency scaling
  powerManagement.cpuFreqGovernor = lib.mkDefault "ondemand";
}
