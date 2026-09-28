# Shared test utilities for substrate tests
# Import with: testLib = import ../lib.nix { inherit pkgs; };
{
  pkgs ? import <nixpkgs> { },
}:
let
  lib = pkgs.lib;

  # Helper to run a test and return result
  runTest =
    name: test:
    let
      result = builtins.tryEval (builtins.deepSeq test.check test.check);
    in
    if result.success then
      if result.value == true then
        {
          inherit name;
          success = true;
          message = "PASS";
        }
      else
        {
          inherit name;
          success = false;
          message = "FAIL: check returned false";
        }
    else
      # The error travels in `value` on failure, and it is the only thing that
      # says *why* a check could not be evaluated.
      {
        inherit name;
        success = false;
        message = "FAIL: evaluation error";
      };

  # Minimal core modules (no extensions)
  minimalCoreModules = [
    ../core/settings.nix
    ../core/lib.nix
    ../core/modules.nix
    ../core/finders.nix
  ];

  # Core modules required by most tests
  coreModules = minimalCoreModules ++ [
    ../core/outputs.nix
    ../extensions/overlays/default.nix
    ../extensions/packages/default.nix
  ];

  # Extended core modules (includes hosts, users, checks)
  extendedCoreModules = coreModules ++ [
    ../core/hosts.nix
    ../core/users.nix
    ../core/checks.nix
  ];

  # A target configuration carrying a class's contributions, as a builder builds
  # it: the substrate eval's class contributions, plus whatever the class itself
  # needs to declare.
  #
  # Going through contributionsFor rather than importing a class module directly
  # is the point -- it is the path a builder takes, so a test cannot pass on a
  # publication no builder would make.
  #
  # `context` is what the contribution context carries: pkgs for a wrapper, plus
  # usercfg for a user configuration. `configModules` declares what a hook reads
  # (secretspec, say) so it finds a value rather than an absent attribute.
  classEval =
    {
      eval,
      class ? "nixos",
      context ? { },
      # Modules of the target configuration itself: the class's own stubs, or one
      # that calls `wrap`.
      modules ? [ ],
      configModules ? [ ],
      specialArgs ? { },
    }:
    let
      contextArgs = {
        inputs = { };
        hostname = "h";
        host = "h";
        userName = "u";
        userConfigs = [ ];
        hostcfg = {
          name = "h";
        };
        usercfg = null;
        substrate = eval.config.substrate;
      };
    in
    lib.evalModules {
      modules =
        eval.config.substrate.lib.contributionsFor class (contextArgs // context)
        ++ configModules
        ++ modules;
      # What a builder hands the class: pkgs (bound to the same instance the
      # substrate eval used), the flake inputs, and the host it is building for.
      specialArgs = {
        pkgs = context.pkgs or null;
        inherit (contextArgs) inputs hostcfg;
      }
      // specialArgs
      // {
        inherit eval;
      };
    };

  # One `wrap` call, made the way a module of the target configuration makes it.
  # A publication like this is not readable as `config._module.args` -- `_module`
  # is internal -- so the argument is taken by a module that declares an option
  # and assigns it to `wrap spec`, which is how a real module sees it.
  classWrap =
    {
      eval,
      spec,
      class ? "nixos",
      context ? { },
      configModules ? [ ],
      specialArgs ? { },
    }:
    (classEval {
      inherit
        eval
        class
        context
        configModules
        specialArgs
        ;
      modules = [
        ({ wrap, ... }: {
          options.wrapped = lib.mkOption {
            type = lib.types.raw;
          };
          config.wrapped = wrap.package spec;
        })
      ];
    }).config.wrapped;

  # Create an evalSubstrate function with specific base modules
  mkEvalSubstrate =
    baseModules: extraModules:
    lib.evalModules {
      modules = baseModules ++ extraModules;
    };

  # Standard evalSubstrate with core modules only
  evalSubstrate = mkEvalSubstrate coreModules;

  # Extended evalSubstrate with hosts/users/checks
  evalSubstrateExtended = mkEvalSubstrate extendedCoreModules;

  # Generate summary from test results
  mkSummary =
    title: results:
    let
      passed = lib.filter (r: r.success) (lib.attrValues results);
      failed = lib.filter (r: !r.success) (lib.attrValues results);
      separator = lib.concatStrings (lib.replicate (lib.stringLength title) "=");
    in
    ''
      ${title}
      ${separator}
      Tests: ${toString (lib.length (lib.attrValues results))}
      Passed: ${toString (lib.length passed)}
      Failed: ${toString (lib.length failed)}
      ${lib.concatMapStringsSep "\n" (r: "  ${r.name}: ${r.message}") (lib.attrValues results)}
    '';

  # Run all tests and return standard result structure
  runTests =
    title: tests:
    let
      results = lib.mapAttrs runTest tests;
      allPassed = lib.all (r: r.success) (lib.attrValues results);
    in
    {
      inherit results allPassed;
      summary = mkSummary title results;
    };
in
{
  inherit
    classEval
    classWrap
    lib
    runTest
    minimalCoreModules
    coreModules
    extendedCoreModules
    mkEvalSubstrate
    evalSubstrate
    evalSubstrateExtended
    mkSummary
    runTests
    ;
}
