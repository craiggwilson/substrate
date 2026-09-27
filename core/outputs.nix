{ lib, ... }:
let
  builderType = lib.types.submodule {
    options.build = lib.mkOption {
      # raw on purpose: the result is opaque configuration (e.g. nixosSystem's
      # config), and an attrsOf-anything merge would recursively force it.
      # Builders must return an attrset; merging happens in the builder.
      type = lib.types.functionTo lib.types.raw;
      description = ''
        Function producing the attrset to merge into the output.
        Per-system builders receive { pkgs, system, inputs, substrate };
        global builders receive { inputs, substrate }.
      '';
    };
  };
in
{
  options.substrate.outputs = {
    global = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf builderType);
      description = ''
        Output builders invoked once, independent of system (e.g.,
        nixosConfigurations, homeConfigurations, overlays). Each attrset name
        becomes a flake-level output of the same name; all builders registered
        for a name have their results merged into it.
      '';
      default = { };
    };
    perSystem = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf builderType);
      description = ''
        Output builders invoked once per system in substrate.settings.systems
        (e.g., packages, devShells). Each attrset name becomes a flake output
        keyed by system; all builders registered for a name have their results
        merged into it.
      '';
      default = { };
    };
  };
}
