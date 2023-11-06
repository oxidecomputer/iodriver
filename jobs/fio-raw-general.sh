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

[randread-4K]
bs=4K
rw=randread

[randread-16K]
bs=16K
rw=randread

[randread-4M]
bs=4M
rw=randread

[randwrite-4K]
bs=4K
rw=randwrite

[randwrite-16K]
bs=16K
rw=randwrite

[randwrite-4M]
bs=4M
rw=randwrite

[randrw-4K]
bs=4K
rw=randrw

[randrw-16K]
bs=16K
rw=randrw

[randrw-4M]
bs=4M
rw=randrw
' > general-direct.fio

fio general-direct.fio
