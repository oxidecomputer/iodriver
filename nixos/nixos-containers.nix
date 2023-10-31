# Creates job scripts where `driver = "nixos-container"`.

{ config, lib, pkgs, ... }:
let
  mkfs.ext4 = "${pkgs.e2fsprogs}/bin/mkfs.ext4 -E lazy_itable_init=0,lazy_journal_init=0";

  scripts = lib.attrsets.mapAttrsToList
    (name: job: pkgs.writeShellApplication {
      name = "iodriver-run-job-${name}";
      runtimeInputs = with pkgs; [ nixos-container serial-bridge util-linux ];
      text = ''
        jobname=${lib.strings.escapeShellArg name}
        job_output_file="/tmp/$jobname-output.txt"

        get_time_millis() {
          # get time in nanos but shave off the last 6 digits of micros/nanos to
          # leave us with time in milliseconds
          date +'%s%N' | sed 's/......$//'
        }

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
        
        job_start="$(get_time_millis)"
        nixos-container run "$jobname" -- ${job} &> "$job_output_file" 
        job_exit="$?"
        job_end="$(get_time_millis)"

        job_time_elapsed="$(( job_end - job_start ))"
        
        serial-bridge-guest send-results \
          --test-name "$jobname" \
          --test-output "$job_output_file" \
          --test-exit-code "$job_exit" \
          --test-runtime-millis "$job_time_elapsed" \
          --dmesg-output "todo i guess"
      '';
    })
    config.iodriver.groupedJobs.nixos-container;
in
{
  # Define the NixOS containers.
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
    config.iodriver.groupedJobs.nixos-container;

  iodriver.jobScripts = builtins.map lib.getExe scripts;
  # Also provide the scripts on the system $PATH.
  environment.systemPackages = scripts;
}
