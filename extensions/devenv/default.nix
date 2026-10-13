{ lib, config, ... }:
let
  devenvCfg = config.substrate.devenv or { };
  slib = config.substrate.lib;

  mkDevenvShells =
    {
      pkgs,
      inputs,
      # Falls back to the consumer's inputs so a builder that supplies only
      # those still builds shells; it just resolves devenv from the consumer's
      # pin rather than substrate's.
      coreInputs ? inputs,
      ...
    }:
    let
      devenvInput = slib.resolveInput "devenv" coreInputs;

      # devenv's `devenv` wrapper runs a command by re-entering the flake as
      # `nix develop .#<name> --impure`, taking `<name>` from the module argument
      # `_module.args.name`. The name substrate publishes a shell under is its
      # attribute key, so hand that over: the wrapper then finds the shell it
      # was started from, instead of a `default` that may not exist.
      shellNamed = name: _: { _module.args.name = name; };

      # The same wrapper re-enters so that a command runs against a freshly
      # evaluated configuration, which is what a shell devenv built from a flake
      # needs and a substrate-built one does not: this shell is already running,
      # and re-entering can only land somewhere else — another shell name, a
      # builder whose output is not a flake, no flake in the working directory
      # at all. This is devenv's own opt-out of the re-entry, and mkDefault
      # leaves it overridable.
      alreadyEntered = _: { env.DEVENV_IN_DIRENV_SHELL = lib.mkDefault "true"; };
    in
    lib.mapAttrs (
      name: shellModule:
      devenvInput.lib.mkShell {
        inherit inputs pkgs;
        modules = [
          shellModule
          (shellNamed name)
          alreadyEntered
        ];
      }
    ) devenvCfg.shells;
  # A shell entry is a devenv module: an attribute set of devenv options, or a
  # function producing one. Both shapes must survive this option untouched,
  # because mkDevenvShells hands the value straight to devenv as the head of
  # `modules`.
  #
  # A bare `submodule` type cannot do that. nixpkgs turns a submodule's
  # definitions into modules of THIS configuration, and collectModules calls a
  # function value with THIS configuration's arguments — which are not devenv's.
  # Destructuring `pkgs` there fails, because this configuration has no `pkgs`
  # argument; the function is consumed before devenv ever sees it.
  #
  # `functionTo raw` is the branch `either` tries first, so a function entry
  # that is the ONLY definition of its name is never offered to the submodule
  # and reaches devenv callable. The word "only" is load-bearing: `either` falls
  # through to the submodule branch as soon as any definition of the same name
  # is an attribute set, and a function defined alongside one is collected as a
  # module of this configuration — the original failure, one definition away.
  # A function entry is therefore all-or-nothing; attribute sets are the shape
  # that merges, and are documented as such.
  #
  # `functionTo` merges to a lazy `{ __functor; __functionArgs }` set rather
  # than a lambda, which is fine: devenv calls a module with `entry args`, and a
  # functor set applies exactly as a lambda does.
  shellType = lib.types.either (lib.types.functionTo lib.types.raw) (
    lib.types.submodule {
      freeformType = lib.types.lazyAttrsOf lib.types.anything;
    }
  );
in
{
  options.substrate.devenv.shells = lib.mkOption {
    type = lib.types.attrsOf shellType;
    default = { };
    description = ''
      Named devenv shell modules to build into devShells. An entry is an
      attribute set of devenv options, or a function of devenv's module
      arguments. A function entry must be the only definition of its name;
      anything else defined for the same shell claims it and calls it with
      substrate's arguments instead of devenv's.
    '';
  };

  config.substrate.outputs.perSystem.devShells =
    let
      shells = devenvCfg.shells or { };
    in
    lib.mkIf (shells != { }) [
      {
        build = mkDevenvShells;
      }
    ];
}
