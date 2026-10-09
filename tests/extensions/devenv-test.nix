# Tests for substrate devenv extension
{
  pkgs ? import <nixpkgs> { },
  ...
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib runTests evalSubstrate;

  substrate = import ../..;

  fakeDevenv = {
    outPath = pkgs.path;
    lib.mkShell = args: {
      shellMarker = "mkShell";
      inherit (args) modules;
    };
  };

  oneSystemModule = {
    substrate.settings.systems = [ "x86_64-linux" ];
  };
in
runTests "Devenv Extension Tests" {
  shellOptionsMerge = {
    check =
      let
        eval = evalSubstrate [
          {
            imports = [ ../../extensions/devenv ];
            substrate.devenv.shells.default.packages = [ pkgs.hello ];
          }
          {
            imports = [ ../../extensions/devenv ];
            substrate.devenv.shells.default.enterShell = "echo hello";
          }
        ];
      in
      eval.config.substrate.devenv.shells.default.packages == [ pkgs.hello ]
      && eval.config.substrate.devenv.shells.default.enterShell == "echo hello";
  };

  shellsBuildIntoDevShells = {
    check =
      let
        result =
          substrate.build.raw
            {
              inputs = {
                nixpkgs = {
                  outPath = pkgs.path;
                  inherit (pkgs) lib;
                };
              };
              coreInputs = {
                nixpkgs = {
                  outPath = pkgs.path;
                  inherit (pkgs) lib;
                };
                devenv = fakeDevenv;
              };
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
        built = result.devShells.x86_64-linux.default;
      in
      built.shellMarker == "mkShell"
      &&
        built.modules == [
          {
            packages = [ pkgs.hello ];
            enterShell = "echo hello";
          }
        ];
  };

  builtShellUsesMkShell = {
    check =
      let
        result =
          substrate.build.raw
            {
              inputs = {
                nixpkgs = {
                  outPath = pkgs.path;
                  inherit (pkgs) lib;
                };
              };
              coreInputs = {
                nixpkgs = {
                  outPath = pkgs.path;
                  inherit (pkgs) lib;
                };
                devenv = fakeDevenv;
              };
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

  packagePkgsReachShells = {
    check =
      let
        overlayDevenv = {
          outPath = pkgs.path;
          lib.mkShell = args: {
            gotPackage = (args.pkgs ? custom) && builtins.hasAttr "hello-package" args.pkgs.custom;
            shellMarker = "mkShell";
          };
        };

        result =
          substrate.build.raw
            {
              inputs = {
                nixpkgs = {
                  outPath = pkgs.path;
                  inherit (pkgs) lib;
                };
              };
              coreInputs = {
                nixpkgs = {
                  outPath = pkgs.path;
                  inherit (pkgs) lib;
                };
                devenv = overlayDevenv;
              };
            }
            {
              imports = [
                oneSystemModule
                ../../extensions/overlays
                ../../extensions/packages
                ../../extensions/devenv
              ];

              substrate.packages.publish.hello-package =
                { pkgs, ... }:
                pkgs.callPackage ./fixtures/hello-package.nix { };

              substrate.devenv.shells.default = {
                packages = [ pkgs.hello ];
                enterShell = "echo hello";
              };
            };
      in
      result.devShells.x86_64-linux.default.gotPackage;
  };
}
