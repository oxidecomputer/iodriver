{
  virtualisation.vmVariant = { config, lib, pkgs, ... }: {
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

    # Don't run `iodriver.service` on boot, as we're probably here to debug
    # something.
    systemd.services.iodriver.wantedBy = lib.mkForce [ ];

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
}
