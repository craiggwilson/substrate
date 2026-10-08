{ lib, config, ... }:
let
  devenvCfg = config.substrate.devenv or { };
  slib = config.substrate.lib;

  mkDevenvShells =
    {
      pkgs,
      inputs,
      coreInputs,
      ...
    }:
    let
      devenvInput = slib.resolveInput "devenv" coreInputs;
    in
    lib.mapAttrs (
      _name: shellModule:
      devenvInput.lib.mkShell {
        inherit inputs pkgs;
        modules = [ shellModule ];
      }
    ) devenvCfg.shells;
in
{
  options.substrate.devenv.shells = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        freeformType = lib.types.lazyAttrsOf lib.types.anything;
      }
    );
    default = { };
    description = "Named devenv shell modules to build into devShells.";
  };

  config.substrate.outputs.perSystem.devShells =
    let
      shells = devenvCfg.shells or { };
    in
    lib.mkIf (shells != { }) [
      {
        build = mkDevenvShells;
      }
    ];
}
