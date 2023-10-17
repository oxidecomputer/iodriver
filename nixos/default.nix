{ config, lib, modulesPath, ... }: {
  imports = [
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
    ./jobs.nix
    ./nixos-containers.nix
  ];

  networking.hostName = "iodriver";

  # Allow login as root without a password.
  users.users.root.initialHashedPassword = "";
  # Automatically log in on gettys.
  services.getty.autologinUser = "root";

  isoImage.makeEfiBootable = true;
  isoImage.makeUsbBootable = true;
  isoImage.squashfsCompression = "zstd -Xcompression-level 3";

  virtualisation.vmVariant = {
    virtualisation.diskImage = null;
    virtualisation.graphics = false;
    virtualisation.useDefaultFilesystems = false;
    virtualisation.fileSystems."/" = {
      fsType = "tmpfs";
      options = [ "mode=0755" ];
    };

    # `installer/cd-dvd/iso-image.nix` sets a boot.postBootCommands which
    # imports /nix/store/nix-path-registration, which does not exist in the 9p-
    # based /nix/store, and then runs a nix-env command that attempts to realise
    # a store path, which hits the network and fails. This is copied from
    # `virtualisation/qemu-vm.nix` but with extra `lib.mkForce`.
    boot.postBootCommands = lib.mkForce ''
      if [[ "$(cat /proc/cmdline)" =~ regInfo=([^ ]*) ]]; then
        ${config.nix.package.out}/bin/nix-store --load-db < ''${BASH_REMATCH[1]}
      fi
    '';
  };

  boot.loader.grub.extraConfig = ''
    serial --unit=1 --speed=115200 --word=8 --parity=no --stop=1
    terminal_input --append serial
    terminal_output --append serial
  '';
  boot.loader.timeout = lib.mkForce 3;
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
    "console=ttyS1,115200"
  ];

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
