{ config, lib, modulesPath, pkgs, ... }:
let
  cfg = config.iodriver;
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
    ./jobs.nix
    ./nixos-containers.nix
    ./options.nix
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

  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";

  virtualisation.vmVariant = {
    virtualisation.graphics = false;
    virtualisation.memorySize = 4096;
    virtualisation.useDefaultFilesystems = false;
    virtualisation.fileSystems."/" = {
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };

    # Have `qemu-vm.nix` generate us an empty disk image, and use it as
    # /dev/cobblestone.
    virtualisation.diskImage = "./iodriver.qcow2";
    virtualisation.diskSize = 128 * 1024;
    iodriver.cobblestone = "vda";

    # `installer/cd-dvd/iso-image.nix` sets a boot.postBootCommands which
    # imports /nix/store/nix-path-registration, which does not exist in the 9p-
    # based /nix/store, and then runs a nix-env command that attempts to realise
    # a store path, which hits the network and fails. This is copied from
    # `virtualisation/qemu-vm.nix` but with extra `lib.mkForce`.
    boot.postBootCommands = lib.mkForce ''
      if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
        ${config.nix.package.out}/bin/nix-store --load-db < ''${BASH_REMATCH[1]}
      fi

      # `qemu-vm.nix` does not wipe this device between runs, so ensure it's
      # ready for use. (We could instead use `virtualisation.emptyDiskImages`
      # but that puts them in $TMPDIR and the UX there is kinda bad.)
      ${pkgs.util-linux}/bin/wipefs --all --quiet /dev/vda
    '';
  };

  boot.loader.timeout = lib.mkForce 3;
  boot.kernelParams = [ "console=tty0" ];

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
  programs.command-not-found.enable = false;
}
