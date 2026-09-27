{ lib, config, ... }:
let
  settings = config.substrate.settings;
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
      }) settings.publish.shells
    );
in
{
  options.substrate.settings.publish.shells = lib.mkOption {
    type = lib.types.listOf lib.types.path;
    default = [ ];
    description = "Paths to shell files to publish as devShells flake outputs.";
  };

  config.substrate.outputs.perSystem.devShells = lib.mkIf (settings.publish.shells != [ ]) [
    {
      build = { pkgs, inputs, ... }: mkShells { inherit pkgs inputs; };
    }
  ];
}
