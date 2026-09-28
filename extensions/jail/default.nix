# Jail extension: bubblewrap isolation via jail.nix.
#
# Registers a `wrap.withBubblewrap` backend (see the wrappers extension) so isolated
# programs compose with the rest of the wrap API:
#
#   wrap.withBubblewrap {
#     package = pkgs.foo;
#     permissions = c: with c; [ network gui (readonly "/var/log") ];
#   }
#
# It also exposes the raw pkgs-bound jail.nix callable as `jailLib` for uses
# the backend does not cover — most notably `jailLib.mkOverlay` for jailing
# whole package sets. The `jail-nix` input resolves via the usual precedence:
# an explicit `jail-nix` arg, `substrate.settings.inputs."jail-nix"`, or a
# flake input named `jail-nix`.
args:
let
  hasModuleArgs = args ? lib && args ? config;

  mkModule =
    {
      jail-nix ? null,
    }:
    {
      lib,
      config,
      options,
      inputs,
      ...
    }:
    let
      cfg = config.substrate.settings.jail;

      jailInput =
        if jail-nix != null then jail-nix else config.substrate.lib.resolveInput "jail-nix" inputs;

      # jail.nix wants its config via lib.extend as an attrset whose only
      # required key is pkgs; basePermissions/additionalCombinators are
      # optional overrides.
      jailFor =
        pkgs:
        jailInput.lib.extend (
          {
            inherit pkgs;
          }
          // lib.optionalAttrs (cfg.basePermissions != null) {
            inherit (cfg) basePermissions;
          }
          // lib.optionalAttrs (cfg.additionalCombinators != null) {
            inherit (cfg) additionalCombinators;
          }
        );
    in
    {
      options.substrate.settings.jail = {
        basePermissions = lib.mkOption {
          type = lib.types.nullOr (lib.types.functionTo (lib.types.listOf lib.types.anything));
          description = ''
            Function that receives combinators and returns a list of base permissions.
            All jails inherit these permissions by default.
            Example: combinators: with combinators; [ base bind-nix-store-runtime-closure fake-passwd ]
          '';
          default = null;
        };

        additionalCombinators = lib.mkOption {
          type = lib.types.nullOr (lib.types.functionTo lib.types.attrs);
          description = ''
            Function that receives builtin combinators and returns an attrset of custom combinators.
            These are exposed under jail.combinators and in jail definitions.
            Example: builtinCombinators: with builtinCombinators; { my-permission = compose [ (readonly "/foo") ]; }
          '';
          default = null;
        };
      };

      config = lib.mkMerge [
        # Raw jail.nix callable, for mkOverlay and anything the backend omits.
        {
          substrate.settings.extraArgsGenerators = [
            (
              { pkgs, ... }:
              {
                jailLib = jailFor pkgs;
              }
            )
          ];
        }

        # Register the wrap.withBubblewrap backend when the wrappers extension is
        # loaded. Without wrappers the option does not exist and there is
        # nothing to contribute; jail still works through jailLib.
        (lib.optionalAttrs ((options.substrate.settings.wrappers or { }) ? backends) {
          substrate.settings.wrappers.backends.bubblewrap = {
            options =
              { config, ... }:
              {
                options = {
                  permissions = lib.mkOption {
                    type = lib.types.raw;
                    default = null;
                    description = "jail.nix combinators: a list, a function receiving them, or null (base permissions only).";
                  };
                  name = lib.mkOption {
                    type = with lib.types; nullOr str;
                    default = null;
                    description = "Jail/wrapper name (default: <package>-isolated).";
                  };
                };
                config.assertions = [
                  {
                    assertion = config.package != null;
                    message = "wrap.withBubblewrap requires { package = ... }.";
                  }
                ];
              };
            build =
              { pkgs, ... }:
              cfg:
              let
                jail = jailFor pkgs;
              in
              jail (
                if cfg.name != null then cfg.name else "${lib.getName cfg.package}-isolated"
              ) cfg.package cfg.permissions;
            # cfg.permissions passes through as function, list, or null (all valid for jail.nix)
          };
        })
      ];
    };
in
if hasModuleArgs then (mkModule { }) args else mkModule args
