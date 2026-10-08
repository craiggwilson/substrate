# Tests for the raw substrate builder
{
  pkgs ? import <nixpkgs> { },
  # nixpkgs input passed to the raw builder. flake.nix supplies the real flake
  # input; the default provides a flake-shaped wrapper around <nixpkgs> so the
  # tests also work when evaluated directly.
  nixpkgsSrc ? {
    outPath = pkgs.path;
    inherit (pkgs) lib;
  },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib runTests;

  substrate = import ../..;
  mkRaw = inputs: module: substrate.build.raw { inherit inputs; } module;
  mkRawWithCoreInputs =
    inputs: coreInputs: module:
    substrate.build.raw { inherit inputs coreInputs; } module;

  oneSystemModule = {
    substrate.settings.systems = [ "x86_64-linux" ];
  };
in
runTests "Raw Builder Tests" {
  nixosConfigurationsBuilt = {
    check =
      let
        result = mkRaw { nixpkgs = nixpkgsSrc; } {
          imports = [
            oneSystemModule
            ../../extensions/nixos
          ];
          substrate.hosts.testhost.system = "x86_64-linux";
        };
      in
      result.nixosConfigurations.testhost.config.networking.hostName == "testhost"
      && result.nixosConfigurations.testhost.config.nixpkgs.flake.source != null;
  };

  barePathInputThrows = {
    check =
      let
        result =
          builtins.tryEval
            (mkRaw { nixpkgs = <nixpkgs>; } {
              imports = [
                oneSystemModule
                ../../extensions/nixos
              ];
              substrate.hosts.testhost.system = "x86_64-linux";
            }).nixosConfigurations.testhost.config.networking.hostName;
      in
      !result.success;
  };

  checksOutputEmitted = {
    check =
      let
        result = mkRaw { nixpkgs = nixpkgsSrc; } oneSystemModule;
      in
      lib.isDerivation result.checks.x86_64-linux.substrate-config;
  };

  inputsReachModules = {
    check =
      let
        result = mkRaw { nixpkgs = nixpkgsSrc; } (
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

  coreInputsDefaultsToInputs = {
    check =
      let
        result = mkRaw { nixpkgs = nixpkgsSrc; } (
          { inputs, ... }:
          {
            imports = [ oneSystemModule ];
            substrate.settings.checks = [
              {
                name = "coreInputs-defaults-to-inputs";
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

  explicitCoreInputsUsedForResolution = {
    check =
      let
        result = mkRawWithCoreInputs { } { nixpkgs = nixpkgsSrc; } (
          { inputs, ... }:
          {
            imports = [
              oneSystemModule
              ../../extensions/nixos
            ];
            substrate.hosts.testhost.system = "x86_64-linux";
            substrate.settings.checks = [
              {
                name = "modules-receive-consumer-inputs";
                valid = !(inputs ? nixpkgs);
                warn = false;
                message = "modules should see consumer inputs, not coreInputs";
              }
            ];
          }
        );
      in
      result.nixosConfigurations.testhost.config.networking.hostName == "testhost"
      && lib.isDerivation result.checks.x86_64-linux.substrate-config;
  };

  failingCheckThrows = {
    check =
      let
        result = mkRaw { nixpkgs = nixpkgsSrc; } {
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
        result = mkRaw { nixpkgs = nixpkgsSrc; } {
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

  devenvShellsBuilt = {
    check =
      let
        fakeDevenv = {
          outPath = pkgs.path;
          lib.mkShell = args: {
            shellMarker = "mkShell";
            inherit (args) modules;
          };
        };

        result =
          mkRawWithCoreInputs { }
            {
              nixpkgs = nixpkgsSrc;
              devenv = fakeDevenv;
            }
            {
              imports = [
                oneSystemModule
                ../../extensions/devenv
              ];

              substrate.devenv.shells.default = {
                packages = [ pkgs.hello ];
                enterShell = "echo hello";
              };
            };
      in
      result.devShells.x86_64-linux.default.shellMarker == "mkShell"
      && builtins.length result.devShells.x86_64-linux.default.modules == 1;
  };
}
