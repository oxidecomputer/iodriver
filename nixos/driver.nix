{ ... }: {
  systemd.services.iodriver = {
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      echo "artemis fill this in"
    '';
  };
}
