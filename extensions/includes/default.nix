{ lib, config, ... }:
let
  inherit (config.substrate) settings;
  modules = config.substrate.modules;

  finderName = "by-includes";

  allClasses = [ "generic" ] ++ settings.supportedClasses;
  reservedNames = allClasses ++ lib.attrNames settings.extraModuleOptions;

  hasSubstrateContent =
    node: builtins.any (class: node ? ${class} && node.${class} != null) allClasses;

  hasIncludesContent = node: (node.includes or [ ]) != [ ];

  walk =
    path: node:
    let
      children = lib.filterAttrs (n: v: (!builtins.elem n reservedNames) && builtins.isAttrs v) node;
      childEntries = lib.mapAttrsToList (n: v: walk (path ++ [ n ]) v) children;
      self = lib.optional (hasSubstrateContent node || hasIncludesContent node) {
        path = lib.concatStringsSep "/" path;
        inherit node;
      };
    in
    self ++ lib.concatLists childEntries;

  allModules = walk [ ] modules;
  allModulesByPath = builtins.listToAttrs (
    map (entry: {
      name = entry.path;
      value = entry;
    }) allModules
  );

  # What an includes source names. Two forms, one meaning -- "these modules":
  #
  #   [ "programs/git" config.substrate.modules.programs.git ]  a list
  #   { hostcfg, usercfg, ... }: [ ... ]                          a function of the context
  #
  # A function returns the same thing as the list form, just computed from the
  # host/user context first.

  entries =
    context: source:
    if source ? __definition then
      entries context source.__definition
    else if builtins.isFunction source then
      entries context (source context)
    else if builtins.isList source then
      lib.concatMap (entry: entries context entry) source
    else if builtins.isString source then
      [ source ]
    else if builtins.isAttrs source && source ? __path then
      [ source.__path ]
    else
      throw "substrate: an includes value must be a list of module paths / module nodes or a function returning one; got ${builtins.typeOf source}";

  # Each config paired with what a conditional include should see about it. find
  # is handed the host first and, after it, the users that host is being built
  # for: [ hostcfg ] for a host alone, [ hostcfg usercfg ] for a single user, and
  # [ hostcfg ] ++ userConfigs for all of them. Position therefore decides which
  # config is the host.
  contextsFor =
    cfgs:
    lib.imap0 (i: cfg: {
      context = {
        hostcfg = if i == 0 then cfg else builtins.head cfgs;
        usercfg = if i == 0 then null else cfg;
      };
      includes = if cfg == null then [ ] else cfg.includes or [ ];
    }) cfgs;

  # Roots named by one config, in the order that config named them.
  rootsOf = c: entries c.context (c.includes or [ ]);

  includeType = lib.mkOptionType {
    name = "includeType";
    # Deliberately shallow. lib.types.listOf checks every element when the
    # option is read, and an entry can be a node of the module tree, so
    # checking would mean evaluating every named subtree just to look at it --
    # the work includes exists to avoid. So this accepts either the list form or
    # the context function form without inspecting a list's entries, and the
    # recursive walk does the checking where it can say what was wrong. Merge
    # tags each definition instead of concatenating them, so a definition
    # written as a function keeps its position and is still read as a function.
    check = x: builtins.isList x || builtins.isFunction x;
    merge = _loc: defs: builtins.map (d: { __definition = d.value; }) defs;
  };

  resolveEntry =
    path:
    allModulesByPath.${path}
      or (throw "substrate: unknown module path '${path}' in includes; known paths: ${lib.concatStringsSep ", " (builtins.attrNames allModulesByPath)}");

  renderCycle = stack: lib.concatStringsSep " -> " stack;

  visit =
    context: path: stack: seen:
    if builtins.elem path stack then
      throw "substrate: includes cycle detected: ${renderCycle (stack ++ [ path ])}"
    else if builtins.elem path seen then
      {
        inherit seen;
        includedEntries = [ ];
      }
    else
      let
        entry = resolveEntry path;
        nextStack = stack ++ [ path ];
        nextSeen = seen ++ [ path ];
        childIncludes = entries context (entry.node.includes or [ ]);
        childResult =
          lib.foldl'
            (
              acc: child:
              let
                result = visit context child nextStack acc.seen;
              in
              {
                inherit (result) seen;
                includedEntries = acc.includedEntries ++ result.includedEntries;
              }
            )
            {
              seen = nextSeen;
              includedEntries = [ ];
            }
            childIncludes;
      in
      {
        inherit (childResult) seen;
        includedEntries = childResult.includedEntries ++ [ entry ];
      };

  resolveFromRoots =
    context: roots:
    (lib.foldl'
      (
        acc: root:
        let
          result = visit context root [ ] acc.seen;
        in
        {
          inherit (result) seen;
          includedEntries = acc.includedEntries ++ result.includedEntries;
        }
      )
      {
        seen = [ ];
        includedEntries = [ ];
      }
      roots
    ).includedEntries;
in
{
  options.substrate = {
    hosts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.includes = lib.mkOption {
            type = includeType;
            default = [ ];
            description = "The modules to include for this host.";
          };
        }
      );
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.includes = lib.mkOption {
            type = includeType;
            default = [ ];
            description = "The modules to include for this user.";
          };
        }
      );
    };

    settings.modulesFinder = lib.mkOption {
      type = lib.types.enum [ finderName ];
    };
  };

  config.substrate = {
    # Resolve once per config, so a conditional include inside a module sees the
    # host or user that reached it rather than whichever config happened to be
    # considered first. The host is always first, so a module both the host and
    # one of its users include resolves under the host, and the union below
    # collapses it to one entry either way.
    moduleFinders.${finderName}.find =
      cfgs:
      let
        resolved = lib.concatMap (c: lib.map (entry: entry.node) (resolveFromRoots c.context (rootsOf c))) (
          contextsFor cfgs
        );
      in
      # Keyed by address, so a module included for several configs is returned
      # once. The address is also the order, which makes the result stable.
      lib.attrValues (
        lib.listToAttrs (
          lib.map (node: {
            name = node.__path;
            value = node;
          }) resolved
        )
      );

    settings = {
      extraModuleOptions.includes = lib.mkOption {
        type = includeType;
        default = [ ];
        description = "The modules included transitively from this module.";
      };

      modulesFinder = finderName;
    };
  };
}
