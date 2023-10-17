{ lib, ... }: {
  options.iodriver.jobs = lib.mkOption { };

  config.iodriver.jobs =
    let
      mkShellScriptJob = f:
        let
          lines = lib.strings.splitString "\n" (builtins.readFile f);
          range = lib.lists.imap0 (i: _: i) lines;
          isTOML = i: lib.strings.hasPrefix "#:" (builtins.elemAt lines i);
          firstLine = lib.lists.findFirst isTOML null range;
          lastLine = lib.lists.findFirst (i: i > firstLine && !(isTOML i)) null range;
        in
        {
          name = lib.strings.removeSuffix ".sh" (builtins.baseNameOf f);
          value = builtins.fromTOML
            (builtins.concatStringsSep "\n"
              (builtins.map (lib.strings.removePrefix "#:")
                (lib.lists.sublist firstLine (lastLine - firstLine) lines)));
        };
      mkJob = f:
        if lib.strings.hasSuffix ".sh" f
        then mkShellScriptJob f
        else null;
    in
    builtins.mapAttrs (_: builtins.listToAttrs)
      (builtins.groupBy
        (job: job.value.driver)
        (builtins.map mkJob (import ../jobs)));
}
