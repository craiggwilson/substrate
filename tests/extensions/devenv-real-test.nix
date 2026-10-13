# The devenv extension against the REAL devenv.
#
# devenv-test.nix substitutes a fake whose mkShell records the module it was
# handed and returns. That proves the extension passes its arguments through, and
# nothing more: it never evaluates a devenv module tree, so a shell entry that the
# module system consumed on the way there still passed. A regression that only a
# real devenv evaluation can see belongs here.
#
# The shell entry is a function, because that is the shape that broke. The check
# forces the derivation path, which evaluates devenv's whole module tree: if the
# entry was consumed by this configuration's module system, `pkgs` is missing and
# evaluation fails rather than the shell being built.
{
  pkgs ? import <nixpkgs> { },
  # The real devenv flake. Supplied by flake.nix; absent means the check is
  # skipped rather than failed, so the file evaluates without it.
  devenvSrc ? null,
  ...
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) runTests;

  substrate = import ../..;

  system = "x86_64-linux";
in
runTests "Devenv Real Extension Tests" {
  # A function entry reaches real devenv and builds a real shell derivation.
  functionEntryBuilds = {
    check =
      devenvSrc != null
      && (
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
                  devenv = devenvSrc;
                };
              }
              {
                imports = [ substrate.substrateModules.devenv ];
                substrate.settings.systems = [ system ];

                substrate.devenv.shells.default =
                  { pkgs, ... }:
                  {
                    # Pure eval cannot read PWD, and devenv asserts its root is
                    # non-empty, so a literal is the only value that evaluates.
                    devenv.root = "/tmp";
                    packages = [ pkgs.hello ];
                    enterShell = "echo hello";
                  };
              };
        in
        # Forcing drvPath is the assertion: it evaluates devenv's module tree.
        pkgs.lib.isString result.devShells.${system}.default.drvPath
      );
  };

  # An attribute-set entry still works through real devenv, so the fix does not
  # only repair functions.
  attributeSetEntryBuilds = {
    check =
      devenvSrc != null
      && (
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
                  devenv = devenvSrc;
                };
              }
              {
                imports = [ substrate.substrateModules.devenv ];
                substrate.settings.systems = [ system ];

                substrate.devenv.shells.default = { pkgs, ... }: {
                  devenv.root = "/tmp";
                  packages = [ pkgs.hello ];
                };
              };
        in
        pkgs.lib.isString result.devShells.${system}.default.drvPath
      );
  };

  # One function entry per shell name, which is what a module-per-shell tree
  # import produces. Two entries under one name is the case that fails (the
  # substrate module system claims the function and calls it with its own
  # arguments); two names with one entry each is the case that has to work, and
  # nothing else here covers it.
  oneFunctionEntryPerName = {
    check =
      devenvSrc != null
      && (
        let
          shell =
            {
              pkgs,
              ...
            }:
            {
              devenv.root = "/tmp";
              packages = [ pkgs.hello ];
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
                  devenv = devenvSrc;
                };
              }
              {
                imports = [ substrate.substrateModules.devenv ];
                substrate.settings.systems = [ system ];

                substrate.devenv.shells.first = shell;
                substrate.devenv.shells.second = shell;
              };
        in
        pkgs.lib.isString result.devShells.${system}.first.drvPath
        && pkgs.lib.isString result.devShells.${system}.second.drvPath
        # Each shell reports its own name, which is what devenv's `devenv`
        # wrapper resolves `nix develop .#<name>` against. Without it every
        # shell claims to be `default`, and the wrapper re-enters whichever one
        # that happens to be.
        && result.devShells.${system}.first.config.env.DEVENV_FLAKE_SHELL == "first"
        && result.devShells.${system}.second.config.env.DEVENV_FLAKE_SHELL == "second"
      );
  };
}
