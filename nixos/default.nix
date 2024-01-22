# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Sets basic NixOS options for the generated ISO, and imports of all the other
# modules we're using.

{ config, lib, modulesPath, pkgs, ... }:
let
  cfg = config.iodriver;
in
{
  imports = [
    "${modulesPath}/installer/cd-dvd/iso-image.nix"
    ./jobs.nix
    ./nixos-containers.nix
    ./vm.nix
  ];

  options.iodriver = {
    # The block device to symlink to `/dev/cobblestone`. This is modified in the
    # development VM (see ./vm.nix).

    # YYY im deciding that its fine to keep nuking 0n1 because
    # - our VMs are getting torn down after the test anyway
    # - we copytoram the rootfs
    # - its more representative of a load test because each crucible will be
    #   active instead of 2 crucibles per instance with only one active
    cobblestone = lib.mkOption { default = "nvme0n1"; };
  };

  config = {
    networking.hostName = "iodriver";
    environment.systemPackages = with pkgs; [ serial-bridge ];

    # Symlink our test disk to /dev/cobblestone.
    services.udev.extraRules = ''
      KERNEL=="${cfg.cobblestone}", SYMLINK+="cobblestone"
    '';

    # Allow login as root without a password.
    users.users.root.initialHashedPassword = "";

    # YYY getty on/off should be configurable. And when getty is on, we should
    # not run iodriver guest in a way where it reads from tty.

    # Automatically log in on gettys.
    # services.getty.autologinUser = "root";
    systemd.services."serial-getty@ttyS0".enable = lib.mkForce false;
    services.openssh.enable = true;

    systemd.services.oxide-ssh-init = {
      description = "Add SSH keys from the Oxide cidata volume or EC2 IMDS";
      # `script` takes a string and adds a bash shebang and `set -e` to it.
      script = builtins.readFile ./ssh-init.sh;
      path = with pkgs; [ coreutils curl jq mtools ];

      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      before = [ "sshd.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ConditionPathExists = "!/root/.ssh/authorized_keys";
      };
    };


    # Name the output file `iodriver.iso`.
    isoImage.isoBaseName = "iodriver";
    # Use a very quick but effective compression.
    isoImage.squashfsCompression = "zstd -Xcompression-level 3";

    # Leave a few seconds for enabling kernel debug messages; but otherwise the
    # default of 10 seconds is a bit too long to be comfortable for automated
    # uses.
    boot.loader.timeout = lib.mkForce 3;
    boot.kernelParams = [
      # Display console messages to both the serial console and the VGA console.
      "copytoram"
      "console=ttyS0"
      "console=tty0"
    ];

    # These options are necessary for booting in Propolis.
    isoImage.makeEfiBootable = true;
    isoImage.makeUsbBootable = true;
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
  };
}
