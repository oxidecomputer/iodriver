{ lib, ... }: {
  options.iodriver = {
    cobblestone = lib.mkOption { default = "nvme0n1"; };
    jobs = lib.mkOption { };
  };
}
