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

set -euo pipefail

# TODO: any particular pgbench args we want to use? any sql?

export PGUSER=postgres

# init db
pgbench -i 

# bench 3 times
pgbench
pgbench
pgbench
