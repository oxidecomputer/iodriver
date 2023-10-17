{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";

  outputs = { nixpkgs, ... }:
    let
      eachSystem = nixpkgs.lib.genAttrs [ "x86_64-linux" ];
      pkgs = eachSystem (system: import nixpkgs { inherit system; });
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
          inherit (nixosSystem.config.system.build) isoImage toplevel vm;
          default = isoImage;
        });

      formatter = eachSystem (system: pkgs.${system}.nixpkgs-fmt);
    };
}
