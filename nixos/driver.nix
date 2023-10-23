{ ... }: {
  systemd.services.iodriver = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      # please forgive me
      export PATH="/run/current-system/sw/bin:$PATH"

      iodriver-run-all-jobs
    '';
  };
}
