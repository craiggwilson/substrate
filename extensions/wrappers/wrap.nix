# The wrap pipeline: evaluate a spec against a backend's typed option
# interface, build, and finalize passthru. One language for the built-in
# backends (shell/script/binary, in builtins.nix) and every contributed
# backend — they all live in the same registry and are validated by the same
# private evalModules call, so wrong fields are module errors, never silent.
#
# Registry keys are nouns (used by settings.wrappers.defaultBackend and
# contributed entries); each key surfaces as the callable `wrap.with<Key>`.
#
# Usage (as the `wrap` module argument, see default.nix):
#
#   wrap { package; env; args; ... }           # the configured default backend
#                                              # (settings.wrappers.defaultBackend,
#                                              #  normally the shell backend)
#   wrap.withShell { package; ... }            # in-place makeWrapper shell stub
#   wrap.withBinary { package; ... }           # in-place compiled stub
#   wrap.withScript { cmd; name; prefix; ... } # standalone script package
#   wrap.withBubblewrap { ... }                # contributed (jail extension)
#   wrap.typed def settings -> drv             # typed, reusable definition
{
  lib,
  pkgs,
  backends ? { },
  defaultBackend ? "shell",
  # The build context the `wrap` argument was generated for (see
  # extensions/wrappers/default.nix): hostcfg/usercfg flow to backend build
  # calls so context-sensitive backends can adapt (e.g. the secrets backends's
  # manifest path). null usercfg = a host build.
  hostcfg ? null,
  usercfg ? null,
}:
let
  common = import ./common.nix { inherit lib pkgs; };
  builtin = import ./builtins.nix { inherit lib pkgs common; };

  builtinNames = builtins.attrNames builtin.backends;

  registry = builtin.backends // backends;

  reservedNames = [
    "binary"
    "script"
    "shell"
    "toOuter"
    "toScript"
    "toStubFlags"
    "typed"
    "types"
  ];

  backendClash = builtins.filter (n: builtins.elem n reservedNames) (builtins.attrNames backends);

  # A backend's `options` is an attrset of mkOption declarations, a full
  # module body (imports/options/config), or a module function.
  toModule =
    opts:
    if lib.isFunction opts then
      opts
    else if
      builtins.any (k: builtins.hasAttr k opts) [
        "options"
        "config"
        "imports"
      ]
    then
      opts
    else
      { options = opts; };

  # Evaluate a backend's interface against a spec, enforce its assertions,
  # build, then attach the core-owned passthru (wrapped/override/files).
  # `rerun` rebuilds from the same spec with fields overridden.
  buildWith =
    name: spec:
    let
      b =
        registry.${name}
          or (throw "substrate(wrappers): unknown backend '${name}'. Available: ${lib.concatStringsSep ", " (builtins.attrNames registry)}.");
      cfg = common.checkAssertions (
        (lib.evalModules {
          class = "wrap-${name}";
          modules = [
            common.commonModule
            (toModule (b.options or { }))
            spec
          ];
          specialArgs = { inherit pkgs lib; };
        }).config
      );
      drv = b.build {
        inherit
          pkgs
          lib
          hostcfg
          usercfg
          ;
        wrapLib = common;
      } cfg;
      rerun = overrides: buildWith name (spec // overrides);
    in
    common.finalize {
      inherit
        cfg
        drv
        rerun
        ;
    };

  # settings may be a plain attrset (including one lifted from a submodule
  # option value, hence dropping _module) or a module function.
  knobsCfg =
    def: settings:
    (lib.evalModules {
      class = "wrap-knobs";
      modules = [
        (toModule def.options)
        (if lib.isFunction settings then settings else builtins.removeAttrs settings [ "_module" ])
      ];
      specialArgs = { inherit pkgs lib; };
    }).config;

  withName =
    key:
    "with"
    + lib.strings.toUpper (lib.strings.substring 0 1 key)
    + lib.strings.substring 1 (builtins.stringLength key) key;

  contributedCallables = lib.mapAttrs' (
    n: _: lib.nameValuePair (withName n) (spec: buildWith n spec)
  ) (lib.filterAttrs (n: _: !(builtins.elem n builtinNames)) registry);
in
builtins.seq
  (
    if backendClash == [ ] then
      true
    else
      throw "substrate(wrappers): settings.wrappers.backends may not override reserved name(s) ${toString backendClash}."
  )
  (
    builtins.seq
      (
        if builtins.hasAttr defaultBackend registry then
          true
        else
          throw "substrate(wrappers): settings.wrappers.defaultBackend = '${defaultBackend}' names no known backend. Available: ${lib.concatStringsSep ", " (builtins.attrNames registry)}."
      )
      {
        # The functor dispatches to the configured default backend; named
        # callables are unaffected by it.
        __functor = self: spec: buildWith defaultBackend spec;
        inherit (builtin) toScript toOuter toStubFlags;

        withShell = spec: buildWith "shell" spec;
        withBinary = spec: buildWith "binary" spec;
        withScript = spec: buildWith "script" spec;

        # Reusable typed wrapper definitions. `wrap.typed def` returns a callable
        # (settings -> wrapped derivation) plus `.options` for embedding the
        # declarations into a real nixpkgs module via types.submodule. A
        # definition without a pinned `backend` follows defaultBackend too.
        typed = def: {
          __functor =
            self: settings: buildWith (def.backend or defaultBackend) (def.spec (knobsCfg def settings));
          # Normalized to a module body so `lib.types.submodule foo.options` works.
          options = toModule def.options;
        };

        # Option types shared with backend authors.
        types = {
          file = common.fileType pkgs;
        };
      }
    // contributedCallables
  )
