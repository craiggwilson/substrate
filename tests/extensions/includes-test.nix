# Tests for substrate includes extension
# Run with: nix eval -f substrate/tests/extensions/includes-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib mkEvalSubstrate runTests;

  evalSubstrate = mkEvalSubstrate [
    ../../core/settings.nix
    ../../core/lib.nix
    ../../core/modules.nix
    ../../core/finders.nix
    ../../core/hosts.nix
    ../../core/users.nix
    ../../core/outputs.nix
    ../../core/overlays.nix
    ../../core/checks.nix
    ../../extensions/nixos/default.nix
    ../../extensions/includes/default.nix
  ];

  tests = {
    hostIncludesModuleClosure = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.supportedClasses = [ "nixos" ];
              config.substrate.hosts.workstation.includes = [ "desktop" ];
              config.substrate.modules.desktop = {
                includes = [ "gui" ];
                nixos = { };
              };
              config.substrate.modules.gui = {
                nixos = { };
              };
            }
          ];
          found = eval.config.substrate.moduleFinders.by-includes.find [ eval.config.substrate.hosts.workstation ];
        in
        lib.length found == 2;
    };

    moduleIncludesTransitively = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.supportedClasses = [ "nixos" ];
              config.substrate.hosts.workstation.includes = [ "desktop" ];
              config.substrate.modules.desktop = {
                includes = [ "gui" ];
                nixos = { };
              };
              config.substrate.modules.gui = {
                includes = [ "wayland" ];
                nixos = { };
              };
              config.substrate.modules.wayland = {
                nixos = { };
              };
            }
          ];
          found = eval.config.substrate.moduleFinders.by-includes.find [ eval.config.substrate.hosts.workstation ];
        in
        lib.length found == 3;
    };

    missingModulePathFails = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.supportedClasses = [ "nixos" ];
              config.substrate.hosts.workstation.includes = [ "missing" ];
              config.substrate.modules.desktop = {
                nixos = { };
              };
            }
          ];
          result = builtins.tryEval (builtins.deepSeq (eval.config.substrate.moduleFinders.by-includes.find [ eval.config.substrate.hosts.workstation ]) true);
        in
        !result.success;
    };

    cycleFails = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.supportedClasses = [ "nixos" ];
              config.substrate.hosts.workstation.includes = [ "desktop" ];
              config.substrate.modules.desktop = {
                includes = [ "gui" ];
                nixos = { };
              };
              config.substrate.modules.gui = {
                includes = [ "desktop" ];
                nixos = { };
              };
            }
          ];
          result = builtins.tryEval (builtins.deepSeq (eval.config.substrate.moduleFinders.by-includes.find [ eval.config.substrate.hosts.workstation ]) true);
        in
        !result.success;
    };
  };
in
runTests "Includes Tests" tests
