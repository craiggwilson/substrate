let
  common = import ../common.nix;
in
{
  build =
    {
      inputs,
      coreInputs ? common.defaultCoreInputs inputs,
      flake-parts-lib ? inputs.flake-parts.lib,
      self ? inputs.self,
      ...
    }:
    module:
    flake-parts-lib.mkFlake
      {
        inherit self inputs;
        specialArgs = {
          inherit coreInputs;
        };
      }
      {
        imports = [
          ./adapter.nix
          module
        ];
      };
}
