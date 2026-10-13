# Builders that return the substrate outputs as a plain attrset: global outputs
# at the top level, per-system outputs keyed by system under their output name.
#
# That is the flake output schema, so this is what a bare
# `outputs = inputs: …` in a flake.nix returns — no flake-parts, no
# flake-parts' perSystem, and nothing added to the consumer's inputs.
let
  common = import ./common.nix;
in
{
  build =
    {
      inputs,
      # In a flake this is substrate's own locked inputs, so extensions resolve
      # their roles against substrate's pins unless the consumer rewires one
      # with inputs.substrate.inputs.<role>.follows or .url. Pass coreInputs
      # explicitly to resolve against a different set.
      coreInputs ? common.defaultCoreInputs inputs,
      # Library for evaluating the substrate configuration itself. Derived from
      # the nixpkgs input; override when nixpkgs is not among the inputs.
      lib ? (
        let
          nixpkgsInput =
            coreInputs.nixpkgs
              or (throw "substrate: this builder needs a lib, and derives one from inputs.nixpkgs.lib. Pass flake-shaped inputs (see docs/src/builders.md for with-inputs) or a lib argument.");
        in
        nixpkgsInput.lib
          or (throw "substrate: this builder needs a lib, and derives one from inputs.nixpkgs.lib. Pass flake-shaped inputs (see docs/src/builders.md for with-inputs) or a lib argument.")

      ),
      ...
    }:
    module:
    let
      c = common.fromModule {
        inherit
          coreInputs
          inputs
          lib
          module
          ;
      };

      global = lib.mapAttrs (_: builders: c.merge c.globalArgs builders) c.outputs.global;

      perSystem = lib.mapAttrs (
        _: builders:
        lib.genAttrs c.settings.systems (
          system: c.merge (c.perSystemArgs system (c.pkgsFor system)) builders
        )
      ) c.outputs.perSystem;

      # Both maps land at the top level, so a name claimed by both would lose
      # one without a trace. That is a configuration error, not a merge.
      shadowed = builtins.intersectAttrs global perSystem;
    in
    assert
      shadowed == { }
      || throw ''
        substrate: output name(s) ${lib.concatStringsSep ", " (builtins.attrNames shadowed)} are
        registered as both global and per-system. The plain builders put both
        maps at the top level, so one would silently replace the other.
      '';
    global // perSystem;
}
