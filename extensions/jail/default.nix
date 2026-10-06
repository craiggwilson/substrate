# Jail extension: bubblewrap isolation via jail.nix.
#
# Contributes isolation to wrapping (see the wrappers extension), so isolated
# programs compose with the rest of the wrap API:
#
#   wrap {
#     package = pkgs.foo;
#     bubblewrap.permissions = c: with c; [ network gui (readonly "/var/log") ];
#   }
#
# It also exposes the raw pkgs-bound jail.nix callable as `jailLib` for uses the
# contributor does not cover — most notably `jailLib.mkOverlay` for jailing
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
            Example: `combinators: with combinators; [ base bind-nix-store-runtime-closure fake-passwd ]`
          '';
          default = null;
        };

        additionalCombinators = lib.mkOption {
          type = lib.types.nullOr (lib.types.functionTo lib.types.attrs);
          description = ''
            Function that receives builtin combinators and returns an attrset of custom combinators.
            These are exposed under jail.combinators and in jail definitions.
            Example: `builtinCombinators: with builtinCombinators; { my-permission = compose [ (readonly "/foo") ]; }`
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

        # Contribute isolation to wrapping when the wrappers extension is loaded.
        # Without wrappers the option does not exist and there is nothing to
        # contribute; jail still works through jailLib.
        (lib.optionalAttrs ((options.substrate.settings.wrappers or { }) ? contributors) {
          substrate.settings.wrappers.contributors.bubblewrap = {
            # Inside anything that needs the host to resolve something first: a
            # jail cannot reach a keychain, and secretspec cannot run inside one.
            priority = 20;
            # jail.nix, extended for this configuration's pkgs and settings.
            # Resolved from this extension's own module args, so the wrappers
            # extension never learns that jail-nix exists.
            context = ctx: {
              inherit (jailFor ctx.pkgs) combinators;
              jailLib = jailFor ctx.pkgs;
            };
            options = {
              permissions = lib.mkOption {
                type = with lib.types; nullOr (either (listOf raw) (functionTo (listOf raw)));
                default = null;
                description = ''
                  jail.nix permissions: a list of combinators, or a function
                  receiving the combinator set and returning one. Null means the
                  base permissions alone.
                '';
              };

              forwardEnv = lib.mkOption {
                type = with lib.types; listOf str;
                default = [ ];
                example = [ "XDG_SESSION_TYPE" ];
                description = ''
                  Names to pass through the jail's cleared environment with
                  `try-fwd-env`, so the wrapped program still sees a value that
                  came from outside the wrapper: a variable your own `prefix`
                  chain introduced, or one an interactive session provides that a
                  systemd unit would not.

                  Values already in the wrapper's `env` are set literally and need
                  no forwarding, and so are secrets: `secrets.scope` names what its
                  scope injects, and for a secret use that rather than naming the
                  variable here, since only the chain knows when it is resolved.
                  A name that is unset in the environment is simply absent inside
                  the jail.
                '';
              };
            };

            # The program a jail wraps is the jail itself, so everything the core
            # would have applied around the program is applied to the jail
            # instead: `env` becomes --setenv, `runtimeInputs` become PATH
            # entries with their closures bound, and `files` are bound at the
            # store paths the spec already resolved them to (so an env value
            # computed from a file still points at the right thing inside).
            #
            # jail.nix's base permissions include --clearenv, so the environment
            # the wrapper was careful to build has to be named back in. It is:
            # every variable another contributor advertised, plus anything the
            # provider CLIs and the spec itself put here. Forwarded by value, so
            # nothing about a secret reaches the bwrap command line.
            program =
              ctx: spec: inner:
              let
                combinators = ctx.combinators;
                # jail.nix takes permissions as a list or as a function of the
                # combinator set; resolving it here is what lets the translation
                # below be appended to it.
                declared =
                  let
                    permissions = spec.bubblewrap.permissions;
                  in
                  if permissions == null then
                    [ ]
                  else if lib.isFunction permissions then
                    permissions combinators
                  else
                    permissions;
                # files are already resolved to their store paths, and a store
                # path inside the jail is the same path.
                # Everything the wrapper put in the environment before the chain
                # ran: what the spec set literally, what a contributor advertised,
                # and what the caller asked to forward by name. `env` is set by
                # value (it is known at build time, and secretspec's own values
                # never appear in the spec), the rest is forwarded so nothing
                # about a resolved secret reaches the bwrap command line.
                forwardedNames = lib.unique (ctx.forwarded ++ spec.bubblewrap.forwardEnv);
                translated =
                  lib.optionals (spec.env != { }) (
                    lib.mapAttrsToList (n: v: combinators.set-env n (toString v)) spec.env
                  )
                  ++ lib.optionals (spec.runtimeInputs != [ ]) [ (combinators.add-pkg-deps spec.runtimeInputs) ]
                  ++ lib.optionals (spec.files != { }) (
                    lib.mapAttrsToList (_: path: combinators.bind-pkg path path) spec.files
                  )
                  # Names this wrapper's own env already set literally above
                  # need no forwarding.
                  ++ map combinators.try-fwd-env (builtins.filter (n: !(spec.env ? ${n})) forwardedNames);
              in
              ctx.jailLib (
                if spec.name != null then spec.name else "${lib.getName spec.package}-isolated"
              ) inner (declared ++ translated);
          };
        })
      ];
    };
in
if hasModuleArgs then (mkModule { }) args else mkModule args
