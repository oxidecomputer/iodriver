# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

{ craneLib, pkg-config, systemd }: craneLib.buildPackage {
  name = "serial-bridge";
  src = ./.;
  buildInputs = [ pkg-config systemd ];
}
