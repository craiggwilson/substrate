# Tests for substrate output builder schema
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib runTests;

  evalSubstrate =
    mk:
    lib.evalModules {
      modules = [
        ../../core/settings.nix
        ../../core/lib.nix
        ../../core/outputs.nix
        mk
      ];
    };
in
runTests "Outputs Tests" {
  # Test 1: both categories default to empty
  defaultsEmpty = {
    check =
      let
        eval = evalSubstrate { };
      in
      eval.config.substrate.outputs.global == { } && eval.config.substrate.outputs.perSystem == { };
  };

  # Test 2: builders registered under a category are readable and callable,
  # returning the attrset the output name is built from
  builderRegistration = {
    check =
      let
        eval = evalSubstrate {
          config.substrate.outputs = {
            global.nixosConfigurations = [
              {
                build =
                  # `substrate` is accepted (and ignored) on purpose: the test
                  # passes it to assert builders tolerate extra builder args.
                  { inputs, ... }:
                  {
                    inherited = inputs;
                  };
              }
            ];
            perSystem.packages = [
              {
                build =
                  { system, ... }:
                  {
                    hello = system;
                  };
              }
            ];
          };
        };
        outputs = eval.config.substrate.outputs;
      in
      (builtins.head outputs.global.nixosConfigurations).build {
        inputs = "i";
        substrate = "s";
      } == {
        inherited = "i";
      }
      &&
        (builtins.head outputs.perSystem.packages).build {
          pkgs = { };
          system = "x86_64-linux";
          inputs = { };
          substrate = { };
        } == {
          hello = "x86_64-linux";
        };
  };

  # Test 3: builders from multiple modules for the same output name accumulate
  buildersMergeAcrossModules = {
    check =
      let
        eval = lib.evalModules {
          modules = [
            ../../core/settings.nix
            ../../core/lib.nix
            ../../core/outputs.nix
            {
              config.substrate.outputs.perSystem.packages = [
                {
                  build = _: { };
                }
              ];
            }
            {
              config.substrate.outputs.perSystem.packages = [
                {
                  build = _: { };
                }
              ];
            }
          ];
        };
      in
      builtins.length eval.config.substrate.outputs.perSystem.packages == 2;
  };
}
