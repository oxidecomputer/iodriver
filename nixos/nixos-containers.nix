{ config, lib, ... }: {
  containers = builtins.mapAttrs
    (name: options: {
      config = { config, ... }: {
        imports = [ (options.nixos-module or { }) ];
        system.stateVersion = config.system.nixos.version;
      };
      ephemeral = true;
      bindMounts = lib.mkIf (options.disk_format != "block") {
        "/" = { hostPath = "/iodriver"; isReadOnly = false; };
      };
      allowedDevices = lib.mkIf (options.disk_format == "block") [
        { node = "/dev/cobblestone"; modifier = "rwm"; }
      ];
    })
    config.iodriver.jobs.nixos-container;
}
