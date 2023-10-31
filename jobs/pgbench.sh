#!/usr/bin/env bash
#:
#: disk_format = "ext4"
#: driver = "nixos-container"
#: packages = ["postgresql"]
#:
#: [nixos-module.services.postgresql]
#: enable = true
#: authentication = "local all all trust\n"
#:

set -euxo pipefail

which pgbench
echo "hello, world"

export PGUSER=postgres

# init db
pgbench -i 

# bench 3 times
pgbench
pgbench
pgbench
