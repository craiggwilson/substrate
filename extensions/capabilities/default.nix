{ lib, config, ... }:
let
  inherit (config.substrate) settings;
  slib = config.substrate.lib;

  finderName = "by-capabilities";

  # Separates the levels of a capability name, for prefix selection only.
  separator = config.substrate.settings.capabilities.separator;

  # Capability names are flat strings matched by equality. A requirement also
  # selects any capability it prefixes, so `core` selects `core:ssh` — but
  # nothing infers the reverse: including a module that offers `core:ssh` never
  # puts `core` into the provided set.
  capabilityType = lib.types.listOf lib.types.nonEmptyStr;

  allClasses = [ "generic" ] ++ settings.supportedClasses;
  reservedNames = allClasses ++ lib.attrNames settings.extraModuleOptions;

  hasSubstrateContent =
    node: builtins.any (class: node ? ${class} && node.${class} != null) allClasses;

  # Enumerate module nodes with their tree path. Core discards paths when it
  # flattens the tree, so walk it here rather than change the core collection:
  # paths are only needed for diagnostics, not for selection.
  walk =
    path: node:
    let
      children = lib.filterAttrs (n: v: (!builtins.elem n reservedNames) && builtins.isAttrs v) node;
      childEntries = lib.mapAttrsToList (n: v: walk (path ++ [ n ]) v) children;
      self = lib.optional (hasSubstrateContent node) {
        path = lib.concatStringsSep "/" path;
        inherit node;
      };
    in
    self ++ lib.concatLists childEntries;

  allModules = walk [ ] config.substrate.modules;

  # Prefix matching exists for selection only, and only from requirement to
  # capability. Matching is on separator boundaries so `programs` selects
  # `programs:vscode` but not `programsvc`.
  selects =
    requirement: capability:
    capability == requirement || lib.hasPrefix "${requirement}${separator}" capability;

  requirementsOf =
    configs:
    slib.unique (lib.concatMap (cfg: if cfg == null then [ ] else (cfg.requires or [ ])) configs);

  # Whether this entry satisfies a requirement, i.e. the requirement selects
  # something the entry offers. Requirement first, so `covered r` is a
  # predicate over entries.
  covered =
    requirement: entry: builtins.any (cap: selects requirement cap) (entry.node.provides or [ ]);

  # The gate for inclusion, and the one that never moves: the roots named it.
  # Whatever happens during resolution cannot widen what is wanted, so a
  # module whose offers are not reachable from requiredSet stays out no matter
  # how much else gets built. This is what stops a chain of extensions from
  # running away — admission always traces back to a requirement.
  wants =
    requiredSet: entry:
    builtins.any (cap: lib.any (r: selects r cap) requiredSet) (entry.node.provides or [ ]);

  # The gate that does move: an entry is admissible when its requirements are
  # accounted for, and "accounted for" includes what included modules already
  # provide. A module whose needs are nothing but already-provided capabilities
  # becomes eligible once those are in the build.
  admits =
    requiredSet: provided: entry:
    lib.all (r: lib.elem r requiredSet || builtins.elem r provided) (entry.node.requires or [ ]);

  # Monotone fixpoint: included and provided only grow, both bounded by the
  # module set, so this converges and the result does not depend on the order
  # modules happen to be visited in.
  resolveFrom =
    requiredSet:
    let
      loop =
        included: provided:
        let
          next = lib.filter (entry: wants requiredSet entry && admits requiredSet provided entry) allModules;
          # Every pass recomputes from allModules, so `next` is always the whole
          # set that satisfies both gates right now, never an increment. It can
          # therefore only grow.
          settled = builtins.length next == builtins.length included;
        in
        if settled then
          {
            inherit requiredSet;
            # Tree order, not discovery order: the walk is sorted and stable, so
            # module lists (and the imports built from them) do not shift with
            # the iteration.
            includedEntries = included;
            included = map (e: e.node) included;
            # Exactly what those modules declare. No prefix inference here, so
            # hasCapability "programs" is false when only "programs:vscode" is
            # offered.
            providedCapabilities = provided;
          }
        else
          # Recomputed from the whole of `next`, not just what this pass added,
          # so `provided` never loses an alias the set already contained.
          let
            grown = slib.unique (lib.concatMap (e: e.node.provides or [ ]) next);
          in
          loop next (slib.unique (provided ++ grown));
    in
    loop [ ] [ ];

  resolve = configs: resolveFrom (requirementsOf configs);

  # Diagnostics ask whether a requirement is satisfied *in the result*, which
  # is not the same question as the admission gate above.
  unmetRequirements =
    resolution:
    lib.filter (r: !(builtins.any (covered r) resolution.includedEntries)) resolution.requiredSet;

  renderList = items: "[${lib.concatStringsSep ", " items}]";

  # Two failure modes, told apart because they are fixed differently: nothing
  # offers the capability (a name that matches no module at all), or every
  # module that does was filtered out because it needs something unnamed.
  describeProblems =
    resolution:
    let
      entriesCovering =
        r:
        let
          matching = lib.filter (covered r) allModules;
        in
        {
          inherit matching;
          unmetByThem = slib.unique (
            lib.concatMap (
              entry: lib.filter (req: !(builtins.elem req resolution.requiredSet)) (entry.node.requires or [ ])
            ) matching
          );
        };
    in
    map (
      r:
      let
        detail = entriesCovering r;
      in
      if detail.matching == [ ] then
        "  Capability '${r}' is required but no module offers it."
      else
        "  Capability '${r}' is offered by ${toString (builtins.length detail.matching)} module(s), all filtered out; they require ${renderList detail.unmetByThem}."
    ) (unmetRequirements resolution);

  renderProblems = lines: ''
    substrate: capability resolution failed.

    ${lib.concatStringsSep "\n\n" lines}

    A module is included when it offers something a requirement selects and
    needs nothing the build has not already provided. A requirement selects a
    capability it prefixes, never the reverse. For the difference between
    capabilities and tags, see docs/src/extensions/capabilities.md.
  '';

  # Roots for a builder context. A host build passes a null usercfg, in which
  # case every user on the host contributes their own requirements.
  requirementsForContext =
    { hostcfg, usercfg }:
    requirementsOf (
      lib.optionals (hostcfg != null) [ hostcfg ]
      ++ lib.optionals (usercfg != null) [ usercfg ]
      ++ lib.optionals (usercfg == null && hostcfg != null) (
        map (user: config.substrate.users.${user}) hostcfg.users
      )
    );
