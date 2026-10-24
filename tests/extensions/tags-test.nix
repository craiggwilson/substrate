# Tests for substrate tags extension
# Run with: nix eval -f substrate/tests/extensions/tags-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib mkEvalSubstrate runTests;

  # Tags extension tests need extended core plus tags and nixos extensions
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

  tests = {
    # Test 1: Simple string tags are normalized to attrsets
    simpleStringTagsNormalized = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "core"
                "other"
              ];
            }
          ];
          # After apply, each entry should be an attrset
          inherit (eval.config.substrate.settings.tags) definitions;
        in
        builtins.isList definitions
        && builtins.length definitions == 2
        && builtins.isAttrs (builtins.elemAt definitions 0);
    };

    # Test 2: Metatags with implications work
    metatagsWithImplications = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "laptop"
                { "hardware:dell" = [ "laptop" ]; }
              ];
            }
          ];
          inherit (eval.config.substrate.settings.tags) definitions;
        in
        builtins.length definitions == 2;
    };

    # Test 3: Parent prefixes are automatically implied
    parentPrefixesImplied = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "theming"
                "theming:catppuccin"
              ];
              config.substrate.users.testuser = {
                tags = [ "theming:catppuccin" ];
              };
            }
          ];
          # Find modules - the hasTag function should work for parent prefix
          found = eval.config.substrate.moduleFinders.by-tags.find [ eval.config.substrate.users.testuser ];
        in
        # Just verify evaluation succeeds
        builtins.isList found;
    };

    # Test 4: Invalid implied tags are rejected
    # The validation happens when modules with the implied tag are accessed
    invalidImpliedTagsRejected = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "laptop"
                { "hardware:dell" = [ "typo-tag" ]; } # "typo-tag" is not declared
              ];
              # Use the metatag which has an invalid implied tag
              config.substrate.users.testuser = {
                tags = [ "hardware:dell" ]; # This should trigger validation of implied "typo-tag"
              };
            }
          ];
          # Try to use the finder which should trigger validation
          result = builtins.tryEval (
            builtins.deepSeq (eval.config.substrate.moduleFinders.by-tags.find [
              eval.config.substrate.users.testuser
            ]) true
          );
        in
        # Should fail because "typo-tag" is not a valid tag
        !result.success;
    };

    # Test 5: Tags can be merged from multiple definitions
    tagsMergeFromMultipleDefinitions = {
      check =
        let
          eval = evalSubstrate [
            { config.substrate.settings.tags.definitions = [ "core" ]; }
            { config.substrate.settings.tags.definitions = [ "other" ]; }
          ];
          inherit (eval.config.substrate.settings.tags) definitions;
        in
        builtins.length definitions == 2;
    };

    # Test 6: Same tag with implications merges correctly
    sameTagImplicationsMerge = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "portable"
                "lightweight"
                "laptop"
                { "laptop" = [ "portable" ]; }
              ];
            }
            {
              config.substrate.settings.tags.definitions = [
                { "laptop" = [ "lightweight" ]; }
              ];
            }
          ];
          # This should work - laptop should imply both portable and lightweight
          inherit (eval.config.substrate.settings.tags) definitions;
        in
        builtins.length definitions == 5; # 3 strings + 2 metatags
    };

    # Test 7: Modules are filtered by tags correctly
    modulesFilteredByTags = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "core"
                "extra"
              ];
              config.substrate.modules.programs.included = {
                nixos = { };
                tags = [ "core" ];
              };
              config.substrate.modules.programs.excluded = {
                nixos = { };
                tags = [ "extra" ];
              };
              config.substrate.users.testuser = {
                tags = [ "core" ];
              };
            }
          ];
          found = eval.config.substrate.moduleFinders.by-tags.find [ eval.config.substrate.users.testuser ];
        in
        # Only the "included" module should be found
        lib.length found == 1;
    };

    # Test 8: Modules with no tags are always included
    modulesWithNoTagsAlwaysIncluded = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [ "core" ];
              config.substrate.modules.programs.always = {
                nixos = { };
                # No tags - should always be included
              };
              config.substrate.modules.programs.conditional = {
                nixos = { };
                tags = [ "core" ];
              };
              config.substrate.users.testuser = {
                tags = [ "core" ];
              };
            }
          ];
          found = eval.config.substrate.moduleFinders.by-tags.find [ eval.config.substrate.users.testuser ];
        in
        # Both modules should be found
        lib.length found == 2;
    };

    # Test 9: Nested tag prefixes work (a:b:c implies a:b and a)
    nestedTagPrefixesWork = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "desktop"
                "desktop:custom"
                "desktop:custom:hyprland"
              ];
              config.substrate.modules.programs.desktopModule = {
                nixos = { };
                tags = [ "desktop" ];
              };
              config.substrate.modules.programs.customModule = {
                nixos = { };
                tags = [ "desktop:custom" ];
              };
              config.substrate.users.testuser = {
                tags = [ "desktop:custom:hyprland" ];
              };
            }
          ];
          found = eval.config.substrate.moduleFinders.by-tags.find [ eval.config.substrate.users.testuser ];
        in
        # Both modules should be found (desktop and desktop:custom are implied by desktop:custom:hyprland)
        lib.length found == 2;
    };

    # The separator between tag levels is configurable. With "." the implication
    # chain works on dots, and a colon stops being a boundary.
    tagSeparatorIsConfigurable = {
      check =
        let
          # Under the configured "." separator, "audio.prod.midi" is hierarchical
          # and implies "audio", which the user's tag references.
          evalDotted = evalSubstrate [
            {
              config.substrate.settings.tags.separator = ".";
              config.substrate.settings.tags.definitions = [
                "audio"
                "audio.prod"
                "audio.prod.midi"
              ];
              config.substrate.modules.audioModule = {
                nixos = { };
                tags = [ "audio" ];
              };
              config.substrate.users.testuser = {
                tags = [ "audio.prod.midi" ];
              };
            }
          ];
          # Under the default ":" separator the same name is flat, so "audio" is
          # a parent of nothing and is reported unused.
          evalDefault = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "audio"
                "audio.prod"
                "audio.prod.midi"
              ];
              config.substrate.modules.audioModule = {
                nixos = { };
                tags = [ "audio" ];
              };
              config.substrate.users.testuser = {
                tags = [ "audio.prod.midi" ];
              };
            }
          ];
          unusedCheck =
            eval:
            builtins.head (builtins.filter (c: c.name == "unused-tags") eval.config.substrate.settings.checks);
        in
        (unusedCheck evalDotted).valid && !(unusedCheck evalDefault).valid;
    };

    # Test 10: hasTag function works correctly
    hasTagFunctionWorks = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "gui"
                "fonts"
                { "gui" = [ "fonts" ]; }
              ];
              config.substrate.users.testuser = {
                tags = [ "gui" ];
              };
            }
          ];
          # Get the extraArgsGenerator and create hasTag
          inherit (eval.config.substrate.settings) extraArgsGenerators;
          args = lib.mergeAttrsList (
            builtins.map (
              f:
              f {
                hostcfg = null;
                usercfg = eval.config.substrate.users.testuser;
              }
            ) extraArgsGenerators
          );
        in
        # hasTag should return true for "gui" and "fonts" (implied)
        args.hasTag "gui" && args.hasTag "fonts";
    };

    # Test 11: Empty tags list is valid
    emptyTagsListValid = {
      check =
        let
          eval = evalSubstrate [
            { config.substrate.settings.tags.definitions = [ ]; }
          ];
        in
        eval.config.substrate.settings.tags.definitions == [ ];
    };

    # Test 12: Prefix matching for hasTag works
    prefixMatchingForHasTag = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "theming"
                "theming:catppuccin"
                "theming:catppuccin:mocha"
              ];
              config.substrate.users.testuser = {
                tags = [ "theming:catppuccin:mocha" ];
              };
            }
          ];
          inherit (eval.config.substrate.settings) extraArgsGenerators;
          args = lib.mergeAttrsList (
            builtins.map (
              f:
              f {
                hostcfg = null;
                usercfg = eval.config.substrate.users.testuser;
              }
            ) extraArgsGenerators
          );
        in
        # hasTag should work for the exact tag and parent prefixes
        args.hasTag "theming:catppuccin:mocha" && args.hasTag "theming:catppuccin" && args.hasTag "theming";
    };

    # Test 13: Named selectors filter modules using boolean expressions
    selectorsFilterModules = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "common"
                "desktop"
                "laptop"
              ];
              config.substrate.settings.tags.selectors.workstation = {
                and = [
                  "common"
                  {
                    or = [
                      "desktop"
                      "laptop"
                    ];
                  }
                ];
              };
              config.substrate.settings.tags.selectors.laptopOnly = {
                and = [ "laptop" ];
              };
              config.substrate.modules.programs.included = {
                nixos = { };
                tags = [ "workstation" ];
              };
              config.substrate.modules.programs.excluded = {
                nixos = { };
                tags = [ "laptopOnly" ];
              };
              config.substrate.users.testuser.tags = [
                "common"
                "desktop"
              ];
            }
          ];
          found = eval.config.substrate.moduleFinders.by-tags.find [ eval.config.substrate.users.testuser ];
        in
        lib.length found == 1;
    };

    # Test 14: Selectors support negation without changing concrete tags
    selectorNegationWorks = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "desktop"
                "server"
              ];
              config.substrate.settings.tags.selectors.desktopOnly = {
                and = [
                  "desktop"
                  { not = "server"; }
                ];
              };
              config.substrate.modules.programs.desktopOnly = {
                nixos = { };
                tags = [ "desktopOnly" ];
              };
              config.substrate.users.testuser.tags = [ "desktop" ];
            }
          ];
          found = eval.config.substrate.moduleFinders.by-tags.find [ eval.config.substrate.users.testuser ];
        in
        lib.length found == 1;
    };

    # Test 15: hasTag evaluates named selectors
    hasTagSelectorWorks = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [
                "desktop"
                "laptop"
              ];
              config.substrate.settings.tags.selectors.graphical = {
                or = [
                  "desktop"
                  "laptop"
                ];
              };
              config.substrate.users.testuser.tags = [ "desktop" ];
            }
          ];
          inherit (eval.config.substrate.settings) extraArgsGenerators;
          args = lib.mergeAttrsList (
            builtins.map (
              f:
              f {
                hostcfg = null;
                usercfg = eval.config.substrate.users.testuser;
              }
            ) extraArgsGenerators
          );
        in
        args.hasTag "graphical";
    };

    # Test 16: Invalid selector leaves are rejected when the finder is used
    invalidSelectorRejected = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.settings.tags.definitions = [ "desktop" ];
              config.substrate.settings.tags.selectors.broken = {
                or = [
                  "missing"
                  "desktop"
                ];
              };
              config.substrate.modules.programs.test = {
                nixos = { };
                tags = [ "broken" ];
              };
              config.substrate.users.testuser.tags = [ "desktop" ];
            }
          ];
          result = builtins.tryEval (
            builtins.deepSeq (eval.config.substrate.moduleFinders.by-tags.find [
              eval.config.substrate.users.testuser
            ]) true
          );
        in
        !result.success;
    };
  };
in
runTests "Tags Extension Tests" tests
