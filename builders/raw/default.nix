# Raw builder: produces the same outputs as the flake-parts builder as a plain
# attrset — no flake, no flake-parts. `coreInputs` is the attrset used for role
# resolution (in raw mode it defaults to the consumer's `inputs`). `inputs` is
# the consumer's attrset and is passed through to user modules unchanged.
{
  build =
    {
      inputs,
      # Inputs used for role resolution. In raw mode this defaults to the
      # consumer's `inputs`; flake mode supplies substrate's locked inputs.
      coreInputs ? inputs,
      # Library for evaluating the substrate configuration itself. Derived from
      # the nixpkgs input; override when nixpkgs is not among the inputs.
      lib ? (
        let
          nixpkgsInput =
            coreInputs.nixpkgs
              or (throw "substrate: raw builder needs inputs.nixpkgs.lib; pass flake-shaped inputs (see docs/src/builders.md for with-inputs) or a lib argument.");
        in
        nixpkgsInput.lib
          or (throw "substrate: raw builder needs inputs.nixpkgs.lib; pass flake-shaped inputs (see docs/src/builders.md for with-inputs) or a lib argument.")
      ),
    }:
    module:
    let
      eval = lib.evalModules {
        modules = [ module ];
        specialArgs = { inherit inputs coreInputs; };
      };
      inherit (eval.config) substrate;
      inherit (substrate) settings;
      inherit (substrate) outputs;
      slib = substrate.lib;

      nixpkgsInput = slib.resolveInput "nixpkgs" coreInputs;
      allOverlays = settings.overlays or [ ];

      buildAndMerge =
        builderArgs: builders: lib.foldl' (acc: builder: acc // (builder.build builderArgs)) { } builders;

      global = lib.mapAttrs (
        _: builders:
        buildAndMerge {
          inherit inputs coreInputs;
          inherit substrate;
        } builders
      ) outputs.global;

      perSystem = lib.mapAttrs (
        _: builders:
        lib.genAttrs settings.systems (
          system:
          let
            pkgs = import nixpkgsInput {
              inherit system;
              overlays = allOverlays;
              config = settings.nixpkgsConfig;
            };
          in
          buildAndMerge {
            inherit
              pkgs
              system
              inputs
              coreInputs
              ;
            inherit substrate;
          } builders
        )
      ) outputs.perSystem;
    in
    global // perSystem;
}
