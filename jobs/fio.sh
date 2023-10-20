#!/usr/bin/env bash
#:
#: name = "fio"
#: disk_format = "block"
#: driver = "nixos-container"
#: packages = ["fio"]
#:

set -euxo pipefail

# basic test to make sure things are working
printf '%s' '
[global]
filename=/dev/cobblestone
iodepth=25
ioengine=aio
time_based
runtime=10
numjobs=1
direct=1
stonewall=1

[randread-16K]
bs=16K
rw=randread

[randwrite-16K]
bs=16K
rw=randwrite

[read-16K]
bs=16K
rw=read

[write-16K]
bs=16K
rw=write
' > perf.fio

# we could make this output json later
fio perf.fio