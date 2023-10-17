{ craneLib, pkg-config, systemd }: craneLib.buildPackage {
  name = "serial-bridge";
  src = ./.;
  buildInputs = [ pkg-config systemd ];
}
