# Shared test utilities for substrate tests
# Import with: testLib = import ../lib.nix { inherit pkgs; };
{
  pkgs ? import <nixpkgs> { },
}:
let
  inherit (pkgs) lib;

  # Helper to run a test and return result
  runTest =
    name: test:
    let
      result = builtins.tryEval (builtins.deepSeq test.check test.check);
    in
    if result.success then
      if result.value then
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
    ../core/overlays.nix
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
        coreInputs = { };
        hostname = "h";
        host = "h";
        userName = "u";
        userConfigs = [ ];
        hostcfg = {
          name = "h";
        };
        usercfg = null;
        inherit (eval.config) substrate;
      };
    in
    lib.evalModules {
      modules =
        eval.config.substrate.lib.contributionsFor class (contextArgs // context)
        ++ configModules
        ++ modules;
      # What a builder hands the class: pkgs (bound to the same instance the
      # substrate eval used), the flake inputs, the internal dependency inputs,
      # and the host it is building for.
      specialArgs = {
        pkgs = context.pkgs or null;
        inherit (contextArgs) inputs coreInputs hostcfg;
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

  # Stand-in for the directory walk a consumer writes for themselves: every
  # package or shell in a directory, as a name-to-path attribute set. A `.nix`
  # file contributes its basename and a subdirectory its own name, so a file and
  # a directory both land under the name you would expect. Subdirectories are
  # definitions rather than grouping folders — importing one resolves its
  # `default.nix` — so this does not recurse into them.
  #
  # `readDir` reports an entry's kind as a bare string on Nix 2.35 and later and
  # as `{ type = ...; }` before that; only the type needs accommodating, since the
  # name is always the attribute key.
  definitionsIn =
    dir:
    let
      entryType = entry: if lib.isString entry then entry else entry.type;
      entries = builtins.readDir dir;
      definition =
        name:
        let
          kind = entryType entries.${name};
          path = dir + "/${name}";
        in
        if kind == "directory" then
          {
            inherit name;
            value = path;
          }
        else if kind == "regular" && lib.hasSuffix ".nix" name then
          {
            name = lib.removeSuffix ".nix" name;
            value = path;
          }
        else
          null;
    in
    lib.listToAttrs (lib.filter (x: x != null) (lib.map definition (builtins.attrNames entries)));

  # Stands in for an `import-tree` input: every `.nix` file in a directory, as a
  # list of modules ready to drop into `imports`. Real `import-tree` recurses and
  # returns modules rather than paths; for a flat directory of package or shell
  # modules the result is the same.
  modulesIn =
    dir:
    lib.filter (n: lib.hasSuffix ".nix" n) (lib.attrNames (builtins.readDir dir))
    |> map (f: dir + "/${f}");

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
    definitionsIn
    modulesIn
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
