# Wrappers extension: provides a pkgs-bound `wrap` module argument (the jailLib
# pattern) for declaratively wrapping executables. No target-system options
# beyond the backend registry and default: each wrap call returns a derivation
# you install through your usual mechanism (home.packages,
# environment.systemPackages, systemd units, ...).
#
# Other extensions contribute backends via substrate.settings.wrappers.backends;
# each entry surfaces as the callable `wrap.with<Name>` and is validated by the
# same typed pipeline as the built-ins. The jail extension registers the
# `bubblewrap` backend this way — wrappers never references jail-nix.
{ lib, config, ... }:
let
  settings = config.substrate.settings;
in
{
  options.substrate.settings.wrappers = {
    backends = lib.mkOption {
      type = with lib.types; attrsOf (addCheck (attrsOf raw) (e: e ? build));
      default = { };
      description = ''
        Extension-contributed wrap backends, keyed by backend name; the entry
        at key `foo` surfaces as the callable `wrap.withFoo`.
        Each entry is an attrset:
        - options: option declarations for the backend spec (attrset of
          mkOption, full module body with options/config/imports, or module
          function). The pipeline merges the common package/passthru/assertions
          prelude automatically; wrong spec fields are module errors at eval.
        - build: build { pkgs, lib, wrapLib } cfg -> derivation. cfg is the
          validated spec. Backends that wrap a package must honor
          config.package.
        Reserved names (shell, binary, script, typed, types, toScript,
        toOuter, toStubFlags) are rejected. Entries must not merge across
        modules; a duplicate name is an error.
      '';
    };

    defaultBackend = lib.mkOption {
      type = lib.types.str;
      default = "shell";
      example = "binary";
      description = ''
        Which backend the bare `wrap { ... }` functor dispatches to, and the
        fallback for typed definitions that don't pin one. It must name a
        known backend (built-in or contributed); the named callables
        (`wrap.withShell`, `wrap.withBinary`, `wrap.withScript`,
        `wrap.with<Contributed>`) are unaffected.
      '';
    };
  };

  config.substrate.settings.extraArgsGenerators = [
    (
      { pkgs, ... }:
      {
        wrap = import ./wrap.nix {
          inherit lib pkgs;
          backends = settings.wrappers.backends;
          defaultBackend = settings.wrappers.defaultBackend;
        };
      }
    )
  ];
}
