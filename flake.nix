{
  description = "Contexir development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (import nixpkgs {
            inherit system;
          })
        );
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          beamPackages = pkgs.beam.packages.erlang;
        in
        {
          default = pkgs.mkShell {
            packages = [
              beamPackages.elixir
              beamPackages.erlang
              pkgs.mix2nix
              pkgs.rebar3
            ];

            shellHook = ''
              export MIX_HOME="$PWD/.nix/mix"
              export HEX_HOME="$PWD/.nix/hex"
              export ERL_AFLAGS="-kernel shell_history enabled"
              mkdir -p "$MIX_HOME" "$HEX_HOME"
            '';
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
