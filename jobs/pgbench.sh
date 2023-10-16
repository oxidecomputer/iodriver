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

which pgbench
echo "hello, world"
