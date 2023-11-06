
#!/usr/bin/env bash
#:
#: disk_format = "block"
#: driver = "nixos-container"
#: packages = ["fio"]
#:

set -euo pipefail

printf '%s' '
[global]
filename=/dev/cobblestone
iodepth=200
ioengine=io_uring
time_based
numjobs=1
direct=1
stonewall=1

[write-4M]
# just slam the writes for 5 minutes to make sure nothing breaks
runtime=300
bs=4M
rw=write

[read-16K]
# do a bit of reading to make sure it works. we are also interested in the
# max latency from the first read, since thatll be affected by buffering
# behavior in upstairs
runtime=10
bs=16K
rw=read
' > breakdeep.fio

fio breakdeep.fio
