# Tests for substrate overlays and packages
# Run with: nix eval -f substrate/tests/core/overlays-packages-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib evalSubstrate runTests;

  tests = {
    # Test 1: Default overlays list is empty
    defaultOverlaysEmpty = {
      check =
        let
          eval = evalSubstrate [ ];
        in
        eval.config.substrate.settings.overlays == [ ];
    };

    # Test 2: Custom overlays can be added
    customOverlaysAdded = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.overlays = [
                (final: prev: { testPkg = null; })
              ];
            }
          ];
        in
        lib.length eval.config.substrate.settings.overlays == 1;
    };

    # Test 3: Multiple overlays can be added
    multipleOverlays = {
      check =
        let
          eval = evalSubstrate [
            { config.substrate.settings.overlays = [ (final: prev: { }) ]; }
            { config.substrate.settings.overlays = [ (final: prev: { }) ]; }
          ];
        in
        lib.length eval.config.substrate.settings.overlays == 2;
    };

    # Test 4: Overlays in settings can be applied
    overlaysCanBeApplied = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.overlays = [
                (final: prev: { test = true; })
              ];
            }
          ];
          overlays = eval.config.substrate.settings.overlays;
          overlay = builtins.head overlays;
          # Apply the overlay to test it works
          result = overlay pkgs { };
        in
        lib.length overlays == 1 && result.test == true;
    };

    # Test 5: Default packages list is empty
    defaultPackagesEmpty = {
      check =
        let
          eval = evalSubstrate [ ];
        in
        eval.config.substrate.settings.publish.packages == [ ];
    };

    # Test 6: Package namespace can be set
    packageNamespaceSet = {
      check =
        let
          eval = evalSubstrate [
            { config.substrate.settings.packageNamespace = "myns"; }
          ];
        in
        eval.config.substrate.settings.packageNamespace == "myns";
    };

    # Test 7: Multiple overlays can be combined
    multipleOverlaysCombine = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.overlays = [
                (final: prev: { a = 1; })
                (final: prev: { b = 2; })
              ];
            }
          ];
        in
        lib.length eval.config.substrate.settings.overlays == 2;
    };

  };
in
runTests "Overlays & Packages Tests" tests
