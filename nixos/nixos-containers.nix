{ config, lib, pkgs, ... }:
let
  mkfs.ext4 = "mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0";
in
{
  containers = builtins.mapAttrs
    (name: job: {
      config = { config, ... }: {
        imports = [ (job.nixos-module or { }) ];
        environment.systemPackages =
          builtins.map (pkg: pkgs.${pkg}) (job.packages);
        system.stateVersion = config.system.nixos.version;
      };
      ephemeral = true;
      bindMounts =
        if job.disk_format == "block"
        then { "/dev/cobblestone".isReadOnly = false; }
        else { "/".hostPath = "/iodriver"; "/".isReadOnly = false; };
      allowedDevices = lib.mkIf (job.disk_format == "block") [
        { node = "/dev/cobblestone"; modifier = "rw"; }
      ];
    })
    config.iodriver.jobs.nixos-container;

  environment.systemPackages = lib.attrsets.mapAttrsToList
    (name: job: pkgs.writeShellApplication {
      name = "iodriver-run-job-${name}";
      text = ''
        jobname=${lib.strings.escapeShellArg name}

        _iodriver_cleanup() {
          set +o errexit
          nixos-container stop "$jobname"
          umount --all-targets --quiet /dev/cobblestone
          wipefs --all --quiet /dev/cobblestone
        }
        trap _iodriver_cleanup EXIT

        ${lib.strings.optionalString (job.disk_format != "block") ''
          ${mkfs.${job.disk_format}} /dev/cobblestone
          mkdir -p /iodriver
          mount -t ${job.disk_format} /dev/cobblestone /iodriver
        ''}
        nixos-container start "$jobname"
        nixos-container run "$jobname" -- ${job}
      '';
    })
    config.iodriver.jobs.nixos-container;
}
