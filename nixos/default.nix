{ config, lib, modulesPath, pkgs, ... }:
let
  cfg = config.iodriver;
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
    ./driver.nix
    ./jobs.nix
    ./nixos-containers.nix
    ./options.nix
    ./vm.nix
  ];

  networking.hostName = "iodriver";
  environment.systemPackages = with pkgs; [ serial-bridge ];

  # Symlink our test disk to /dev/cobblestone.
  services.udev.extraRules = ''
    KERNEL=="${cfg.cobblestone}", SYMLINK+="cobblestone"
  '';

  # Allow login as root without a password.
  users.users.root.initialHashedPassword = "";
  # Automatically log in on gettys.
  services.getty.autologinUser = "root";

  isoImage.isoBaseName = "iodriver";
  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";

  boot.loader.timeout = lib.mkForce 3;
  boot.kernelParams = [ "console=tty0" ];
  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_blk" ];

  # We do not intend to install NixOS from this ISO.
  system.disableInstallerTools = true;
  # This system has no state; squelch the warning.
  #
  # Doing this on a system with state is a bad idea; see:
  # https://nixos.org/manual/nixos/stable/options.html#opt-system.stateVersion
  system.stateVersion = config.system.nixos.version;
  # General other minimization
  documentation.doc.enable = false;
  documentation.info.enable = false;
  documentation.nixos.enable = false;
  programs.command-not-found.enable = false;
}
