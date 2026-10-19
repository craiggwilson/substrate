# Tests for the `explain` output: which modules each class's builder would
# build, for each host and each (host, user) scope.
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib mkEvalSubstrate runTests;

  # Extended core so `substrate.hosts` and `substrate.users` exist, plus the
  # tags extension because it is the one finder that actually filters: the `all`
  # finder returns everything for every host, which would make every assertion
  # here vacuous.
  evalSubstrate = mkEvalSubstrate [
    ../../core/settings.nix
    ../../core/lib.nix
    ../../core/modules.nix
    ../../core/finders.nix
    ../../core/hosts.nix
    ../../core/users.nix
    ../../core/outputs.nix
    ../../core/overlays.nix
    ../../core/checks.nix
    ../../core/explain.nix
    ../../core/publish.nix
    ../../extensions/tags/default.nix
    {
      # The class is what makes this test say anything: with none registered,
      # `allClasses` is `generic` alone and every host section is empty.
      config.substrate.settings.supportedClasses = [
        "nixos"
      ];
    }
  ];

  explained =
    eval:
    (builtins.head eval.config.substrate.outputs.global.explain).build {
      substrate = eval.config.substrate;
    };

  tests = {
    # The finder that ran is named, so a surprising answer can be traced to the
    # selection model rather than guessed at.
    itNamesTheFinderItUsed = {
      check =
        let
          eval = evalSubstrate [ ];
        in
        (explained eval).modulesFinder == "by-tags";
    };

    # Per host and per (host, user), keyed the way the class builders name
    # their configurations.
    itKeysScopesTheWayBuildersNameThem = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.users.bob = { };
              config.substrate.hosts.igloo = {
                users = [ "bob" ];
              };
            }
          ];
          scopes = builtins.attrNames (explained eval).classes.nixos.igloo;
        in
        scopes == [
          "igloo"
          "igloo+users"
          "igloo/bob"
        ];
    };

    # A host-scoped module reaches the host's own scope.
    itReportsWhatReachesTheHost = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.options = [
                "base"
                "never"
              ];
              config.substrate.modules.programs.always = {
                tags = [ "base" ];
                nixos = { };
              };
              config.substrate.modules.programs.extra = {
                tags = [ "never" ];
                nixos = { };
              };
              config.substrate.hosts.igloo.tags = [ "base" ];
            }
          ];
          selected = (explained eval).classes.nixos.igloo.igloo;
        in
        selected == [ "programs/always" ];
    };

    # The diff between `available` and what a host got is what the finder
    # filtered out. Without `available` there is no way to see that a module was
    # considered and rejected, only that it is not there.
    itReportsWhatWasFilteredOut = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.options = [
                "base"
                "never"
              ];
              config.substrate.modules.programs.always = {
                tags = [ "base" ];
                nixos = { };
              };
              config.substrate.modules.programs.extra = {
                tags = [ "never" ];
                nixos = { };
              };
              config.substrate.hosts.igloo.tags = [ "base" ];
            }
          ];
          report = explained eval;
        in
        lib.elem "programs/extra" report.available
        && !(lib.elem "programs/extra" report.classes.nixos.igloo.igloo);
    };

    # A user's scope is resolved with the host alongside it, so a host's modules
    # are part of what that user's configuration is built from.
    aUsersScopeIncludesTheHostsModules = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.options = [
                "base"
                "never"
              ];
              config.substrate.users.bob = { };
              config.substrate.hosts.igloo = {
                users = [ "bob" ];
              };
            }
          ];
        in
        (explained eval).classes.nixos.igloo."igloo/bob" == (explained eval).classes.nixos.igloo.igloo;
    };

    # A home-only host declares no operating system, so there is nothing for the
    # host class to build and no entry to report.
    itSkipsHomeOnlyHosts = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.users.bob = { };
              config.substrate.hosts.igloo = { };
              config.substrate.hosts.homeonly = {
                usersOnly = true;
                users = [ "bob" ];
              };
            }
          ];
          scopes = builtins.attrNames (explained eval).classes.nixos.igloo;
        in
        scopes == [
          "igloo"
          "igloo+users"
        ];
    };

    # Every registered class gets a section, including `generic` -- which is
    # merged into the others and so has no builder of its own. Listing it keeps
    # the shape of the report stable as classes come and go.
    itReportsEveryClass = {
      check =
        let
          eval = evalSubstrate [ ];
        in
        builtins.attrNames (explained eval).classes == [
          "generic"
          "nixos"
        ];
    };
  };
in
runTests "Explain Tests" tests
