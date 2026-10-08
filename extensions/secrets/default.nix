# Secrets extension: declarative SecretSpec integration for substrate.
#
# Contributes a class module for each target it supports (nixos, homeManager),
# routed by class so a manifest is only ever placed where that builder exists.
# These modules declare secretspec.{project,entries,providers,scopes,...}, which
# render into a per-configuration secretspec.toml manifest (declarations only;
# values stay in providers and resolve at runtime).
#
# When the wrappers extension is also loaded, secrets joins in as a wrapper
# contributor: `wrap { package; secrets.scope; ... }` puts secretspec's
# invocation in the wrapper's exec chain, so the command's environment is
# populated at exec time from the generated manifest. Without wrappers there is
# nothing to contribute; class modules, the installed CLI, and $SECRETSPEC_FILE
# cover the rest.
#
# A provider names the CLI it shells out to beside its URI
# (`secretspec.providers.<alias>.package`), and those CLIs reach the PATH of the
# two runtime contexts this extension builds itself — the materialization units
# and the wrap stubs — and nothing else: session PATHs stay yours (add the
# packages to home.packages or environment.systemPackages).
{
  lib,
  options,
  ...
}:
let
  manifestLib = import ./manifest.nix { inherit lib; };
  inherit (manifestLib) manifestFile;

  # The CLI a provider needs, declared beside the provider that needs it:
  # `secretspec.providers.<alias>.package`. Being a package, it comes from the
  # configuration's own package set, so it honors that host's nixpkgsConfig.
  #
  # Which providers a consumer needs is decided by what it can reach: a scope's
  # entries, or every declared entry for a materialization unit. An entry naming
  # no providers falls back to the configuration's default chain. Only those CLIs
  # go on its PATH, so a wrapper touching one service's secrets does not carry
  # another's tooling.
  providerPackages =
    cfg: aliases:
    let
      declared = lib.filter (a: cfg.providers ? ${a}) aliases;
      withPackage = lib.filter (a: cfg.providers.${a}.package != null) declared;
    in
    lib.map (a: cfg.providers.${a}.package) withPackage;

  aliasesFor =
    cfg: scope:
    let
      names =
        if scope != null && cfg.scopes ? ${scope} then
          cfg.scopes.${scope}.secrets
        else
          builtins.attrNames cfg.entries;
      ofEntry =
        n:
        let
          e = cfg.entries.${n} or { };
        in
        if (e.providers or [ ]) == [ ] then cfg.defaultProviders else e.providers;
    in
    lib.unique (lib.concatMap ofEntry names);

  nixosContribution = _: [
    (import ./nixos-module.nix { inherit lib aliasesFor providerPackages; })
  ];

  homeManagerContribution = _: [
    (import ./home-manager-module.nix { inherit lib aliasesFor providerPackages; })
  ];

  # A secret wrapper is an exec chain: secretspec resolves the scope, then the
  # wrapped command runs with the resolved values in its environment. As a
  # contributor it contributes exactly that — the invocation as a chain prefix,
  # the provider CLIs on PATH, and an XDG fallback for callers with no HOME —
  # and nothing else; the core renders the wrapper.
  #
  # The invocation goes outside anything else in the chain: secretspec needs the
  # provider CLIs, the keychain and the network, and its `--scope` both injects
  # the scope's values and strips every other secret from the child environment.
  #
  # The manifest comes from the configuration the wrapper is built for
  # (ctx.config), rendered from the same secretspec options the class module
  # rendered it from — so a wrapper names only its scope, and the path is the
  # store file that configuration already produced. `manifest` overrides it for
  # a wrapper that must read somewhere else.
  secretOptions =
    {
      config,
      ...
    }:
    {
      options = {
        scope = lib.mkOption {
          type = lib.types.str;
          description = "Scope resolved at exec time; must be declared in `secretspec.scopes`.";
        };

        reason = lib.mkOption {
          type = lib.types.str;
          default = "runtime resolution for scope ${config.scope}";
          description = "Audit-reason string; defaults to \"runtime resolution for scope <scope>\".";
        };

        manifest = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "/etc/secretspec.toml";
          description = ''
            Read the manifest from here instead of the one this configuration
            wrote. Null (the default) renders it from `config.secretspec` — the
            same options the class module renders from, producing the same store
            path — so a spec never has to name a path. Set it for a wrapper that
            must read a manifest placed on disk (`secretspec.manifestPath`) or
            one written by a different configuration.
          '';
        };
      };
    };

  # The manifest this wrapper's configuration writes, from its secretspec
  # options. `project` must be set or the render throws, so a class module that
  # forgot its default fails here rather than producing a manifest nobody can
  # address.
  manifestFor =
    ctx: spec:
    if spec.secrets.manifest != null then
      spec.secrets.manifest
    else if !(ctx.config ? secretspec) then
      throw "substrate(secrets): wrap { secrets.scope = ...; } needs a configuration that declares secretspec. Load the secrets extension's class module for this class, or name the manifest explicitly with secrets.manifest."
    else if ctx.config.secretspec.project == null then
      throw "substrate(secrets): secretspec.project is unset, so the manifest cannot be rendered. It defaults to the class module's identity (hostname or username); set it explicitly if this configuration should use another."
    else
      "${manifestFile ctx.pkgs ctx.config.secretspec}";

  # secretspec resolves an XDG config directory before it reads anything, and
  # fails every call with "Unable to determine location of config directory"
  # without one; a systemd unit has no HOME to derive it from. So a wrapper a
  # unit runs supplies one — but only when the caller has neither HOME nor
  # XDG_CONFIG_HOME, so an interactive session keeps its own.
  #
  # Plain XDG roots, as the spec intends: secretspec and the provider CLIs each
  # append their own name, giving /var/lib/secretspec/{config.toml, audit.log} and
  # /var/lib/op/config.
  #
  # Host builds only (usercfg == null, the same signal manifestFor uses). A user
  # build runs with a HOME; if one ever does not, failing with secretspec's own
  # error beats relocating a CLI's state to a guessed path.
  xdgSetup = ''
    # Secretspec needs an XDG config directory; see the secrets extension for when
    # this fires and why it is host builds only.
    if [[ -z "''${HOME:-}" && -z "''${XDG_CONFIG_HOME:-}" ]]; then
      export XDG_CONFIG_HOME="/var/lib"
      export XDG_STATE_HOME="/var/lib"
    fi
  '';

