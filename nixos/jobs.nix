# Parses and imports jobs from ../jobs.
#
# These job definitions are stored as `config.iodriver.jobs`,
# which is an attribute set of job names and their definitions, and
# `config.iodriver.groupedJobs`, which groups these by their `driver`
# field. For example, a job named `fio` with `driver = "nixos-container"`
# could be referenced at either `config.iodriver.jobs.fio` or
# `config.iodriver.groupedJobs.nixos-container.fio`.

{ config, lib, pkgs, ... }: {
  options.iodriver = {
    jobs = lib.mkOption { };

    groupedJobs = lib.mkOption { };

    jobScripts = lib.mkOption {
      type = lib.types.listOf lib.types.pathInStore;
      default = [ ];
    };
  };

  config =
    let
      # readFrontmatter :: prefix -> path -> attrset
      #
      # Parses TOML frontmatter from the first block of lines in `path` with
      # the prefix `prefix`.
      #
      # For example, to read Buildomat-style `#:`-prefixed lines from a shell
      # script at `fio.sh`, write `readFrontmatter "#:" ./ fio.sh`.
      readFrontmatter = prefix: path:
        let
          # Read `path` to a string and split on newlines.
          lines = lib.strings.splitString "\n" (builtins.readFile path);
          endLine = (builtins.length lines) - 1;
          # Create a list of line numbers.
          range = lib.lists.range 0 endLine;
          # isMatch :: line number -> bool
          isMatch = lineNumber:
            lib.strings.hasPrefix prefix (builtins.elemAt lines lineNumber);
          isNotMatch = lineNumber: !(isMatch lineNumber);
          # Find the first line number in `lines` that matches the prefix.
          # `null` here is a default value.
          firstMatch = lib.lists.findFirst isMatch null range;
          # List all the lines that come after `firstLine`.
          remainingRange =
            if firstMatch == null then [ ]
            else lib.lists.range (firstMatch + 1) endLine;
          # Find the first line number in `lines` not matching the prefix.
          firstNonMatch = lib.lists.findFirst isNotMatch null remainingRange;
          # Select the first block of matching lines.
          matchingLines =
            if firstMatch == null then [ ]
            else lib.lists.sublist firstMatch (firstNonMatch - firstMatch) lines;
          # Remove the prefix and concatenate back into a string.
          frontmatter = builtins.concatStringsSep "\n"
            (builtins.map (lib.strings.removePrefix prefix) matchingLines);
        in
        if prefix == null then null else builtins.fromTOML frontmatter;

      # mkJob :: path -> (attrset | null)
      #
      # Try to parse a job from a path. Returns `null` if the path doesn't
      # look like a job (either doesn't have a recognized file extension or is
      # missing frontmatter).
      mkJob = path:
        let
          scriptPath = builtins.baseNameOf path;
          type =
            if lib.strings.hasSuffix ".sh" path
            then {
              name = lib.strings.removeSuffix ".sh" scriptPath;
              frontmatterPrefix = "#:";
            }
            else { frontmatterPrefix = null; };
          frontmatter =
            if type.frontmatterPrefix == null then null
            else readFrontmatter type.frontmatterPrefix path;
        in
        if (frontmatter == null || frontmatter == { })
        then null
        else {
          inherit (type) name;
          value = frontmatter // {
            inherit scriptPath;
          };
        };

      # jobs :: [ { name = string; value = attrset; } ]
      jobs =
        let
          # Read the directory entries for ../jobs.
          entries = builtins.readDir ../jobs;
          # Filter on regular files.
          regulars = lib.attrsets.filterAttrs (_: type: type == "regular") entries;
          # Get a list of paths to each regular file.
          files = lib.attrsets.mapAttrsToList (path: _: ../jobs/${path}) regulars;
        in
        # Call `mkJob` for each file in `files`, and filter out null values.
        builtins.filter (x: x != null) (builtins.map mkJob files);

      # Create a shell script to run all jobs scripts.
      runAllJobs = pkgs.writeShellScriptBin
        "iodriver-run-all-jobs"
        (builtins.concatStringsSep "\n" config.iodriver.jobScripts);
    in
    {
      iodriver.jobs = builtins.listToAttrs jobs;
      iodriver.groupedJobs =
        builtins.mapAttrs (_: builtins.listToAttrs)
          (builtins.groupBy (job: job.value.driver) jobs);

      # Add `iodriver-run-all-jobs` to $PATH for all users.
      environment.systemPackages = [ runAllJobs ];
      # Run `iodriver-run-all-jobs` on boot, then send a "done" message to
      # `serial-bridge-host` and power the system off when done.
      systemd.services.iodriver = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig.Type = "oneshot";
        script = ''
          ${lib.getExe runAllJobs}
          ${pkgs.serial-bridge}/bin/serial-bridge-guest send-done
          systemctl poweroff
        '';
      };
    };
}
