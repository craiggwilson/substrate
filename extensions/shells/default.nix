{ lib, config, ... }:
let
  shellsCfg = config.substrate.shells or { };
  slib = config.substrate.lib;

  mkShells =
    { pkgs, inputs }:
    lib.listToAttrs (
      lib.map (path: {
        name = slib.nameFromPath path;
        value = import path {
          inherit lib inputs pkgs;
          inherit (pkgs) stdenv;
        };
      }) shellsCfg.publish
    );
in
{
  options.substrate.shells.publish = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    default = [ ];
    description = "Paths to shell files to build into devShells.";
  };

  config.substrate.outputs.perSystem.devShells = lib.mkIf (shellsCfg.publish != [ ]) [
    {
      build = { pkgs, inputs, ... }: mkShells { inherit pkgs inputs; };
    }
  ];
}
