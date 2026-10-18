{ lib, config, ... }:
let
  inherit (config.substrate) settings;
  slib = config.substrate.lib;

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

  allModules = walk [ ] config.substrate.modules;
  allModulesByPath = builtins.listToAttrs (
    map (entry: {
      name = entry.path;
      value = entry;
    }) allModules
  );

  includePathType = lib.types.str;
  includeListType = lib.types.listOf includePathType;

  resolveEntry =
    path:
    allModulesByPath.${path}
      or (throw "substrate: unknown module path '${path}' in includes; known paths: ${lib.concatStringsSep ", " (builtins.attrNames allModulesByPath)}");

  includeRoots =
    cfgs: slib.unique (lib.concatMap (cfg: if cfg == null then [ ] else (cfg.includes or [ ])) cfgs);

  renderCycle = stack: lib.concatStringsSep " -> " stack;

  visit =
    path: stack: seen:
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
        childResult =
          lib.foldl'
            (
              acc: child:
              let
                result = visit child nextStack acc.seen;
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
            (entry.node.includes or [ ]);
      in
      {
        inherit (childResult) seen;
        includedEntries = childResult.includedEntries ++ [ entry ];
      };

  resolveFromRoots =
    roots:
    (lib.foldl'
      (
        acc: root:
        let
          result = visit root [ ] acc.seen;
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
            type = includeListType;
            default = [ ];
            description = "Module paths to include from this host.";
          };
        }
      );
    };

    users = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options.includes = lib.mkOption {
            type = includeListType;
            default = [ ];
            description = "Module paths to include from this user.";
          };
        }
      );
    };

    settings.modulesFinder = lib.mkOption {
      type = lib.types.enum [ finderName ];
    };
  };

  config.substrate = {
    moduleFinders.${finderName}.find = cfgs: resolveFromRoots (includeRoots cfgs);

    settings = {
      extraModuleOptions.includes = lib.mkOption {
        type = includeListType;
        default = [ ];
        description = "Module paths included transitively from this module.";
      };

      modulesFinder = finderName;
    };
  };
}
