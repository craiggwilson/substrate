{ lib, config, ... }:
let
  settings = config.substrate.settings;
  moduleFinders = config.substrate.moduleFinders;

  # Extracts a name from a path by taking the basename and removing .nix suffix.
  # Works for both files (foo.nix -> foo) and directories (foo/ -> foo).
  nameFromPath =
    path:
    let
      basename = baseNameOf path;
    in
    lib.removeSuffix ".nix" basename;

  unique = list: lib.foldl' (acc: x: if lib.elem x acc then acc else acc ++ [ x ]) [ ] list;

  extractClassModules =
    class: mods:
    let
      extractClass =
        c: lib.flatten (lib.map (m: if m ? ${c} && m.${c} != null then [ m.${c} ] else [ ]) mods);
      classModules = extractClass class;
      genericModules = if class != "generic" then extractClass "generic" else [ ];
    in
    genericModules ++ classModules;

  # Find modules for a given class using the configured modules finder.
  # Takes a class name and a list of configs (e.g., [hostcfg], [hostcfg usercfg], [usercfg]).
  # Returns the extracted modules for that class.
  findModulesForClass =
    class: configs:
    let
      finder = moduleFinders.${settings.modulesFinder};
      mods = finder.find configs;
    in
    extractClassModules class mods;

  # The module arguments every generator contributes, as the builder passes them
  # into a target configuration. An arg whose value depends on that
  # configuration cannot come from here — a generator runs in the builder, outside
  # the configuration being built — so it is published by a class module writing
  # `_module.args` instead. A class module extending an argument another
  # extension publishes does it the same way, with lib.mkForce.
  extraArgsGenerator =
    {
      hostcfg,
      usercfg,
      inputs,
      pkgs,
    }:
    lib.mergeAttrsList (
      lib.map (
        f:
        f {
          inherit
            hostcfg
            usercfg
            inputs
            pkgs
            ;
        }
      ) settings.extraArgsGenerators
    );

  hasClass = class: builtins.elem class settings.supportedClasses;

  # Collect modules contributed for a given class, applying each matching
  # contributor to the build context. Builders call this with the class they
  # speak; contributions targeting other classes are ignored, so a
  # contribution is only ever loaded where its destination extension exists.
  contributionsFor =
    class: context:
    lib.concatMap (c: c.contribute context) (
      builtins.filter (c: c.class == class) settings.contributors
    );

  # Resolve a flake input by the role it plays (e.g., "nixpkgs"), preferring an
  # explicit substrate.settings.inputs entry over an input of the same name.
  # Inputs must be flake-shaped: they must have outPath and at least one of
  # outputs or lib. Pinned source trees (npins, niv, ...) should be adapted
  # with with-inputs before being passed to substrate.
  # Note: the throw must stay parenthesized; `a or b or throw "x"` parses as a
  # function call on the result of the or-chain.
  resolveInput =
    name: inputs:
    let
      value =
        settings.inputs.${name} or inputs.${name}
          or (throw "substrate: no input named '${name}'. Either name your input '${name}' or pass it explicitly via substrate.settings.inputs.${name}.");
    in
    if value ? outPath && (value ? outputs || value ? lib) then
      value
    else
      throw "substrate: input '${name}' is not flake-shaped (expected a flake input with outPath and outputs/lib). For non-flake sources (npins, niv, ...), adapt them with https://github.com/denful/with-inputs — see docs/src/builders.md.";
in
{
  options.substrate.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.anything;
    description = ''
      Library functions for use by builders, extensions, and other substrate components.
      Extensions can add functions by setting config.substrate.lib.<name> = <function>.
    '';
  };

  config.substrate.lib = {
    inherit
      nameFromPath
      unique
      findModulesForClass
      extraArgsGenerator
      contributionsFor
      hasClass
      resolveInput
      ;
  };
}
