{ config, ... }: {
  containers = builtins.mapAttrs
    (name: options: {
      config = { config, ... }: {
        imports = [ (options.nixos-module or { }) ];
        system.stateVersion = config.system.nixos.version;
      };
      ephemeral = true;
    })
    config.iodriver.jobs.nixos-container;
}
