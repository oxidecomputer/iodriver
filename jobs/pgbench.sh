#!/usr/bin/env bash
#:
#: name = "pgbench"
#: disk_format = "ext4"
#: driver = "nixos-container"
#: packages = ["pgbench"]
#:
#: [nixos-module]
#: services.postgresql.enable = true
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
