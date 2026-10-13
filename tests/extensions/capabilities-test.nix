# Tests for substrate capabilities extension
# Run with: nix eval -f substrate/tests/extensions/capabilities-test.nix
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) lib mkEvalSubstrate runTests;

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
    ../../extensions/capabilities/default.nix
  ];

  find = eval: cfgs: eval.config.substrate.moduleFinders.by-capabilities.find cfgs;

  # Modules come back as raw nodes, so identify them by what they offer.
  offers = capability: modules: builtins.any (m: lib.elem capability (m.provides or [ ])) modules;

  # tryEval reports success but hands back an error value that will not
  # stringify, so this only answers "did this fail". Message content is
  # asserted through the extension's checks instead.
  throws = thunk: !(builtins.tryEval (builtins.deepSeq thunk true)).success;

  checkByName =
    eval: name:
    builtins.head (builtins.filter (c: c.name == name) eval.config.substrate.settings.checks);

  mkArgs =
    eval: context:
    lib.mergeAttrsList (lib.map (f: f context) eval.config.substrate.settings.extraArgsGenerators);

  tests = {
    # A requirement selects every module offering it
    requirementSelectsProviders = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "audio" ];
              config.substrate.modules.pipewire = {
                provides = [ "audio" ];
                nixos.pipewire = true;
              };
              config.substrate.modules.pulseaudio = {
                provides = [ "audio" ];
                nixos.pulse = true;
              };
              config.substrate.modules.unrelated = {
                provides = [ "video" ];
                nixos.video = true;
              };
            }
          ];
          found = find eval [ eval.config.substrate.hosts.h ];
        in
        builtins.length found == 2 && offers "audio" found;
    };

    # A requirement selects any capability it prefixes, on ':' boundaries
    prefixSelectsNestedCapability = {
      check =
        let
          evalOne = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "core" ];
              config.substrate.modules.core.ssh = {
                provides = [ "core:ssh" ];
                nixos.ssh = true;
              };
              config.substrate.modules.core.networking = {
                provides = [ "core:networking" ];
                nixos.networking = true;
              };
            }
          ];
          # A shorter name must not select a longer one that merely starts the same
          evalNotPrefix = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "program" ];
              config.substrate.modules.vscodium = {
                provides = [ "programsvc" ];
                nixos.v = true;
              };
            }
          ];
          notPrefixCheck = checkByName evalNotPrefix "capability-resolution";
        in
        builtins.length (find evalOne [ evalOne.config.substrate.hosts.h ]) == 2
        && !notPrefixCheck.valid
        && lib.hasInfix "no module offers it" notPrefixCheck.message;
    };

    # A module that needs something nobody named is filtered out, and when a
    # sibling survives that is not an error — this is what lets a headless
    # server have `programming` without a desktop
    filteredModuleIsNotAnErrorWhenASiblingSurvives = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "programming" ];
              config.substrate.modules.vscode = {
                provides = [ "programming" ];
                requires = [ "gui" ];
                nixos.vscode = true;
              };
              config.substrate.modules.grep = {
                provides = [ "programming" ];
                nixos.grep = true;
              };
            }
          ];
          found = find eval [ eval.config.substrate.hosts.h ];
        in
        builtins.length found == 1
        && offers "programming" found
        && (checkByName eval "capability-resolution").valid;
    };

    # Naming the missing capability brings the filtered module back in
    namedDependencyBringsModuleBack = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [
                "programming"
                "gui"
              ];
              config.substrate.modules.vscode = {
                provides = [ "programming" ];
                requires = [ "gui" ];
                nixos.vscode = true;
              };
              config.substrate.modules.grep = {
                provides = [ "programming" ];
                nixos.grep = true;
              };
              config.substrate.modules.bar = {
                provides = [ "gui" ];
                nixos.bar = true;
              };
            }
          ];
          found = find eval [ eval.config.substrate.hosts.h ];
        in
        builtins.length found == 3;
    };

    # When every provider of a required capability is filtered out, that is an
    # error — this is what makes a missing dependency a build failure rather
    # than a module silently not loading
    allProvidersFilteredIsAnError = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "hardware:model:dell" ];
              config.substrate.modules.hardware.models.dell = {
                provides = [ "hardware:model:dell" ];
                requires = [ "hardware:audio" ];
                nixos.dell = true;
              };
              config.substrate.modules.hardware.audio = {
                provides = [ "hardware:audio" ];
                nixos.audio = true;
              };
            }
          ];
          check = checkByName eval "capability-resolution";
        in
        throws (find eval [ eval.config.substrate.hosts.h ])
        && !check.valid
        && lib.hasInfix "all filtered out" check.message
        && lib.hasInfix "hardware:audio" check.message;
    };

    # A requirement no module offers at all is an error, told apart from the
    # filtered case by its wording
    noProviderIsAnError = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "hardware:audoi" ];
              config.substrate.modules.base = {
                provides = [ "base" ];
                nixos.base = true;
              };
            }
          ];
          check = checkByName eval "capability-resolution";
        in
        throws (find eval [ eval.config.substrate.hosts.h ])
        && !check.valid
        && lib.hasInfix "no module offers it" check.message;
    };

    # A capability that only enters the required set by being prefixed is never
    # itself required, so its module being filtered out is silent
    prefixedChildrenAreNeverUnchecked = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "core" ];
              config.substrate.modules.core.ssh = {
                provides = [ "core:ssh" ];
                requires = [ "kernel" ];
                nixos.ssh = true;
              };
              config.substrate.modules.core.utils = {
                provides = [ "core:utils" ];
                nixos.utils = true;
              };
            }
          ];
          found = find eval [ eval.config.substrate.hosts.h ];
        in
        # core:ssh's module is filtered (nothing named kernel) but core is still
        # satisfied by core:utils, so no error and the host still builds
        builtins.length found == 1
        && offers "core:utils" found
        && (checkByName eval "capability-resolution").valid;
    };

    # A module with only requirements and no offers is never included
    moduleWithNoProvidesIsNeverIncluded = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "base" ];
              config.substrate.modules.base = {
                provides = [ "base" ];
                nixos.base = true;
              };
              config.substrate.modules.requiring = {
                requires = [ "base" ];
                nixos.requiring = true;
              };
            }
          ];
        in
        builtins.length (find eval [ eval.config.substrate.hosts.h ]) == 1;
    };

    # Capability names are flat: nothing about ':' is special beyond selection
    capabilityNamesAreFlat = {
      check =
        let
          evalLonger = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "hardware:audio" ];
              config.substrate.modules.hardware = {
                provides = [ "hardware" ];
                nixos.hardware = true;
              };
            }
          ];
          evalExact = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "hardware:audio" ];
              config.substrate.modules.hardware.audio = {
                provides = [ "hardware:audio" ];
                nixos.audio = true;
              };
            }
          ];
        in
        throws (find evalLonger [ evalLonger.config.substrate.hosts.h ])
        && builtins.length (find evalExact [ evalExact.config.substrate.hosts.h ]) == 1;
    };

    # The separator between capability levels is configurable, and it governs
    # prefix selection only. With "." the pairing works on dots, and a colon
    # inside a name stops being a boundary.
    capabilitySeparatorIsConfigurable = {
      check =
        let
          evalDotted = evalSubstrate [
            {
              config.substrate.settings.capabilities.separator = ".";
              config.substrate.hosts.h.requires = [ "core" ];
              config.substrate.modules.core.ssh = {
                provides = [ "core.ssh" ];
                nixos.ssh = true;
              };
              config.substrate.modules.core.networking = {
                provides = [ "core.networking" ];
                nixos.networking = true;
              };
            }
          ];
          # Under the default separator a dotted name is a single flat name
          evalDefault = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "core" ];
              config.substrate.modules.core.ssh = {
                provides = [ "core.ssh" ];
                nixos.ssh = true;
              };
            }
          ];
          defaultCheck = checkByName evalDefault "capability-resolution";
        in
        # the dotted requirement selects both dotted providers
        builtins.length (find evalDotted [ evalDotted.config.substrate.hosts.h ]) == 2
        # and under the default it selects nothing
        && !defaultCheck.valid
        && lib.hasInfix "no module offers it" defaultCheck.message;
    };

    # A capability alone does not make a module. Substrate decides a tree node
    # is a module by whether it has a class body, not by whether it declares
    # capabilities.
    capabilitiesAloneDoNotMakeAModule = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "ghost" ];
              config.substrate.modules.ghost.provides = [ "ghost" ];
            }
          ];
        in
        throws (find eval [ eval.config.substrate.hosts.h ]);
    };

    # A module whose only requirement is something an included module provides
    # joins on a later pass, without ever being named by a root. This is what
    # lets an extension of an extension arrive.
    extensionCascadesFromProvidedCapabilities = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [
                "ai:clients"
                "programming"
                "gui"
              ];
              config.substrate.modules.programs.vscode = {
                provides = [
                  "programs:vscode"
                  "programming"
                ];
                requires = [ "gui" ];
                nixos.vscode = true;
              };
              # offers both the sweep it is reached by and the name its own child needs
              config.substrate.modules.programs.vscode.mcp = {
                provides = [
                  "ai:clients"
                  "programs:vscode:mcp"
                ];
                requires = [ "programs:vscode" ];
                nixos.mcp = true;
              };
              # two hops out, gated on the same way
              config.substrate.modules.programs.vscode.mcp.tools = {
                provides = [ "ai:clients" ];
                requires = [ "programs:vscode:mcp" ];
                nixos.tools = true;
              };
              config.substrate.modules.bar = {
                provides = [ "gui" ];
                nixos.bar = true;
              };
            }
          ];
          found = find eval [ eval.config.substrate.hosts.h ];
          # vscode offers two names, so compare the set rather than the list
          offered = map (m: lib.sort builtins.lessThan (m.provides or [ ])) found;
        in
        builtins.length found == 4
        && lib.any (p: lib.elem "programs:vscode" p) offered
        && lib.any (p: lib.elem "ai:clients" p) offered
        && (checkByName eval "capability-resolution").valid;
    };

    # Admission always traces back to a requirement: a module satisfying its
    # requirements but offering nothing reachable from requiredSet stays out, no
    # matter how much else gets built.
    satisfyingRequirementsIsNotEnough = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [
                "programming"
                "gui"
              ];
              config.substrate.modules.programs.vscode = {
                provides = [
                  "programs:vscode"
                  "programming"
                ];
                requires = [ "gui" ];
                nixos.vscode = true;
              };
              config.substrate.modules.bar = {
                provides = [ "gui" ];
                nixos.bar = true;
              };
              # Its requirement is met (vscode is in by now) but it offers
              # nothing a requirement selects, so it never joins.
              config.substrate.modules.drift = {
                requires = [ "programs:vscode" ];
                nixos.drift = true;
              };
            }
          ];
          found = find eval [ eval.config.substrate.hosts.h ];
        in
        builtins.length found == 2 && !(offers "" found);
    };

    # A module with no requirements does not drift in on a later pass either,
    # for the same reason
    requirementlessModuleStaysOut = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "base" ];
              config.substrate.modules.base = {
                provides = [ "base" ];
                nixos.base = true;
              };
              config.substrate.modules.orphan.nixos.orphan = true;
            }
          ];
        in
        builtins.length (find eval [ eval.config.substrate.hosts.h ]) == 1;
    };

    # Filtering survives the loop even when an included module does offer
    # `programming`: nothing offers `gui`, so the editor stays out
    guiFilteringHoldsAcrossTheLoop = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "programming" ];
              config.substrate.modules.vscode = {
                provides = [
                  "programs:vscode"
                  "programming"
                ];
                requires = [ "gui" ];
                nixos.vscode = true;
              };
              config.substrate.modules.grep = {
                provides = [ "programming" ];
                nixos.grep = true;
              };
            }
          ];
          found = find eval [ eval.config.substrate.hosts.h ];
        in
        builtins.length found == 1
        && offers "programming" found
        && !(offers "programs:vscode" found)
        && (checkByName eval "capability-resolution").valid;
    };

    # Requiring a capability only the module itself provides is satisfiable, so
    # it does not break resolution — but it is reported, because it almost
    # always means a name is wrong and the requirement never catches what it
    # was meant to.
    selfReferentialCapabilityIsReported = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "base" ];
              config.substrate.modules.base = {
                provides = [ "base" ];
                requires = [ "base" ];
                nixos.base = true;
              };
            }
          ];
          selfRef = checkByName eval "self-referential-capabilities";
        in
        !selfRef.valid
        && selfRef.warn
        && lib.hasInfix "base" selfRef.message
        # resolution itself is unaffected
        && (checkByName eval "capability-resolution").valid
        && builtins.length (find eval [ eval.config.substrate.hosts.h ]) == 1;
    };

    # A module that only requires something already provided is stable: it does
    # not oscillate, and the loop terminates with it included exactly once.
    moduleOrderIsStable = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [
                "core"
                "core:apps"
              ];
              config.substrate.modules.core.utils = {
                provides = [ "core:utils" ];
                nixos.utils = true;
              };
              config.substrate.modules.core.apps = {
                provides = [ "core:apps" ];
                requires = [ "core:utils" ];
                nixos.apps = true;
              };
              config.substrate.modules.core.network = {
                provides = [ "core:network" ];
                nixos.network = true;
              };
            }
          ];
          found = find eval [ eval.config.substrate.hosts.h ];
          again = find eval [ eval.config.substrate.hosts.h ];
          # Sorted by capability name, because the walk visits the tree in key order and
          # not in the order passes pulled modules in
          provides = map (m: m.provides or [ ]) found;
        in
        builtins.length found == 3
        &&
          provides == [
            [ "core:apps" ]
            [ "core:network" ]
            [ "core:utils" ]
          ]
        && found == again;
    };

    # Users are independent roots, and a host build with a null usercfg still
    # sees every user on the host
    usersContributeTheirOwnRequirements = {
      check =
        let
          evalUserRoot = evalSubstrate [
            {
              config.substrate.users.u.requires = [ "vpn:work" ];
              config.substrate.modules.vpn.work = {
                provides = [ "vpn:work" ];
                nixos.vpn = true;
              };
              config.substrate.modules.base = {
                provides = [ "base" ];
                nixos.base = true;
              };
            }
          ];
          evalHostBuild = evalSubstrate [
            {
              config.substrate.hosts.h = {
                users = [ "u" ];
                requires = [ "base" ];
              };
              config.substrate.users.u.requires = [ "vpn:work" ];
              config.substrate.modules.base = {
                provides = [ "base" ];
                nixos.base = true;
              };
              config.substrate.modules.vpn.work = {
                provides = [ "vpn:work" ];
                nixos.vpn = true;
              };
            }
          ];
        in
        # A user root selects only what it asked for
        builtins.length (find evalUserRoot [ evalUserRoot.config.substrate.users.u ]) == 1
        # A host build unions the host with all of its users
        &&
          builtins.length (
            find evalHostBuild (
              [ evalHostBuild.config.substrate.hosts.h ] ++ [ evalHostBuild.config.substrate.users.u ]
            )
          ) == 2;
    };

    # hasCapability reads what the included modules offer, not what the roots
    # asked for, and it never walks a prefix backwards
    hasCapabilityReadsProvidedSet = {
      check =
        let
          eval = evalSubstrate [
            {
              # gui is named, so vscode passes its filter and gets included
              config.substrate.hosts.h.requires = [
                "programming"
                "gui"
              ];
              config.substrate.modules.vscode = {
                provides = [
                  "programs:vscode"
                  "programming"
                ];
                requires = [ "gui" ];
                nixos.vscode = true;
              };
              config.substrate.modules.bar = {
                provides = [ "gui" ];
                nixos.bar = true;
              };
            }
          ];
          args = mkArgs eval {
            hostcfg = eval.config.substrate.hosts.h;
            usercfg = null;
          };
        in
        # vscode's leaf name was never required, yet it is offered here
        args.hasCapability "programs:vscode"
        # and the prefix it hangs off is not, because nothing walks backwards
        && !args.hasCapability "programs"
        && args.hasCapability "gui";
    };

    # A capability that is neither required nor offered is not provided
    hasCapabilityIsFalseForUnprovided = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "base" ];
              config.substrate.modules.base = {
                provides = [ "base" ];
                nixos.base = true;
              };
            }
          ];
          args = mkArgs eval {
            hostcfg = eval.config.substrate.hosts.h;
            usercfg = null;
          };
        in
        !args.hasCapability "audio" && args.hasCapability "base";
    };

    # A module can pull in an interface module it never names, only the
    # capability it needs
    requirementPairsAnInterfaceModule = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [
                "hardware:model:dell"
                "hardware:audio"
              ];
              config.substrate.modules.hardware.audio = {
                provides = [ "hardware:audio" ];
                generic.audioOption = 1;
              };
              config.substrate.modules.hardware.model.dell = {
                provides = [ "hardware:model:dell" ];
                requires = [ "hardware:audio" ];
                generic.usesAudioOption = true;
              };
            }
          ];
          found = find eval [ eval.config.substrate.hosts.h ];
        in
        builtins.length found == 2 && offers "hardware:audio" found;
    };

    # The finder still hands class fragments back through the shared lib
    findModulesForClassSplitsGeneric = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "base" ];
              config.substrate.modules.base = {
                provides = [ "base" ];
                generic.shared = 1;
                nixos.specific = 2;
              };
            }
          ];
          modulesFor =
            class: eval.config.substrate.lib.findModulesForClass class [ eval.config.substrate.hosts.h ];
        in
        builtins.length (modulesFor "generic") == 1 && builtins.length (modulesFor "nixos") == 2;
    };

    # Nothing required, nothing included
    noRootsSelectsNothing = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.modules.base = {
                provides = [ "base" ];
                nixos.base = true;
              };
            }
          ];
        in
        builtins.length (find eval [ ]) == 0;
    };

    # A module no host selects is dead weight
    unusedModuleWarns = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "core" ];
              config.substrate.modules.core.utils = {
                provides = [ "core:utils" ];
                nixos.utils = true;
              };
              config.substrate.modules.orphan = {
                provides = [ "never:used" ];
                nixos.orphan = true;
              };
            }
          ];
          unused = checkByName eval "unused-modules";
        in
        !unused.valid && unused.warn && lib.hasInfix "orphan" unused.message;
    };

    # A deliberate leaf alias is not an unused capability: the module is
    # included through its other offer, which is the point of the alias.
    leafAliasIsNotFlagged = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [
                "programming"
                "gui"
              ];
              config.substrate.modules.vscode = {
                provides = [
                  "programs:vscode"
                  "programming"
                ];
                requires = [ "gui" ];
                nixos.vscode = true;
              };
              config.substrate.modules.bar = {
                provides = [ "gui" ];
                nixos.bar = true;
              };
            }
          ];
        in
        (checkByName eval "unused-modules").valid;
    };

    # ...and a module every host does select is not reported
    usedModuleNotWarned = {
      check =
        let
          eval = evalSubstrate [
            {
              config.substrate.hosts.h.requires = [ "core" ];
              config.substrate.modules.core.utils = {
                provides = [ "core:utils" ];
                nixos.utils = true;
              };
            }
          ];
        in
        (checkByName eval "unused-modules").valid;
    };
  };

  run = runTests "capabilities extension" tests;
in
run
