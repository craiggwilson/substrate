# Tests for substrate.lib functions
# Run with: nix eval -f substrate/tests/core/lib-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib)
    lib
    minimalCoreModules
    mkEvalSubstrate
    runTests
    ;

  # Use minimal core modules for lib tests (no extensions needed)
  # Add nixos and homeManager to supportedClasses for tests that need them
  evalSubstrate = mkEvalSubstrate (
    minimalCoreModules
    ++ [
      {
        config.substrate.settings.supportedClasses = [
          "nixos"
          "homeManager"
        ];
      }
    ]
  );

  tests = {
    # Test 1: unique deduplicates list preserving order
    uniqueDeduplicates = {
      check =
        let
          eval = evalSubstrate [ ];
          unique = eval.config.substrate.lib.unique;
        in
        unique [
          1
          2
          3
          2
          1
          4
        ] == [
          1
          2
          3
          4
        ];
    };

    # Test 2: unique preserves order
    uniquePreservesOrder = {
      check =
        let
          eval = evalSubstrate [ ];
          unique = eval.config.substrate.lib.unique;
        in
        unique [
          "c"
          "a"
          "b"
          "a"
          "c"
        ] == [
          "c"
          "a"
          "b"
        ];
    };

    # Test 3: unique handles empty list
    uniqueEmptyList = {
      check =
        let
          eval = evalSubstrate [ ];
          unique = eval.config.substrate.lib.unique;
        in
        unique [ ] == [ ];
    };

    # Test 4: findModulesForClass finds nixos modules
    findModulesForClassNixos = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.modules.programs.test1 = {
                nixos = {
                  enable = true;
                };
              };
            }
            {
              config.substrate.modules.programs.test2 = {
                nixos = {
                  enable = false;
                };
              };
            }
          ];
          findModulesForClass = eval.config.substrate.lib.findModulesForClass;
        in
        lib.length (findModulesForClass "nixos" [ ]) == 2;
    };

    # Test 5: findModulesForClass filters modules without the class
    findModulesForClassFiltersOtherClasses = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.modules.programs.test1 = {
                nixos = null;
                homeManager = {
                  config = { };
                };
              };
            }
            {
              config.substrate.modules.programs.test2 = {
                nixos = {
                  enable = true;
                };
              };
            }
          ];
          findModulesForClass = eval.config.substrate.lib.findModulesForClass;
        in
        lib.length (findModulesForClass "nixos" [ ]) == 1;
    };

    # Test 6: hasClass returns true for supported class
    hasClassSupported = {
      check =
        let
          eval = evalSubstrate [ ];
          hasClass = eval.config.substrate.lib.hasClass;
        in
        hasClass "nixos" == true;
    };

    # Test 7: hasClass returns false for unsupported class
    hasClassUnsupported = {
      check =
        let
          eval = evalSubstrate [ ];
          hasClass = eval.config.substrate.lib.hasClass;
        in
        hasClass "nonexistentClass" == false;
    };

    # Test 8: extraArgsGenerator returns empty attrs with no generators
    extraArgsGeneratorEmpty = {
      check =
        let
          eval = evalSubstrate [ ];
          extraArgsGenerator = eval.config.substrate.lib.extraArgsGenerator;
          args = extraArgsGenerator {
            hostcfg = null;
            usercfg = null;
            inputs = null;
            pkgs = { };
          };
        in
        args == { };
    };

    # The generated set is the plain merge of every generator's contribution --
    # no self-reference. An argument whose value depends on the configuration is
    # published by a class module writing `_module.args` instead (a generator
    # runs in the builder, outside the configuration being built), and a class
    # module extending one does it with lib.mkForce.
    extraArgsGeneratorMergesPlainly = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.extraArgsGenerators = [
                (_: { foo = "bar"; })
              ];
            }
          ];
          args = eval.config.substrate.lib.extraArgsGenerator {
            hostcfg = null;
            usercfg = null;
            inputs = null;
            pkgs = { };
          };
        in
        args == {
          foo = "bar";
        };
    };

    # Test 9: extraArgsGenerator merges multiple generators
    extraArgsGeneratorMerges = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.extraArgsGenerators = [
                (_: { foo = "bar"; })
                (_: { baz = 42; })
              ];
            }
          ];
          extraArgsGenerator = eval.config.substrate.lib.extraArgsGenerator;
          args = extraArgsGenerator {
            hostcfg = null;
            usercfg = null;
            inputs = null;
            pkgs = { };
          };
        in
        args.foo == "bar" && args.baz == 42;
    };

    # Test 9a: generators receive pkgs and can return pkgs-bound helpers
    extraArgsGeneratorReceivesPkgs = {
      check =
        let
          fakePkgs = {
            tag = "host-pkgs";
          };
          eval = evalSubstrate [
            {
              config.substrate.settings.extraArgsGenerators = [
                ({ pkgs, ... }: { bound = pkgs.tag; })
              ];
            }
          ];
          args = eval.config.substrate.lib.extraArgsGenerator {
            hostcfg = null;
            usercfg = null;
            inputs = null;
            pkgs = fakePkgs;
          };
        in
        args.bound == "host-pkgs";
    };

    # Test 9b: static helpers arrive as flat args, substrate.lib stays out
    extraArgsGeneratorFlatAndIsolated = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.extraArgsGenerators = [
                (_: { myHelper = x: x; })
              ];
            }
          ];
          args = eval.config.substrate.lib.extraArgsGenerator {
            hostcfg = null;
            usercfg = null;
            inputs = null;
            pkgs = { };
          };
        in
        (args.myHelper 1) == 1 && !(args ? hasClass) && !(args ? findModulesForClass);
    };

    # Test 10: findModulesForClass includes generic modules for nixos
    findModulesForClassIncludesGenericForNixos = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.modules.programs.test1 = {
                generic = {
                  shared = true;
                };
                nixos = null;
              };
            }
            {
              config.substrate.modules.programs.test2 = {
                generic = null;
                nixos = {
                  enable = true;
                };
              };
            }
          ];
          findModulesForClass = eval.config.substrate.lib.findModulesForClass;
        in
        lib.length (findModulesForClass "nixos" [ ]) == 2;
    };

    # Test 11: findModulesForClass includes generic modules for homeManager
    findModulesForClassIncludesGenericForHomeManager = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.modules.programs.test1 = {
                generic = {
                  shared = true;
                };
                homeManager = null;
              };
            }
            {
              config.substrate.modules.programs.test2 = {
                generic = null;
                homeManager = {
                  config = { };
                };
              };
            }
          ];
          findModulesForClass = eval.config.substrate.lib.findModulesForClass;
        in
        lib.length (findModulesForClass "homeManager" [ ]) == 2;
    };

    # Test 12: findModulesForClass with both generic and specific modules
    findModulesForClassBothGenericAndSpecific = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.modules.programs.test = {
                generic = {
                  shared = true;
                };
                nixos = {
                  specific = true;
                };
              };
            }
          ];
          findModulesForClass = eval.config.substrate.lib.findModulesForClass;
          result = findModulesForClass "nixos" [ ];
        in
        lib.length result == 2;
    };

    # Test 13: findModulesForClass for generic class does not double-include generic
    findModulesForClassGenericClassNoDoubleInclude = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.modules.programs.test = {
                generic = {
                  shared = true;
                };
                nixos = null;
              };
            }
          ];
          findModulesForClass = eval.config.substrate.lib.findModulesForClass;
        in
        lib.length (findModulesForClass "generic" [ ]) == 1;
    };

    # Test 14: nameFromPath extracts name from file path
    nameFromPathFile = {
      check =
        let
          eval = evalSubstrate [ ];
          nameFromPath = eval.config.substrate.lib.nameFromPath;
        in
        nameFromPath "/foo/bar/baz.nix" == "baz";
    };

    # Test 15: nameFromPath extracts name from directory path
    nameFromPathDir = {
      check =
        let
          eval = evalSubstrate [ ];
          nameFromPath = eval.config.substrate.lib.nameFromPath;
        in
        nameFromPath "/foo/bar/baz" == "baz";
    };

    # Test 16: resolveInput falls back to the input of the same name
    resolveInputByName = {
      check =
        let
          eval = evalSubstrate [ ];
          resolveInput = eval.config.substrate.lib.resolveInput;
        in
        (resolveInput "nixpkgs" { nixpkgs = "by-name"; }) == "by-name";
    };

    # Test 17: settings.inputs overrides win over name lookup
    resolveInputSettingsOverride = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.inputs.nixpkgs = "from-settings";
            }
          ];
          resolveInput = eval.config.substrate.lib.resolveInput;
        in
        (resolveInput "nixpkgs" { nixpkgs = "by-name"; }) == "from-settings";
    };

    # Test 18: resolveInput throws with guidance when no input is found
    resolveInputMissingThrows = {
      check =
        let
          eval = evalSubstrate [ ];
          resolveInput = eval.config.substrate.lib.resolveInput;
          result = builtins.tryEval (resolveInput "jail-nix" { });
        in
        !result.success;
    };
  };
in
runTests "Lib Tests" tests
