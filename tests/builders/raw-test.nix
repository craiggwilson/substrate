# Tests for the raw substrate builder
{
  pkgs ? import <nixpkgs> { },
  # The nixpkgs source to use as the raw builder's nixpkgs input. Defaults to
  # <nixpkgs> (a plain path — the pinned-source shape); flake.nix passes its
  # flake input (the flake shape), so both input shapes get exercised.
  nixpkgsSrc ? <nixpkgs>,
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib runTests;

  substrate = import ../..;
  mkRaw =
    module:
    substrate.build.raw {
      inputs = {
        nixpkgs = nixpkgsSrc;
      };
    } module;

  oneSystemModule = {
    substrate.settings.systems = [ "x86_64-linux" ];
  };
in
runTests "Raw Builder Tests" {
  nixosConfigurationsBuilt = {
    check =
      let
        result = mkRaw {
          imports = [
            oneSystemModule
            ../../extensions/nixos
          ];
          substrate.hosts.testhost.system = "x86_64-linux";
        };
      in
      result.nixosConfigurations.testhost.config.networking.hostName == "testhost"
      # Both input shapes pin the nixpkgs the system was built with
      # (nixpkgs.flake.source), matching what nixpkgs' flake entry point does —
      # the invariant that makes a flake-pinned and npins-pinned build of the
      # same nixpkgs revision produce the same system.
      && result.nixosConfigurations.testhost.config.nixpkgs.flake.source != null;
  };

  checksOutputEmitted = {
    check =
      let
        result = mkRaw oneSystemModule;
      in
      lib.isDerivation result.checks.x86_64-linux.substrate-config;
  };

  inputsReachModules = {
    check =
      let
        result = mkRaw (
          { inputs, ... }:
          {
            imports = [ oneSystemModule ];
            substrate.settings.checks = [
              {
                name = "inputs-visible";
                valid = inputs ? nixpkgs;
                warn = false;
                message = "inputs not passed as module args";
              }
            ];
          }
        );
      in
      lib.isDerivation result.checks.x86_64-linux.substrate-config;
  };

  failingCheckThrows = {
    check =
      let
        result = mkRaw {
          imports = [ oneSystemModule ];
          substrate.settings.checks = [
            {
              name = "always-fails";
              valid = false;
              warn = false;
              message = "boom";
            }
          ];
        };
      in
      !(builtins.tryEval (lib.isDerivation result.checks.x86_64-linux.substrate-config)).success;
  };

  warningCheckPasses = {
    check =
      let
        result = mkRaw {
          imports = [ oneSystemModule ];
          substrate.settings.checks = [
            {
              name = "always-warns";
              valid = false;
              warn = true;
              message = "boom";
            }
          ];
        };
      in
      lib.isDerivation result.checks.x86_64-linux.substrate-config;
  };
}
