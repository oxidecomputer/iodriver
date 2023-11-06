#!/bin/bash
#:
#: name = "iodriver.iso"
#: variety = "basic"
#: target = "ubuntu-22.04"
#: output_rules = [
#:	"=/work/oxidecomputer/iodriver/result/iso/iodriver.iso",
#:	"=/nix/var/log/nix/drvs/*/*",
#: ]
#:
#: [[publish]]
#: series = "iodriver"
#: name = "iodriver.iso"
#: from_output = "/work/oxidecomputer/iodriver/result/iso/iodriver.iso"
#:

set -o errexit
set -o pipefail
set -o xtrace

curl -fLOsS https://releases.nixos.org/nix/nix-2.18.1/install
# https://releases.nixos.org/nix/nix-2.18.1/install.sha256
echo "59bdd4f890c8dfdf8e530794bf6bf50392b6d109d772da0d953c50e6bebe34c1  install" | sha256sum -c
sh install --yes --no-daemon --no-channel-add --no-modify-profile
# shellcheck source=/dev/null
source ~/.nix-profile/etc/profile.d/nix.sh

nix --experimental-features="nix-command flakes" build
