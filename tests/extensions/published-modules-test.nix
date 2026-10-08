# Tests for substrate published-modules extension
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) runTests evalSubstrate;
in
runTests "Published Modules Tests" {
  publishedModulesLiveUnderModules = {
    check =
      let
        eval = evalSubstrate [
          {
            imports = [ ../../extensions/published-modules ];
            config.substrate.modules.publish.nixosModules.test = { };
            config.substrate.modules.publish.homeManagerModules.test = { };
            config.substrate.modules.publish.substrateModules.test = { };
          }
        ];
      in
      eval.config.substrate.modules.publish.nixosModules.test != null
      && eval.config.substrate.modules.publish.homeManagerModules.test != null
      && eval.config.substrate.modules.publish.substrateModules.test != null;
  };
}
