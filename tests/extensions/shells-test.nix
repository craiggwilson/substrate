# Tests for substrate shells extension
{
  pkgs ? import <nixpkgs> { },
  ...
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) runTests;

  substrate = import ../..;

  oneSystemModule = {
    substrate.settings.systems = [ "x86_64-linux" ];
  };

  nixpkgsStub = {
    outPath = pkgs.path;
    inherit (pkgs) lib;
  };

  mkRaw =
    extraModules:
    substrate.build.raw
      {
        inputs.nixpkgs = nixpkgsStub;
        coreInputs.nixpkgs = nixpkgsStub;
      }
      {
        imports = [
          oneSystemModule
          ../../extensions/shells
        ]
        ++ extraModules;
      };
in
runTests "Shells Extension Tests" {
  # A function entry is called with the entry context.
  functionEntry = {
    check =
      let
        result = mkRaw [
          {
            substrate.shells.publish.hello =
              { pkgs, ... }:
              pkgs.mkShell {
                packages = [ pkgs.hello ];
              };
          }
        ];
      in
      builtins.hasAttr "hello" result.devShells.x86_64-linux;
  };

  # A path entry is imported with the entry context, so a shell file reads the
  # same as a function entry. A directory works too — importing one resolves its
  # default.nix.
  pathEntry = {
    check =
      let
        result = mkRaw [
          {
            substrate.shells.publish.dev = ./fixtures/tree/shells/dev;
          }
        ];
      in
      builtins.hasAttr "dev" result.devShells.x86_64-linux;
  };

  # The context a function entry receives carries the build, not just pkgs.
  entryContext = {
    check =
      let
        result = mkRaw [
          {
            substrate.shells.publish.ctx =
              {
                pkgs,
                system,
                lib,
                inputs,
                substrate,
                ...
              }:
              if
                system == "x86_64-linux"
                && lib ? mkOption
                && inputs ? nixpkgs
                && substrate ? settings
                && pkgs ? hello
              then
                "ok"
              else
                "bad";
          }
        ];
      in
      result.devShells.x86_64-linux.ctx == "ok";
  };

  # definitionsIn reads a directory of definitions, naming a file by its
  # basename and a subdirectory by its own name.
  definitionsInNamesEntries = {
    check =
      let
        pkgsDir = testLib.definitionsIn ./fixtures/tree/pkgs;
        shellsDir = testLib.definitionsIn ./fixtures/tree/shells;
      in
      builtins.attrNames pkgsDir == [
        "path-entry"
        "pkgs-style"
      ]
      && pkgsDir."path-entry" == ./fixtures/tree/pkgs/path-entry.nix
      && builtins.attrNames shellsDir == [ "dev" ]
      && shellsDir.dev == ./fixtures/tree/shells/dev;
  };

  # A whole directory assigned in one go reaches devShells, which is the
  # drop-a-file-in case.
  directoryBecomesShells = {
    check =
      let
        result = mkRaw [
          (_: {
            substrate.shells.publish = testLib.definitionsIn ./fixtures/tree/shells;
          })
        ];
      in
      builtins.hasAttr "dev" result.devShells.x86_64-linux;
  };
}
