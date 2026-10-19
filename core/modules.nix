{
  lib,
  config,
  options,
  ...
}:
let
  inherit (config.substrate) settings;

  allClasses = [ "generic" ] ++ settings.supportedClasses;

  reservedNames = allClasses ++ lib.attrNames settings.extraModuleOptions;

  # A node's own address, threaded through the type rather than recovered by a
  # walk. lib.types.submodule is handed the attribute name, and lazyAttrsOf hands
  # that name down, so each level extends the prefix it sits under. This is what
  # lets an includes entry be a reference to a node instead of a string naming
  # one: the value a reference resolves to carries its own address, so nothing
  # has to compare nodes against each other to find one again.
  extend = prefix: name: if prefix == "" then name else "${prefix}/${name}";

  treeAt =
    prefix:
    lib.types.submodule (
      { name, ... }:
      {
        options =
          lib.genAttrs allClasses (
            _:
            lib.mkOption {
              type = lib.types.nullOr lib.types.deferredModule;
              default = null;
            }
          )
          // settings.extraModuleOptions
          // {
            __path = lib.mkOption {
              type = lib.types.str;
              default = extend prefix name;
              internal = true;
            };
          };
        freeformType = lib.types.lazyAttrsOf (treeAt (extend prefix name));
      }
    );

  hasSubstrateContent =
    module: builtins.any (class: module ? ${class} && module.${class} != null) allClasses;

  collectSubstrateModules =
    module:
    let
      childAttrs = lib.filterAttrs (n: v: (!builtins.elem n reservedNames) && builtins.isAttrs v) module;
      childModules = lib.flatten (lib.mapAttrsToList (_: collectSubstrateModules) childAttrs);
    in
    if hasSubstrateContent module then [ module ] ++ childModules else childModules;

  # A node is live when it carries class content of its own or something below
  # it does. Reported dead paths are the deepest nodes of each dead region, so
  # the path names the key the value was actually written at: a module written
  # for a class nobody registered comes back as "programs/zfs/darwin" rather
  # than the grouping node above it.
  classify =
    node:
    let
      childAttrs = lib.filterAttrs (n: v: (!builtins.elem n reservedNames) && builtins.isAttrs v) node;
      classified = lib.mapAttrsToList (_: classify) childAttrs;
      live = hasSubstrateContent node || builtins.any (c: c.live) classified;
    in
    {
      inherit live;
      dead = if live || classified != [ ] then lib.concatMap (c: c.dead) classified else [ node.__path ];
    };

  # Paths no finder can ever select: tree nodes with no supported-class content
  # anywhere beneath them. The tree's freeform type cannot tell an unregistered
  # class from a legitimate grouping node -- `modules.foo.darwin` and
  # `modules.foo.programs` are the same shape -- so this reports reachability
  # rather than trying to name the mistake. A grouping node above a live module
  # is never reported; only a subtree with nothing buildable under it is.
  unreachableModulePaths =
    node:
    lib.concatMap (c: c.dead) (
      lib.mapAttrsToList (_: classify) (
        lib.filterAttrs (n: v: (!builtins.elem n reservedNames) && builtins.isAttrs v) node
      )
    );
in
{
  options.substrate = {
    modules = lib.mkOption {
      description = "Modules available for inclusion in user and host configurations. Structure: substrate.modules.<path>.<to>.<module>";
      type = lib.types.submodule { freeformType = lib.types.lazyAttrsOf (treeAt ""); };
      default = { };
    };
    settings = {
      extraModuleOptions = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        description = "Additional typed options to recognize at each level of the module tree. The key is the attribute name, the value is the type.";
        default = { };
      };
    };
  };

  config = lib.mkMerge [
    {
      # The "all" finder returns all modules regardless of the configs passed.
      substrate.moduleFinders.all = {
        find = _cfgs: collectSubstrateModules config.substrate.modules;
      };

      # The module tree, readable as a Nix reference, so a host or user can name
      # the module it means instead of spelling its path. Declared after the tree
      # itself because it is the tree's own value, which the module system
      # resolves lazily.
      _module.args.substrateModules = config.substrate.modules;
    }
    (lib.optionalAttrs (options.substrate ? lib) {
      substrate.lib.unreachableModulePaths = unreachableModulePaths;
    })
  ];
}
