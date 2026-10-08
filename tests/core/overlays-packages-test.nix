# Tests for substrate overlays and packages
# Run with: nix eval -f substrate/tests/core/overlays-packages-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib runTests;

  # These tests exercise the overlays and packages extensions, which are not
  # part of the shared core module set.
  evalSubstrate = testLib.mkEvalSubstrate (
    testLib.coreModules
    ++ [
      ../../extensions/overlays
      ../../extensions/packages
    ]
  );

  tests = {
    # Test 1: Default overlays list is empty
    defaultOverlaysEmpty = {
      check =
        let
          eval = evalSubstrate [ ];
        in
        eval.config.substrate.settings.overlays == [ ]
        && eval.config.substrate.overlays.internal == [ ]
        && eval.config.substrate.overlays.publish == { };
    };

    # Test 2: Custom overlays can be added
    customOverlaysAdded = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.overlays.internal = [
                (_final: _prev: { testPkg = null; })
              ];
            }
          ];
        in
        lib.length eval.config.substrate.settings.overlays == 1
        && lib.length eval.config.substrate.overlays.internal == 1;
    };

    # Test 3: Multiple overlays can be added
    multipleOverlays = {
      check =
        let
          eval = evalSubstrate [
            { config.substrate.overlays.internal = [ (_final: _prev: { }) ]; }
            { config.substrate.overlays.publish.default = _final: _prev: { }; }
          ];
        in
        lib.length eval.config.substrate.settings.overlays == 2
        && lib.length eval.config.substrate.overlays.internal == 1
        && eval.config.substrate.overlays.publish ? default;
    };

    # Test 4: Overlays in settings can be applied
    overlaysCanBeApplied = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.overlays.internal = [
                (_final: _prev: { test = true; })
              ];
            }
          ];
          inherit (eval.config.substrate.settings) overlays;
          overlay = builtins.head overlays;
          # Apply the overlay to test it works
          result = overlay pkgs { };
        in
        lib.length overlays == 1 && result.test;
    };

    # Test 5: Default packages list is empty
    defaultPackagesEmpty = {
      check =
        let
          eval = evalSubstrate [ ];
        in
        eval.config.substrate.packages.internal == [ ] && eval.config.substrate.packages.publish == [ ];
    };

    # Test 6: Package namespace can be set
    packageNamespaceSet = {
      check =
        let
          eval = evalSubstrate [
            { config.substrate.settings.packages.namespace = "myns"; }
          ];
        in
        eval.config.substrate.settings.packages.namespace == "myns";
    };

    # Test 8: Internal overlays and published overlays are separated
    internalAndPublishedPackages = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.overlays.internal = [
                (_final: _prev: { internalMarker = true; })
              ];
              config.substrate.overlays.publish.default = _final: _prev: {
                publishedMarker = true;
              };
            }
          ];
          overlayOutput = (builtins.head eval.config.substrate.outputs.global.overlays).build {
            inputs = { };
            substrate = eval.config.substrate;
          };
        in
        lib.length eval.config.substrate.settings.overlays == 2
        && overlayOutput.default pkgs pkgs ? publishedMarker;
    };

    # Test 7: Multiple overlays can be combined
    multipleOverlaysCombine = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.overlays.internal = [
                (_final: _prev: { a = 1; })
              ];
            }
            {
              config.substrate.overlays.publish.b = _final: _prev: { b = 2; };
            }
          ];
        in
        lib.length eval.config.substrate.settings.overlays == 2;
    };

  };
in
runTests "Overlays & Packages Tests" tests
