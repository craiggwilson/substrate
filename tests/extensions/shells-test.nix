# Tests for substrate shells extension
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) runTests;

  oneSystemModule = {
    substrate.settings.systems = [ "x86_64-linux" ];
  };
in
runTests "Shells Extension Tests" {
  shellsLiveUnderSubstrateShells = {
    check =
      let
        result =
          (import ../..).build.raw
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
              };
            }
            {
              imports = [
                oneSystemModule
                ../../extensions/shells
              ];

              substrate.shells.publish = [ ./fixtures/hello-shell.nix ];
            };
      in
      builtins.hasAttr "hello-shell" result.devShells.x86_64-linux;
  };
}
