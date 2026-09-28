# Tests for substrate home-manager extension
# Run with: nix eval -f substrate/tests/extensions/home-manager-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib)
    lib
    mkEvalSubstrate
    evalSubstrate
    runTests
    ;

  # Rename the base evaluator for clarity
  evalSubstrateBase = evalSubstrate;

  # Evaluate substrate with home-manager extension
  evalSubstrateWithHM = mkEvalSubstrate [
    ../../core/settings.nix
    ../../core/lib.nix
    ../../core/modules.nix
    ../../core/finders.nix
    ../../core/hosts.nix
    ../../core/users.nix
    ../../core/outputs.nix
    ../../core/checks.nix
    ../../extensions/overlays/default.nix
    ../../extensions/nixos/default.nix
    ../../extensions/home-manager/default.nix
  ];

  tests = {
    # Test 1: homeManager class is not supported without extension
    homeManagerNotSupportedWithoutExtension = {
      check =
        let
          eval = evalSubstrateBase [ ];
          hasClass = eval.config.substrate.lib.hasClass;
        in
        hasClass "homeManager" == false;
    };

    # Test 2: homeManager class is supported with extension
    homeManagerSupportedWithExtension = {
      check =
        let
          eval = evalSubstrateWithHM [ ];
          hasClass = eval.config.substrate.lib.hasClass;
        in
        hasClass "homeManager" == true;
    };

    # Test 3: homeManagerModules option exists with extension
    homeManagerModulesOptionExists = {
      check =
        let
          eval = evalSubstrateWithHM [ ];
        in
        eval.config.substrate.settings ? homeManagerModules;
    };

    # Test 4: homeManagerModules defaults to empty list
    homeManagerModulesDefaultEmpty = {
      check =
        let
          eval = evalSubstrateWithHM [ ];
        in
        eval.config.substrate.settings.homeManagerModules == [ ];
    };

    # Test 5: Module can have homeManager content with extension
    moduleCanHaveHomeManager = {
      check =
        let
          eval = evalSubstrateWithHM [
            {
              config.substrate.modules.programs.test = {
                homeManager = {
                  programs.git.enable = true;
                };
              };
            }
          ];
        in
        eval.config.substrate.modules.programs.test.homeManager != null;
    };

    # Test 6: findModulesForClass works for homeManager
    findModulesForClassHomeManager = {
      check =
        let
          eval = evalSubstrateWithHM [
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
                nixos = { };
                homeManager = null;
              };
            }
          ];
          findModulesForClass = eval.config.substrate.lib.findModulesForClass;
        in
        lib.length (findModulesForClass "homeManager" [ ]) == 1;
    };

    # Test 7: Both nixos and homeManager can coexist
    nixosAndHomeManagerCoexist = {
      check =
        let
          eval = evalSubstrateWithHM [
            {
              config.substrate.modules.programs.git = {
                nixos = {
                  programs.git.enable = true;
                };
                homeManager = {
                  programs.git.userName = "test";
                };
              };
            }
          ];
          mod = eval.config.substrate.modules.programs.git;
        in
        mod.nixos != null && mod.homeManager != null;
    };

    # Test 8: supportedClasses includes both nixos and homeManager
    supportedClassesIncludesBoth = {
      check =
        let
          eval = evalSubstrateWithHM [ ];
          classes = eval.config.substrate.settings.supportedClasses;
        in
        lib.elem "nixos" classes && lib.elem "homeManager" classes;
    };

    # Test 9: core is implementation-agnostic (nixosModules only exists with the nixos extension)
    coreHasNoNixosModules = {
      check =
        let
          eval = evalSubstrateBase [ ];
        in
        !(eval.config.substrate.settings ? nixosModules);
    };

    # Test 10: perHostContributors defaults to empty without the extension
    perHostContributorsDefaultEmpty = {
      check =
        let
          eval = evalSubstrateBase [ ];
        in
        eval.config.substrate.settings.perHostContributors == [ ];
    };

    # Test 11: perUserContributors defaults to empty without the extension
    perUserContributorsDefaultEmpty = {
      check =
        let
          eval = evalSubstrateBase [ ];
        in
        eval.config.substrate.settings.perUserContributors == [ ];
    };

    # Test 12: home-manager extension pushes one per-host contributor
    homeManagerPushesPerHostContributor = {
      check =
        let
          eval = evalSubstrateWithHM [ ];
        in
        lib.length eval.config.substrate.settings.perHostContributors == 1;
    };

    # Test 13: the per-host contributor produces a home-manager module per user
    perHostContributorProducesHomeManagerModule = {
      check =
        let
          eval = evalSubstrateWithHM [
            {
              config.substrate.modules.programs.test.homeManager = {
                programs.git.enable = true;
              };
            }
          ];
          contributor = builtins.head eval.config.substrate.settings.perHostContributors;
          modules = contributor {
            inputs = {
              home-manager.nixosModules.home-manager = { };
            };
            substrate = eval.config.substrate;
            hostname = "testhost";
            hostcfg = {
              users = [ "alice" ];
              system = "x86_64-linux";
            };
            userConfigs = [ { name = "alice"; } ];
            pkgs = { };
          };
          hmModule = builtins.elemAt modules 1;
        in
        lib.length modules == 2 && hmModule ? home-manager && hmModule.home-manager.users ? alice;
    };

    # Test 14: per-user contributors reach NixOS-embedded user modules
    perUserContributorsReachEmbeddedUsers = {
      check =
        let
          eval = evalSubstrateWithHM [
            {
              config.substrate.settings.perUserContributors = [
                (_: [ "sentinel-user-module" ])
              ];
            }
          ];
          contributor = builtins.head eval.config.substrate.settings.perHostContributors;
          modules = contributor {
            inputs = {
              home-manager.nixosModules.home-manager = { };
            };
            substrate = eval.config.substrate;
            hostname = "testhost";
            hostcfg = {
              users = [ "alice" ];
              system = "x86_64-linux";
            };
            userConfigs = [ { name = "alice"; } ];
            pkgs = { };
          };
          userModule = (builtins.elemAt modules 1).home-manager.users.alice;
        in
        lib.elem "sentinel-user-module" userModule.imports;
    };
  };
in
runTests "Home-Manager Extension Tests" tests
