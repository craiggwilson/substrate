{ lib, config, ... }:
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

  # The "all" finder returns all modules regardless of the configs passed
  config.substrate.moduleFinders.all = {
    find = _cfgs: collectSubstrateModules config.substrate.modules;
  };

  # The module tree, readable as a Nix reference, so a host or user can name the
  # module it means instead of spelling its path. Declared after the tree itself
  # because it is the tree's own value, which the module system resolves lazily.
  config._module.args.substrateModules = config.substrate.modules;
}
