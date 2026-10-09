# Tests for substrate overlays and packages
# Run with: nix eval -f substrate/tests/core/overlays-packages-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib runTests;

  # These tests exercise the overlays and packages extensions, which are not
  # part of the shared core module set. The packages extension reads `inputs`,
  # which both builders supply, so the harness passes a stub.
  evalSubstrate =
    extraModules:
    lib.evalModules {
      modules =
        testLib.coreModules
        ++ [
          ../../extensions/overlays
          ../../extensions/packages
        ]
        ++ extraModules;
      specialArgs.inputs = { };
    };

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

    # Test 5: Default packages attrset is empty
    defaultPackagesEmpty = {
      check =
        let
          eval = evalSubstrate [ ];
        in
        eval.config.substrate.packages.internal == { } && eval.config.substrate.packages.publish == { };
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

    # Test 7: A package entry is called with its context and lands in the
    # overlay under the configured namespace, named by its attribute key.
    packageEntryLandsInOverlay = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.packages.namespace = "demo";
              config.substrate.packages.publish.hello =
                { pkgs, ... }:
                pkgs.callPackage ./fixtures/hello-package.nix { };
            }
          ];
          built = (builtins.head eval.config.substrate.settings.overlays) pkgs pkgs;
        in
        built.demo ? hello && built.demo.hello.pname == "hello-package";
    };

    # Test 7b: A path entry is callPackage'd, so a bare package file works
    # without being wrapped in a function.
    packagePathEntryLandsInOverlay = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.packages.namespace = "demo";
              config.substrate.packages.publish.hello = ./fixtures/hello-package.nix;
            }
          ];
          built = (builtins.head eval.config.substrate.settings.overlays) pkgs pkgs;
        in
        built.demo ? hello && built.demo.hello.pname == "hello-package";
    };

    # Test 7c: A directory walk turns bare package files into entries, so dropping
    # one in is all it takes. Both file conventions work: written against a
    # callPackage argument, and written against `pkgs`.
    packageDirectoryBecomesEntries = {
      check =
        let
          eval = evalSubstrate [
            (_: {
              config.substrate.settings.packages.namespace = "demo";
              config.substrate.packages.publish = testLib.definitionsIn ../extensions/fixtures/tree/pkgs;
            })
          ];
          built = (builtins.head eval.config.substrate.settings.overlays) pkgs pkgs;
        in
        built.demo ? path-entry
        && built.demo.path-entry.pname == "path-entry"
        && built.demo ? pkgs-style
        && built.demo.pkgs-style.name == "pkgs-style";
    };

    # Test 7d: A directory of modules registers its packages on import, with no
    # suffix handling or path building anywhere. This is the route an
    # `import-tree` input takes.
    packageModulesRegisterOnImport = {
      check =
        let
          eval = evalSubstrate [
            ({ ... }: {
              imports = testLib.modulesIn ../extensions/fixtures/modules-packages;
            })
          ];
          built = (builtins.head eval.config.substrate.settings.overlays) pkgs pkgs;
        in
        built.custom ? module-entry && built.custom ? other-module-entry;
    };

    # Test 8: An internal package reaches substrate's own package sets but not
    # the published overlay.
    internalPackageIsNotPublished = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.packages.internal.only =
                { pkgs, ... }:
                pkgs.callPackage ./fixtures/hello-package.nix { };
              config.substrate.packages.publish.shown =
                { pkgs, ... }:
                pkgs.callPackage ./fixtures/hello-package.nix { };
            }
          ];
          overlay = builtins.head eval.config.substrate.settings.overlays;
          built = overlay pkgs pkgs;
          published = (builtins.head eval.config.substrate.outputs.global.overlays).build {
            inputs = { };
            substrate = eval.config.substrate;
          };
          publishedBuilt = published.packages pkgs pkgs;
        in
        built.custom ? only
        && built.custom ? shown
        && publishedBuilt.custom ? shown
        && !publishedBuilt.custom ? only;
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
