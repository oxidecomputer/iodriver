# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Top-level entrypoint for iodriver.
#
# The most useful commands are:
# - `nix build`: Builds result/iso/iodrvier.iso. (This is a shorthand for
#   `nix build .#packages.x86_64-linux.default`).
# - `nix run .#vm`: Builds and runs a shell script to start an iodriver VM
#   directly from the Nix store, useful for iterative development. (This is a
#   shorthand for `nix run .#packages.x86_64-linux.vm`.)
# - `nix fmt`: Runs `nixpkgs-fmt`.
#
# These commands require enabling the experimental features "nix-command" and
# "flakes". See https://nixos.wiki/wiki/Flakes#Enable_flakes for instructions.

{
  # Define our inputs.
  inputs = {
    # This uses the `nixos-23.05` branch of nixpkgs, a stable release branch
    # that is updated when packages are built, tested, and ready to be
    # downloaded.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";

    # Crane is a Nix library for building Rust projects that is easier to use
    # than nixpkgs's built-in Rust builder.
    crane.url = "github:ipetkov/crane/v0.14.3";
    # Crane defines a `nixpkgs` input. To make sure it uses the same version
    # we're using, we tell Nix to overwrite it with ours.
    crane.inputs.nixpkgs.follows = "nixpkgs";
  };

  # Define our outputs, a function over the inputs.
  outputs = { nixpkgs, crane, ... }:
    # `let ... in` is used for variable binding.
    let
      # Import nixpkgs for "x86_64-linux".
      pkgs = import nixpkgs {
        system = "x86_64-linux";
        # Define an overlay that provides additional top-level attributes in
        # `pkgs`.
        overlays = [
          (pkgs: orig: {
            craneLib = crane.mkLib pkgs;
            serial-bridge = pkgs.callPackage ./serial-bridge { };
          })
        ];
      };

      # Create a NixOS system, using the nixpkgs we imported above, and
      # ./nixos/default.nix as a module.
      nixosSystem = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        pkgs = pkgs;
        modules = [ ./nixos ];
      };
    in
    {
      # The Nix command line expects a certain schema; see https://nixos.wiki/
      # wiki/Flakes#Flake_schema. These packages can be built via
      # `nix build .#packages.x86_64-linux.default` (or the shorthand,
      # `nix build .#default`).
      packages.x86_64-linux = rec {
        inherit (pkgs) serial-bridge;
        inherit (nixosSystem.config.system.build) isoImage toplevel vm;
        default = isoImage;
      };

      # Defines the `nixpkgs-fmt` package from nixpkgs as our project's
      # formatter for `nix fmt`.
      formatter.x86_64-linux = pkgs.nixpkgs-fmt;
    };
}
