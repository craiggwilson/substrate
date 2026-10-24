# Tests for substrate configuration validation checks
# These tests verify the validation module can detect configuration issues
# Note: Some validations (like invalid module tags) are already caught by
# the type system at evaluation time, so we test the validation logic
# in isolation where possible.
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib mkEvalSubstrate runTests;

  # Checks tests need extended core plus tags and nixos extensions
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
    ../../extensions/nixos/default.nix
    ../../extensions/tags/default.nix
  ];

  checkNamed =
    name: eval:
    builtins.head (builtins.filter (c: c.name == name) eval.config.substrate.settings.checks);

  # Reachability is a property of the tree alone, so these tests use core plus a
  # declared class rather than the nixos/tags extensions. That keeps them from
  # pulling the tags checks in with them: forcing every check in a config this
  # size exceeds the evaluator's call depth, which says nothing about the code
  # under test.
  evalCore = mkEvalSubstrate [
    ../../core/settings.nix
    ../../core/lib.nix
    ../../core/modules.nix
    ../../core/finders.nix
    ../../core/hosts.nix
    ../../core/users.nix
    ../../core/outputs.nix
    ../../core/overlays.nix
    ../../core/checks.nix
    {
      config.substrate.settings.supportedClasses = [
        "nixos"
      ];
    }
  ];

  tests = {
    # Test 1: Valid config with modules using valid tags
    validModuleTags = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "core"
                "gui"
              ];
              config.substrate.modules.programs.test = {
                nixos = { };
                tags = [ "core" ];
              };
            }
          ];
        in
        eval.config.substrate.modules.programs.test.tags == [ "core" ];
    };

    # Test 2: Valid user tags are accepted
    validUserTags = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "desktop"
                "laptop"
              ];
              config.substrate.users.alice = {
                tags = [ "desktop" ];
              };
            }
          ];
        in
        eval.config.substrate.users.alice.tags == [ "desktop" ];
    };

    # Test 3: Host can reference valid users
    hostWithValidUsers = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.users.alice = { };
              config.substrate.hosts.myhost = {
                users = [ "alice" ];
              };
            }
          ];
        in
        eval.config.substrate.hosts.myhost.users == [ "alice" ];
    };

    # Test 4: Host referencing invalid user fails at type check
    hostWithInvalidUserFails = {
      check =
        let
          result = builtins.tryEval (
            let
              eval = evalSubstrate [
                {
                  config.substrate.hosts.myhost = {
                    users = [ "nonexistent" ];
                  };
                }
              ];
            in
            builtins.deepSeq eval.config.substrate.hosts.myhost.users true
          );
        in
        # Should fail because "nonexistent" is not a valid user
        !result.success;
    };

    # Test 5: Multiple modules with valid tags all work
    multipleModulesValidTags = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "core"
                "gui"
                "cli"
              ];
              config.substrate.modules.programs.mod1 = {
                nixos = { };
                tags = [ "core" ];
              };
              config.substrate.modules.programs.mod2 = {
                nixos = { };
                tags = [ "gui" ];
              };
              config.substrate.modules.programs.mod3 = {
                nixos = { };
                tags = [ "cli" ];
              };
            }
          ];
          allMods = eval.config.substrate.moduleFinders.all.find [ ];
        in
        lib.length allMods == 3;
    };

    # Test 6: Modules with no tags have empty tags list
    modulesWithNoTags = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [ "core" ];
              config.substrate.modules.programs.test = {
                nixos = { };
              };
            }
          ];
        in
        eval.config.substrate.modules.programs.test.tags == [ ];
    };

    # Test 7: Supported classes are correct
    supportedClassesCorrect = {
      check =
        let
          eval = evalSubstrate [ ];
          classes = eval.config.substrate.settings.supportedClasses;
        in
        lib.elem "nixos" classes;
    };

    # -- module reachability ------------------------------------------------

    # A module written for a class nobody registered reads as a plain nested
    # node, and no finder can ever select it. It has to be reported, because
    # nothing else would say so.
    # The check runs, and warns rather than failing: a module reaching nothing
    # may well be a grouping node whose class is coming, so it must not stop a
    # build. `valid` is deliberately not forced here -- reading the check list
    # at all is already close to the evaluator's frame budget in a file this
    # size -- so what this covers is the registration, and the walk itself is
    # covered by the tests below.
    reachabilityCheckIsRegisteredAsAWarning = {
      check =
        let
          eval = evalCore [ ];
          result = checkNamed "module-reachability" eval;
        in
        result.warn == true;
    };

    # The reporting path is the deepest node of the dead region, so it names
    # the key the value was written at rather than the grouping node above it.
    unreachablePathNamesTheKeyThatWasWritten = {
      check =
        let
          eval = evalCore [
            {
              config.substrate.modules.programs.zfs = {
                darwin = { };
                homeManager = { };
              };
            }
          ];
        in
        eval.config.substrate.lib.unreachableModulePaths eval.config.substrate.modules == [
          "programs/zfs/darwin"
          "programs/zfs/homeManager"
        ];
    };

    # A grouping node above a live module is reachable: something below it can
    # be selected, so it must not be reported.
    groupingNodesAreNotReported = {
      check =
        let
          eval = evalCore [
            {
              config.substrate.modules.programs.editors.vim.nixos = { };
              config.substrate.modules.services.blueman.nixos = { };
            }
          ];
        in
        eval.config.substrate.lib.unreachableModulePaths eval.config.substrate.modules == [ ];
    };

    # A live module with a dead child under it still reports the child: the
    # parent is reachable, the child is not.
    deadChildOfLiveModuleIsReported = {
      check =
        let
          eval = evalCore [
            {
              config.substrate.modules.programs.zfs = {
                nixos = { };
                settings = { };
              };
            }
          ];
        in
        eval.config.substrate.lib.unreachableModulePaths eval.config.substrate.modules
        == [ "programs/zfs/settings" ];
    };

    # An empty tree has nothing unreachable -- the root has no path of its own
    # to report.
    emptyTreeHasNothingUnreachable = {
      check =
        let
          eval = evalCore [ ];
        in
        eval.config.substrate.lib.unreachableModulePaths eval.config.substrate.modules == [ ];
    };

    # The generic class counts as content, so a module written only in generic
    # terms is reachable.
    genericOnlyModuleIsReachable = {
      check =
        let
          eval = evalCore [
            {
              config.substrate.modules.programs.shared.generic = { };
            }
          ];
        in
        eval.config.substrate.lib.unreachableModulePaths eval.config.substrate.modules == [ ];
    };

    # A module with a class but no value for it is still content -- `nixos = {}`
    # is the normal way to write a module, and it must not be reported.
    emptyClassModuleIsReachable = {
      check =
        let
          eval = evalCore [
            {
              config.substrate.modules.programs.empty.nixos = { };
            }
          ];
        in
        eval.config.substrate.lib.unreachableModulePaths eval.config.substrate.modules == [ ];
    };
  };
in
runTests "Configuration Validation Tests" tests
