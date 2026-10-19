# Tests for the core publishing mechanism: `substrate.publish` keys and the
# `substrate.settings.publishers` registry that turns them into outputs.
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib mkEvalSubstrate runTests;

  core = [
    ../../core/settings.nix
    ../../core/lib.nix
    ../../core/modules.nix
    ../../core/finders.nix
    ../../core/outputs.nix
    ../../core/overlays.nix
    ../../core/publish.nix
  ];

  # A stand-in publisher: the mechanism is meant to work without any particular
  # extension, so the test declares its own keys rather than borrowing one.
  globalPublisher = {
    options.substrate.publish.thingies = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
    config.substrate.settings.publishers.thingies = {
      scope = "global";
      output = "thingies";
      build = { substrate, ... }: substrate.publish.thingies;
    };
  };

  # A second key landing on the same output name. Builders must merge rather
  # than one replacing the other.
  secondPublisher = {
    config.substrate.settings.publishers.moreThingies = {
      scope = "global";
      output = "thingies";
      build = { substrate, ... }: substrate.publish.thingies;
    };
  };

  perSystemPublisher = {
    options.substrate.publish.widgets = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
    };
    config.substrate.settings.publishers.widgets = {
      scope = "perSystem";
      output = "widgets";
      build = { substrate, ... }: substrate.publish.widgets;
    };
  };

  evalWith = extra: modules: mkEvalSubstrate core (modules ++ extra);

  tests = {
    # -- the mechanism -------------------------------------------------------

    aRegisteredKeyBecomesAnOutput = {
      check =
        let
          eval =
            evalWith
              [ globalPublisher ]
              [
                {
                  config.substrate.publish.thingies.alpha = 1;
                }
              ];
        in
        (builtins.length eval.config.substrate.outputs.global.thingies) == 1;
    };

    # The builder is handed the standard output-builder context, not a context
    # of publish's own: `inputs`, `coreInputs` and `substrate`, plus `pkgs` and
    # `system` when the key is per-system.
    theBuilderReadsTheKeyOffSubstrate = {
      check =
        let
          eval =
            evalWith
              [ globalPublisher ]
              [
                {
                  config.substrate.publish.thingies.alpha = 1;
                }
              ];
          built = (builtins.head eval.config.substrate.outputs.global.thingies).build {
            substrate = eval.config.substrate;
          };
        in
        built == {
          alpha = 1;
        };
    };

    scopeDecidesWhereTheOutputLands = {
      check =
        let
          eval = evalWith [ globalPublisher perSystemPublisher ] [ ];
        in
        builtins.attrNames eval.config.substrate.outputs.global == [
          "substrateModules"
          "thingies"
        ]
        && builtins.attrNames eval.config.substrate.outputs.perSystem == [ "widgets" ];
    };

    twoKeysOnOneOutputMergeIntoOneBuilderList = {
      check =
        let
          eval =
            evalWith
              [ globalPublisher secondPublisher ]
              [
                {
                  config.substrate.publish.thingies.alpha = 1;
                }
              ];
        in
        (builtins.length eval.config.substrate.outputs.global.thingies) == 2;
    };

    # A key nothing declares is an error naming the key, not a value that quietly
    # reaches no output. That matters because assigning a publish key is how a
    # configuration says "this is for consumers", and a typo there would
    # otherwise publish nothing at all and silently.
    anUndeclaredKeyIsRejected = {
      check =
        let
          eval = evalWith [ ] [ { config.substrate.publish.typoedKey = 1; } ];
        in
        !(lib.tryEval eval.config.substrate.publish.typoedKey).success;
    };

    # -- the key core declares ----------------------------------------------

    substrateModulesIsPublishedGlobally = {
      check =
        let
          eval =
            evalWith
              [ ]
              [
                (
                  { config, ... }:
                  {
                    substrate.modules.programs.foo.nixos = { };
                    substrate.publish.substrateModules = config.substrate.modules;
                  }
                )
              ];
          builders = eval.config.substrate.outputs.global.substrateModules;
          built = (builtins.head builders).build { substrate = eval.config.substrate; };
        in
        (builtins.length builders) == 1 && (builtins.attrNames built) == [ "programs" ];
    };

    # Assigning the tree is what publishes it: with nothing assigned the output
    # is still there, carrying nothing. A configuration can use its module tree
    # freely without marking itself as a library.
    anUnmarkedTreeIsStillUsableLocally = {
      check =
        let
          eval =
            evalWith
              [ ]
              [
                {
                  config.substrate.modules.programs.foo.nixos = { };
                }
              ];
          built = (builtins.head eval.config.substrate.outputs.global.substrateModules).build {
            substrate = eval.config.substrate;
          };
        in
        built == { } && (eval.config.substrate.modules.programs.foo ? nixos);
    };
  };
in
runTests "Publishing Tests" tests
