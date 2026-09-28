# Wrappers extension: provides a `wrap` module argument (the jailLib pattern)
# for declaratively wrapping executables. No target-system options beyond the
# contributor registry: each wrap call returns a derivation you install through
# your usual mechanism (home.packages, environment.systemPackages, systemd
# units, ...).
#
# One wrapper per call, one shape: the package tree with one executable replaced
# by a stub. A spec is the core vocabulary (package, env, args, prefix, ...) flat
# at the top level, plus at most one key per contributor it names —
# `secrets.scope`, `bubblewrap.permissions`. Extensions contribute to wrapping
# via substrate.settings.wrappers.contributors; the jail and secrets extensions
# register theirs this way, and wrappers never references either.
#
# `wrap` is published by the class module (class-module.nix) rather than by an
# extraArgsGenerator, because it closes over the configuration it is built for:
# that is what lets a contributor hook read options declared beside the wrapper.
{ lib, config, ... }:
let
  settings = config.substrate.settings;
  contributors = settings.wrappers.contributors;

  # One publication per class wrappers speaks for, closing over the registry so
  # the class module does not need to reach back into substrate settings. A class
  # no builder provides is inert: contributionsFor is only called for a class
  # something else claims.
  #
  # usercfg comes from the contribution context because neither builder passes
  # it as a module argument (nixos sends `usercfg = null`; home-manager passes
  # only inputs, hostcfg, userName), and it is null for a host build anyway.
  publish = extra: ctx: [
    (import ./class-module.nix (
      {
        inherit contributors;
        usercfg = ctx.usercfg or null;
      }
      // extra
    ))
  ];
in
{
  options.substrate.settings.wrappers = {
    contributors = lib.mkOption {
      type = with lib.types; attrsOf (addCheck (attrsOf raw) (e: e ? priority));
      default = { };
      description = ''
        Extension-contributed wrapper contributors, keyed by the spec key that
        selects them: an entry at `foo` makes `wrap { foo.…; }` valid and joins
        that contributor in.

        A contributor only adds. Each entry is an attrset:
        - priority: required integer, lower meaning further from the program.
          Contributors are ordered by it in the exec chain; two selected
          contributors may not share one.
        - options: the contributor's own options (attrset of mkOption, full
          module body with options/config/imports, or module function), which
          become the submodule under its key. Wrong fields are module errors at
          eval.
        - context: optional `{ config, inputs, lib, pkgs, hostcfg,
          usercfg, wrapLib }` to anything, merged into the context that
          contributor's other hooks receive (a contributor brings its own
          libraries this way).
        - prefix: `ctx: spec -> [ string ]`, exec-chain fragments ahead of the
          program's own prefix.
        - runtimeInputs: `ctx: spec -> [ package ]`, added to PATH.
        - setup: `ctx: spec -> string`, shell run in the wrapper before the
          chain (for anything conditional a prefix cannot express).
        - program: `ctx: spec -> package -> derivation`, the package to wrap
          instead of `spec.package`, innermost contributor first.
        - envNames: `ctx: spec -> [ string ]`, environment variables this
          contributor's chain introduces. Handed to every contributor as
          `ctx.forwarded`, so one that scrubs the environment can pass them on.
        - incompatible: optional list of core fields this contributor's shape
          cannot honor. Setting one is an error, never a silent omission.

        Every hook receives the whole resolved spec, so a contributor can honor
        the core vocabulary through its own mechanism — but it should reach for
        another contributor's effect through `ctx.forwarded`, not by reading that
        contributor's options. Entries must not merge across modules.
      '';
    };
  };

  config = {
    substrate.settings.contributors = [
      # A host configuration. Contributed without mkForce: a bare NixOS config
      # has only this definition.
      {
        class = "nixos";
        contribute = publish { };
      }
      # A user configuration, which in a NixOS-embedded Home Manager setup is
      # nested inside the host's own module system. mkForce so the user-scoped
      # publication wins there; see class-module.nix for the verified reasons.
      {
        class = "homeManager";
        contribute = publish { force = true; };
      }
    ];
  };
}
