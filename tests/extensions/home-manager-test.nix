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

  # Flake-shaped stubs for inputs the home-manager extension resolves.
  fakeNixpkgs = pkgs.writeText "fake-nixpkgs" "_: { }" // {
    inherit (pkgs) lib;
  };

  fakeHomeManager = {
    outPath = pkgs.path;
    lib.homeManagerConfiguration = args: { inherit (args) extraSpecialArgs; };
    nixosModules.home-manager = { };
  };

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

    # Test 10: contributors defaults to empty without the extension
    contributorsDefaultEmpty = {
      check =
        let
          eval = evalSubstrateBase [ ];
        in
        eval.config.substrate.settings.contributors == [ ];
    };

    # Test 11: home-manager extension pushes one nixos-class contributor
    homeManagerPushesNixosContributor = {
      check =
        let
          eval = evalSubstrateWithHM [ ];
          entries = eval.config.substrate.settings.contributors;
        in
        lib.length entries == 1 && builtins.head entries ? class;
    };

    # Test 12: contributionsFor "nixos" produces a home-manager module per user
    contributionsForNixosProducesHomeManagerModule = {
      check =
        let
          eval = evalSubstrateWithHM [
            {
              config.substrate.modules.programs.test.homeManager = {
                programs.git.enable = true;
              };
            }
          ];
          modules = eval.config.substrate.lib.contributionsFor "nixos" {
            inputs = {
              home-manager = fakeHomeManager;
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

    # Test 13: contributionsFor ignores other classes
    contributionsForFiltersByClass = {
      check =
        let
          eval = evalSubstrateBase [
            {
              config.substrate.settings.contributors = [
                {
                  class = "homeManager";
                  contribute = _: [ "hm-module" ];
                }
              ];
            }
          ];
        in
        eval.config.substrate.lib.contributionsFor "nixos" { } == [ ]
        && eval.config.substrate.lib.contributionsFor "homeManager" { } == [ "hm-module" ];
    };

    # Test 14: homeManager-class contributions reach NixOS-embedded users
    homeManagerContributionsReachEmbeddedUsers = {
      check =
        let
          eval = evalSubstrateWithHM [
            {
              config.substrate.settings.contributors = [
                {
                  class = "homeManager";
                  contribute = _: [ "sentinel-user-module" ];
                }
              ];
            }
          ];
          modules = eval.config.substrate.lib.contributionsFor "nixos" {
            inputs = {
              home-manager = fakeHomeManager;
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

    # Test 15: a user attached to no host builds nothing (no vanilla config)
    userWithNoHostBuildsNothing = {
      check =
        let
          eval = evalSubstrateWithHM [
            {
              config.substrate.users.alice = { };
            }
          ];
          configs = (builtins.head eval.config.substrate.outputs.global.homeConfigurations).build {
            inputs = {
              # Stub inputs so the builder runs its real code path without
              # evaluating a second nixpkgs or a full home-manager config.
              nixpkgs = fakeNixpkgs;
              home-manager = fakeHomeManager;
            };
            substrate = eval.config.substrate;
          };
        in
        configs == { };
    };

    # Test 16: a user of a home-only host gets a host-scoped config keyed
    # <user>@<host> whose host/hostcfg/userName arguments are populated
    homeOnlyHostGetsHostScopedConfig = {
      check =
        let
          eval = evalSubstrateWithHM [
            {
              config.substrate.users.alice = { };
              config.substrate.hosts.homey = {
                system = "x86_64-linux";
                usersOnly = true;
                users = [ "alice" ];
              };
            }
          ];
          configs = (builtins.head eval.config.substrate.outputs.global.homeConfigurations).build {
            inputs = {
              nixpkgs = fakeNixpkgs;
              home-manager = fakeHomeManager;
            };
            substrate = eval.config.substrate;
          };
        in
        # only the host-scoped config exists - no vanilla one alongside it
        builtins.attrNames configs == [ "alice@homey" ]
        && configs."alice@homey".extraSpecialArgs.host == "homey"
        && configs."alice@homey".extraSpecialArgs.hostcfg.name == "homey"
        && configs."alice@homey".extraSpecialArgs.userName == "alice";
    };

    # Test 17: a system host (usersOnly = false, the default) yields no
    # homeConfigurations entry (its HM is delivered by host-integration in NixOS)
    systemHostYieldsNoHostScopedConfig = {
      check =
        let
          eval = evalSubstrateWithHM [
            {
              config.substrate.users.alice = { };
              config.substrate.hosts.server = {
                system = "x86_64-linux";
                users = [ "alice" ];
              };
            }
          ];
          configs = (builtins.head eval.config.substrate.outputs.global.homeConfigurations).build {
            inputs = {
              nixpkgs = fakeNixpkgs;
              home-manager = fakeHomeManager;
            };
            substrate = eval.config.substrate;
          };
        in
        configs == { };
    };
  };
in
runTests "Home-Manager Extension Tests" tests