in
{
  config = lib.mkMerge [
    {
      substrate.settings.contributors = [
        {
          class = "nixos";
          contribute = nixosContribution;
        }
        {
          class = "homeManager";
          contribute = homeManagerContribution;
        }
      ];
    }

    # Contribute secrets to wrapping when the wrappers extension is loaded (see
    # extensions/wrappers). Without wrappers the option does not exist and there
    # is nothing to contribute.
    (lib.optionalAttrs ((options.substrate.settings.wrappers or { }) ? contributors) {
      substrate.settings.wrappers.contributors.secrets = {
        # Outside a jail, inside a launcher: secretspec needs the provider CLIs,
        # the keychain and the network to resolve anything at all.
        priority = 10;
        options = secretOptions;
        prefix =
          ctx: spec:
          let
            manifest = manifestFor ctx spec;
            inherit (spec.secrets) scope;
            # Checked here rather than left to secretspec: an undeclared scope
            # would otherwise fail at exec time, in whatever context runs the
            # wrapper, with no mention of where it should have been declared.
            declared = ctx.config ? secretspec && ctx.config.secretspec.scopes ? ${scope};
          in
          [
            (
              if !declared && spec.secrets.manifest == null then
                throw "substrate(secrets): scope '${scope}' is not declared in this configuration. Declare it as secretspec.scopes.${scope}.secrets."
              else
                "${ctx.pkgs.secretspec}/bin/secretspec run --file ${lib.escapeShellArg manifest} --scope ${lib.escapeShellArg scope} --caller substrate --caller-operation run --reason ${lib.escapeShellArg spec.secrets.reason} --"
            )
          ];
        # Only the providers this scope can reach, so one service's secrets do
        # not drag another's CLI onto the wrapper's PATH.
        runtimeInputs =
          ctx: spec:
          if ctx.config ? secretspec then
            providerPackages ctx.config.secretspec (aliasesFor ctx.config.secretspec spec.secrets.scope)
          else
            [ ];
        # Host builds only: a systemd unit has no HOME.
        setup = ctx: _spec: if ctx.usercfg == null then xdgSetup else "";
      };
    })
  ];
}
