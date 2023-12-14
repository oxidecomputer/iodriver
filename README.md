# iodriver

block device

## Building the bootable image

You will need Nix on a Linux machine to build this image. Once Nix is installed, enable Flakes by writing this to ~/.config/nix/nix.conf:

```
experimental-features = nix-command flakes
```

To build the image:

```bash
nix build
```

The output ISO can be found in `result/iso/`.

## Running in QEMU (without Crucible)

This will run a slightly modified version of iodriver in a QEMU VM:

```bash
nix run .#vm
```

Nix creates and runs a shell script that creates an empty 128 GiB qcow2 image, boots the kernel, and mounts `/nix/store` via virtio-9p. This is useful for iterating on iodriver itself or individual tests, if you have Nix installed. Keep in mind that any test results you get from this mode are worse than useless, other than ensuring your scripts function.

You can terminate the VM by typing `Ctrl-a x`.
