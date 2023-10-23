{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
  inputs.crane.url = "github:ipetkov/crane/v0.14.3";
  inputs.crane.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, crane, ... }:
    let
      eachSystem = nixpkgs.lib.genAttrs [ "x86_64-linux" ];
      pkgs = eachSystem (system: import nixpkgs {
        inherit system;
        overlays = [
          (pkgs: orig: {
            craneLib = crane.mkLib pkgs;
            serial-bridge = pkgs.callPackage ./serial-bridge { };
          })
        ];
      });
    in
    {
      packages = eachSystem (system:
        let
          nixosSystem = nixpkgs.lib.nixosSystem {
            inherit system;
            pkgs = pkgs.${system};
            modules = [ ./nixos ];
          };
        in
        rec
        {
          inherit (pkgs.${system}) serial-bridge;
          inherit (nixosSystem.config.system.build) isoImage toplevel vm;
          default = isoImage;
        });

      formatter = eachSystem (system: pkgs.${system}.nixpkgs-fmt);
    };
}
