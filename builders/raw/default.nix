# Raw builder: produces the same outputs as the flake-parts builder as a plain
# attrset — no flake, no flake-parts. `inputs` is an attrset keyed by role name;
# values must be flake-shaped.
{
  build =
    {
      inputs,
      # Library for evaluating the substrate configuration itself. Derived from
      # the nixpkgs input; override when nixpkgs is not among the inputs.
      lib ? (
        let
          nixpkgsInput =
            inputs.nixpkgs
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
        specialArgs = { inherit inputs; };
      };
      substrate = eval.config.substrate;
      inherit (substrate) settings;
      inherit (substrate) outputs;
      slib = substrate.lib;

      nixpkgsInput = slib.resolveInput "nixpkgs" inputs;
      allOverlays = settings.overlays or [ ];

      buildAndMerge =
        builderArgs: builders: lib.foldl' (acc: builder: acc // (builder.build builderArgs)) { } builders;

      global = lib.mapAttrs (
        _: builders:
        buildAndMerge {
          inherit inputs;
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
            inherit pkgs system inputs;
            inherit substrate;
          } builders
        )
      ) outputs.perSystem;
    in
    global // perSystem;
}
