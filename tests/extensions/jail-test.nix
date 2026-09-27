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

  eval = lib.evalModules {
    modules = [
      ../../core/settings.nix
      ../../core/lib.nix
      ../../extensions/jail/default.nix
    ];
    specialArgs = {
      inputs = {
        jail-nix = fakeJailNix;
      };
    };
  };

  moduleArgs = eval.config.substrate.lib.extraArgsGenerator {
    hostcfg = null;
    usercfg = null;
    inputs = { };
    pkgs = {
      tag = "host-pkgs";
    };
  };
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
}
