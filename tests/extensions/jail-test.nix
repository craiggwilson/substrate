# Tests for substrate jail extension
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib)
    lib
    runTests
    ;

  fakeJailNix = {
    lib = {
      extend = p: {
        pkgsTag = p.tag or null;
        mkJail = { name, ... }: "jail:${name}";
      };
    };
  };

  baseModules = [
    ../../core/settings.nix
    ../../core/lib.nix
    ../../extensions/jail/default.nix
  ];

  moduleArgsFrom =
    eval:
    eval.config.substrate.lib.extraArgsGenerator {
      hostcfg = null;
      usercfg = null;
      inputs = { };
      pkgs = {
        tag = "host-pkgs";
      };
    };

  # resolved via the conventional input name
  eval = lib.evalModules {
    modules = baseModules;
    specialArgs = {
      inputs = {
        jail-nix = fakeJailNix;
      };
    };
  };

  moduleArgs = moduleArgsFrom eval;

  # resolved via substrate.settings.inputs when the flake names it differently
  evalViaSettings = lib.evalModules {
    modules = baseModules ++ [
      {
        config.substrate.settings.inputs."jail-nix" = fakeJailNix;
      }
    ];
    specialArgs = {
      inputs = { };
    };
  };

  moduleArgsViaSettings = moduleArgsFrom evalViaSettings;
in
runTests "Jail Extension Tests" {
  # Test 1: modules receive a pkgs-bound jailLib with mkJail directly usable
  jailLibIsPkgsBound = {
    check =
      moduleArgs.jailLib.pkgsTag == "host-pkgs"
      && moduleArgs.jailLib.mkJail { name = "web"; } == "jail:web";
  };

  # Test 2: the old raw-lib `jail` argument is gone
  rawJailArgRemoved = {
    check = !(moduleArgs ? jail);
  };

  # Test 3: settings.inputs provides the input when the flake lacks the name
  jailLibViaSettingsInputs = {
    check =
      moduleArgsViaSettings.jailLib.pkgsTag == "host-pkgs"
      && moduleArgsViaSettings.jailLib.mkJail { name = "db"; } == "jail:db";
  };
}
