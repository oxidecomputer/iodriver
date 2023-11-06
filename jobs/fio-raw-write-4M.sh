#!/usr/bin/env bash
#:
#: disk_format = "block"
#: driver = "nixos-container"
#: packages = ["fio"]
#:

set -euo pipefail

printf '%s' '
[global]
# raw block access
filename=/dev/cobblestone
direct=1

# does iodepth matter much? unclear
iodepth=48
ioengine=io_uring

# each individual job runs for 120 seconds
time_based
runtime=120
numjobs=1

# wait for all IO to finish before starting the next job
# note that this is the IO finishing from the perspective of the guest VM, not
# from the perspective of any buffering crucible upstairs is doing
stonewall=1

[write-4M]
bs=4M
rw=write
' > job.fio

fio job.fio; sync