in
{
  options.substrate = {
    hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            requires = lib.mkOption {
              type = capabilityType;
              default = [ ];
              description = ''
                Capabilities this host needs, unioned with those of every user
                on the host. Naming a capability selects every module that
                offers it. Each one has to end up covered by an included module;
                a requirement nothing satisfies is a build error.
              '';
            };
          };
        }
      );
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            requires = lib.mkOption {
              type = capabilityType;
              default = [ ];
              description = ''
                Capabilities this user needs, resolved together with the host's
                own. A capability required only by a user is satisfied for every
                configuration that user appears in.
              '';
            };
          };
        }
      );
    };

    # No `description` or `default` here: core already supplies both, and
    # redefining either makes lib/modules.nix reject the option outright. Only
    # `type` widens the enum, the way the tags extension does.
    settings.modulesFinder = lib.mkOption {
      type = lib.types.enum [ finderName ];
    };

    # Separates the levels of a capability name, for prefix selection only.
    settings.capabilities.separator = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = ":";
      description = ''
        The character separating the levels of a capability name. The default ":"
        makes a requirement of `programs` select a module offering
        `programs:vscode`; changing it to "." makes that pairing work on
        `programs.vscode` instead. It affects selection only — capability names
        are otherwise flat strings, and nothing is inferred from a suffix.
      '';
    };
  };

  config.substrate = {
    moduleFinders.${finderName}.find =
      cfgs:
      let
        resolution = resolve cfgs;
        problems = describeProblems resolution;
      in
      if problems == [ ] then resolution.included else throw (renderProblems problems);

    settings = {
      extraModuleOptions = {
        provides = lib.mkOption {
          type = capabilityType;
          default = [ ];
          description = ''
            Capabilities this module offers. A requirement selects this module
            when it names one of these, or any capability they prefix, so
            `programs` selects a module offering `programs:vscode`.

            Convention: a module that declares options should offer a capability
            for them, and modules that set those options should require it.
            That keeps the pairing explicit instead of relying on two
            unrelated tags happening to land in the same configuration.
          '';
        };

        requires = lib.mkOption {
          type = capabilityType;
          default = [ ];
          description = ''
            Capabilities this module needs. A host or user has to name each one,
            or some already-included module has to provide it, before this module
            is a candidate. One that needs something nothing supplies is filtered
            out rather than failing the build. That is what lets a GUI tool and a
            headless tool both offer `programming` while only the headless one is
            included on a machine without a desktop.

            Modules that must load together should offer the same capability
            instead of requiring each other: a requirement is only ever a filter,
            so relying on one to pull a sibling in works by accident.
          '';
        };
      };

      modulesFinder = finderName;

      extraArgsGenerators = [
        (args: {
          hasCapability =
            capability:
            builtins.elem capability (resolveFrom (requirementsForContext args)).providedCapabilities;
        })
      ];

      checks =
        let
          resolutionCheck =
            let
              failing = lib.filter (h: unmetRequirements h.resolution != [ ]) (
                lib.mapAttrsToList (hostname: hostcfg: {
                  inherit hostname;
                  resolution = resolve ([ hostcfg ] ++ (map (user: config.substrate.users.${user}) hostcfg.users));
                }) config.substrate.hosts
              );
              # Bind the body outside the lambda: a string containing an
              # interpolation that itself holds a string mis-braces the parser.
              describeHost =
                h:
                let
                  body = lib.concatStringsSep "\n" (describeProblems h.resolution);
                in
                "Host '${h.hostname}':\n${body}";
            in
            {
              name = "capability-resolution";
              valid = failing == [ ];
              message =
                if failing == [ ] then
                  "Every host's capability requirements are covered by an included module"
                else
                  lib.concatStringsSep "\n\n" (map describeHost failing);
            };

          unusedCheck =
            let
              # Reported per module, not per capability. A module offering both
              # "programs:vscodium" and "programming" and reached through
              # "programming" is doing its job — the leaf name is a deliberate
              # alias for targeting it directly, and flagging it would be noise.
              includedPaths = slib.unique (
                builtins.concatLists (
                  map (
                    hostcfg:
                    (resolve ([ hostcfg ] ++ (map (user: config.substrate.users.${user}) hostcfg.users)))
                    .includedEntries
                  ) (builtins.attrValues config.substrate.hosts)
                )
              );
              unusedEntries = lib.filter (e: !(builtins.elem e includedPaths)) allModules;
              describeEntry =
                e:
                let
                  offered = e.node.provides or [ ];
                in
                "  ${e.path}${if offered == [ ] then " (offers nothing)" else " offers ${renderList offered}"}";
            in
            {
              name = "unused-modules";
              valid = unusedEntries == [ ];
              warn = true;
              message =
                if unusedEntries == [ ] then
                  "Every module is included by some host"
                else
                  ''
                    No host selects these modules:

                    ${lib.concatStringsSep "\n" (map describeEntry unusedEntries)}

                    Either something should require one of them, or the module is
                    dead weight.
                  '';
            };

          # A module requiring something only it provides. Satisfiable once a
          # root names the capability, so it does not break resolution — but it
          # usually means a name is wrong, and it silently masks that: the
          # requirement is met by the module's own offer instead of by whatever
          # was meant to supply it.
          selfReferenceCheck =
            let
              offenders = lib.filter (
                e: (lib.intersectLists (e.node.provides or [ ]) (e.node.requires or [ ])) != [ ]
              ) allModules;
              describeEntry =
                e:
                let
                  shared = lib.intersectLists (e.node.provides or [ ]) (e.node.requires or [ ]);
                in
                "  ${e.path} requires ${renderList shared}, which only it provides.";
            in
            {
              name = "self-referential-capabilities";
              valid = offenders == [ ];
              warn = true;
              message =
                if offenders == [ ] then
                  "No module requires a capability only it provides"
                else
                  ''
                    These modules require something only they provide:

                    ${lib.concatStringsSep "\n" (map describeEntry offenders)}

                    The requirement is satisfied by the module's own offer, so it
                    never catches the case it was meant to.
                  '';
            };
        in
        [
          resolutionCheck
          unusedCheck
          selfReferenceCheck
        ];
    };
  };
}
