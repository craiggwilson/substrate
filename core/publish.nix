# Publishing: one namespace for everything a configuration exposes to
# consumers.
#
# `substrate.settings.publishers` is the registry that several extensions used
# to keep a private copy of. An extension that wants to expose something
# declares its own key under `substrate.publish` with a type that fits, and
# registers where that key should land; it never touches `substrate.outputs`
# itself. This is core rather than an extension because it is about outputs,
# which are core vocabulary -- the same relationship `settings.overlays` has to
# the package sets builders create.
#
# A key is one namespace reaching one output in one scope. Anything needing more
# than that -- a namespace that also contributes an overlay, say -- keeps its
# additional output builder directly, the way any module can.
{ lib, config, ... }:
let
  inherit (config.substrate) settings;

  # What a published module set may hold. All three shapes appear in real module
  # sets: a path to a module file, an attrset, or a function module taking
  # `{ config, ... }`. `deferredModule` alone covers only attrsets -- it checks
  # `isAttrs`, so a function module would be rejected at the point of publishing
  # rather than at the point of use.
  moduleType = lib.types.either lib.types.path (
    lib.types.either lib.types.deferredModule (lib.types.functionTo lib.types.anything)
  );
in
{
  # One vocabulary for "this is a module", so every extension that publishes
  # modules types them the same way and a consumer can rely on it.
  config.substrate.lib.publishedModuleType = moduleType;

  options.substrate.publish = lib.mkOption {
    # A submodule with no freeform type, so an extension declares its own key as
    # a child option with the type that fits it, and assigning a key whose
    # declaring extension is absent is an error naming the key rather than a
    # value quietly reaching no output.
    type = lib.types.submodule {
      options = {
        # The marker for "my module tree is a library another configuration can
        # consume". Everything in the tree is a substrate module; only what is
        # named here is meant to be read by someone else. A configuration that
        # publishes nothing here can still use its tree freely for itself.
        substrateModules = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          description = ''
            The module tree published for other configurations to consume. A
            consumer assigns it straight into its own tree:

              substrate.modules = inputs.mylib.substrateModules;

            The tree's own type is checked where it is consumed, against
            `substrate.modules`, so this only insists it is an attribute set.
          '';
        };
      };
    };
    description = ''
      Values this configuration exposes to consumers, one key per published
      output. Each key is declared by the extension that owns it. Assignment is
      how a configuration publishes:

        substrate.publish.nixosModules = {
          myModule = { config, pkgs, ... }: { };
        };

      What turns a key into an output is its registration under
      `substrate.settings.publishers`, not the assignment.
    '';
    default = { };
  };

  config.substrate = {
    settings.publishers.substrateModules = {
      scope = "global";
      output = "substrateModules";
      build = { substrate, ... }: substrate.publish.substrateModules;
    };

    # One output builder per registered key, grouped by where it lands so two
    # keys sharing an output name contribute builders to the same list rather
    # than one replacing the other. Nothing here knows what a key means: the
    # value was declared by whoever registered it and `build` is their function,
    # so a key can hold modules, derivations, or overlays.
    outputs =
      let
        byScope = lib.groupBy (p: p.scope) (lib.attrValues settings.publishers);
      in
      lib.mapAttrs (
        _scope: scoped:
        lib.mapAttrs (
          _output: same:
          map (p: {
            inherit (p) build;
          }) same
        ) (lib.groupBy (p: p.output) scoped)
      ) byScope;
  };
}
