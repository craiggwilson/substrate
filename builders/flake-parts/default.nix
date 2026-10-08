{
  build =
    {
      inputs,
      coreInputs ? inputs,
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
