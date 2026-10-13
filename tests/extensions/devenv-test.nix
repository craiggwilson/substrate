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

  # Build through a builder with a stub nixpkgs and the fake devenv, and hand
  # back the module the extension put in `modules = [ ... ]`.
  shellModuleSeenByDevenv =
    entry:
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
            substrate.devenv.shells.default = entry;
          };
    in
    builtins.head result.devShells.x86_64-linux.default.modules;
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

  # A function entry must reach devenv still callable, and must be called with
  # devenv's arguments rather than the ones this configuration happens to have.
  #
  # A `submodule` type imports a function value as a module of this configuration
  # and calls it with this configuration's arguments, which have no `pkgs` — so
  # the entry was consumed before devenv saw it, and this check failed with
  # "attribute 'pkgs' missing".
  #
  # `functionTo raw` merges to a lazy `{ __functor; __functionArgs }` set rather
  # than a lambda, so the call shape is `entry args` either way. Calling it the
  # way devenv's collectModules does, with a `pkgs` present, is what makes the
  # difference observable.
  functionEntryReachesDevenvCallable = {
    check =
      let
        entry = shellModuleSeenByDevenv (
          { pkgs, ... }:
          {
            devenv.root = "/tmp";
            packages = [ pkgs.hello ];
          }
        );
        called = entry { inherit pkgs; };
      in
      called.devenv.root == "/tmp" && called.packages == [ pkgs.hello ];
  };

  # The same entry, with the body forced. `tryEval` alone only forces WHNF, so an
  # unforced `pkgs.hello` would let a consumed entry pass; comparing derivations
  # forces the list and the derivation behind it.
  functionEntryBodyForcesWithPkgs = {
    check =
      let
        entry = shellModuleSeenByDevenv (
          { pkgs, ... }:
          {
            devenv.root = "/tmp";
            packages = [ pkgs.hello ];
          }
        );
        called = entry { inherit pkgs; };
      in
      called.packages == [ pkgs.hello ] && called.devenv.root == "/tmp";
  };

  # An attribute-set entry must keep working, and must still merge across files.
  attributeSetEntryStillMerges = {
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

  # The entry is passed through as the first module, and the two modules
  # substrate adds after it are the ones devenv's own `devenv` wrapper needs:
  # the shell's name, and the flag that stops it re-entering the flake. Both are
  # per-shell, so they cannot be written once for the whole set.
  shellIsBuiltWithTheNameAndNoReentry = {
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

              substrate.devenv.shells.rust = {
                packages = [ pkgs.hello ];
              };
            };
        modules = result.devShells.x86_64-linux.rust.modules;
        # The fake records the modules without evaluating them, so the two
        # substrate adds are still lambdas here. Applying one to an empty
        # argument set is what collecting them would do.
        apply = args: module: module args;
      in
      builtins.length modules == 3
      && (apply { } (builtins.elemAt modules 1))._module.args.name == "rust"
      && (apply { } (builtins.elemAt modules 2)).env.DEVENV_IN_DIRENV_SHELL == pkgs.lib.mkDefault "true";
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
        builtins.head built.modules == {
          packages = [ pkgs.hello ];
          enterShell = "echo hello";
        };
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
      # The entry, plus the modules substrate adds for devenv's `devenv`
      # wrapper. The count, not the list: those two are devenv's business.
      && builtins.length result.devShells.x86_64-linux.default.modules == 3;
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
