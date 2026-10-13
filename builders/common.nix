# The part of a builder that does not depend on the build system.
#
# A builder supplies `lib` and the shape it returns, and walks `outputs.global`
# and `outputs.perSystem` itself. Everything in between — evaluating the
# substrate configuration, resolving the nixpkgs role, building a package set
# per system, merging the output builders registered for a name — is here, so a
# builder cannot get one of those subtly wrong.
#
# The two entry points are named for where the configuration comes from, and
# differ only in that: `fromModule` evaluates a substrate module, `fromConfig`
# takes one a module system has already evaluated. Both end up in the same
# place, so a builder picks the one that matches how it was handed its config.
rec {
  # The flake-shaped input set extensions resolve their own dependencies from.
  # Defaults to substrate's own inputs whenever substrate is one of the
  # consumer's flake inputs, which is what makes
  # `inputs.substrate.inputs.<role>.follows` and `.url` do what the docs say.
  # Falls back to the consumer's inputs where substrate is not a flake input
  # (a npins or niv pin, or a plain `default.nix` import).
  defaultCoreInputs = inputs: inputs.substrate.inputs or inputs;

  # Everything derived from an evaluated substrate configuration: the context
  # output builders receive, the merge helper, and a package set per system.
  fromConfig =
    {
      lib,
      inputs,
      # Required rather than defaulted, so the default is written once, on
      # `fromModule`. A caller reaching here already has a coreInputs set: it
      # either supplied one or came from a module argument.
      coreInputs,
      substrate,
    }:
    let
      inherit (substrate) outputs settings;
      nixpkgsInput = substrate.lib.resolveInput "nixpkgs" coreInputs;
    in
    {
      inherit
        coreInputs
        inputs
        outputs
        settings
        substrate
        ;

      # The context an output builder receives. Extensions destructure these
      # directly, so they are the contract, not an implementation detail.
      globalArgs = { inherit coreInputs inputs substrate; };
      perSystemArgs = system: pkgs: {
        inherit
          coreInputs
          inputs
          pkgs
          substrate
          system
          ;
      };

      # A function rather than a value: a builder that shares one package set
      # across output names (flake-parts) and one that builds a set per name
      # (the plain builders) both want this.
      pkgsFor =
        system:
        import nixpkgsInput {
          inherit system;
          inherit (settings) overlays;
          config = settings.nixpkgsConfig;
        };

      # Every output builder registered for a name contributes to that one
      # output, so they are merged rather than picked between.
      merge = args: builders: lib.foldl' (acc: builder: acc // builder.build args) { } builders;
    };

  # Evaluates a substrate module, then hands the result to `fromConfig`. This
  # is what a builder that is not itself a module system uses.
  fromModule =
    {
      lib,
      inputs,
      module,
      coreInputs ? defaultCoreInputs inputs,
    }:
    fromConfig {
      inherit
        coreInputs
        inputs
        lib
        ;
      substrate =
        (lib.evalModules {
          modules = [ module ];
          specialArgs = { inherit coreInputs inputs; };
        }).config.substrate;
    };
}
