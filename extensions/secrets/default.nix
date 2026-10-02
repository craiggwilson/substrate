# Secrets extension: declarative SecretSpec integration for substrate.
#
# Contributes a class module for each target it supports (nixos, homeManager),
# routed by class so a manifest is only ever placed where that builder exists.
# These modules declare secretspec.{entries,providers,scopes,defaultProviders},
# which render into a per-configuration secretspec.toml manifest (declarations
# only; values stay in providers and resolve at runtime).
#
# When the wrappers extension is also loaded, it registers a `secret` wrap
# backend, surfacing as `wrap.withSecret { package; scope; ... }`: a standalone
# script that populates the command's environment at exec time from the
# generated manifest. Without wrappers there is no backend; class modules,
# the installed CLI, and $SECRETSPEC_FILE cover the rest.
{ lib, options, ... }:
let
  inherit (import ./manifest.nix { inherit lib; }) paths;

  nixosContribution = _: [ ./nixos-module.nix ];

  homeManagerContribution = _: [ ./home-manager-module.nix ];

  # The manifest a wrapper reads, derived from the wrap backend's build
  # context (hostcfg/usercfg, threaded through the wrap pipeline): user
  # builds read the Home Manager manifest at its shell-expandable XDG
  # location; host builds read the fixed path placed by the NixOS class
  # module. An explicit `manifest` overrides both.
  manifestFor =
    manifest: usercfg:
    if manifest != null then
      toString manifest
    else if usercfg != null then
      paths.homeManagerUserManifest
    else
      paths.nixosManifest;

  secretBackend =
    { config, ... }:
    {
      options = {
        scope = lib.mkOption {
          type = lib.types.str;
          description = "Scope resolved at exec time; must be declared in the manifest (secretspec.scopes).";
        };

        reason = lib.mkOption {
          type = lib.types.str;
          default = "runtime resolution for scope ${config.scope}";
          description = "Reason recorded by providers that support audit logging.";
        };

        manifest = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = "Path to the secretspec.toml manifest. null derives it from the build context: the Home Manager user manifest on user builds, /etc/secretspec.toml on host builds.";
        };
      };

      config.assertions = [
        {
          assertion = config.package != null;
          message = "wrap.withSecret requires { package = ...; scope = ...; }.";
        }
      ];
    };

  secretBackendBuild =
    {
      pkgs,
      lib,
      wrapLib,
      hostcfg,
      usercfg,
    }:
    cfg:
    let
      name = baseNameOf (lib.getExe cfg.package);
      fileArg = "--file \"${manifestFor cfg.manifest usercfg}\"";
      prefix = "${pkgs.secretspec}/bin/secretspec run ${fileArg} --scope ${lib.escapeShellArg cfg.scope} --caller substrate --caller-operation run --reason ${lib.escapeShellArg cfg.reason} --";
    in
    pkgs.runCommand name
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = name;
      }
      ''
        makeWrapper ${lib.getExe cfg.package} "$out/bin/.${name}-core" --inherit-argv0
        substitute ${pkgs.writeShellScript "${name}-outer" ''
          exec -a "$0" ${prefix} @out@/bin/.${name}-core "$@"
        ''} "$out/bin/${name}" --replace-fail "@out@" "$out"
        chmod +x "$out/bin/${name}"
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

    # Register the wrap.withSecret backend when the wrappers extension is
    # loaded (see extensions/wrappers). Without wrappers the option does not
    # exist and there is nothing to contribute.
    (lib.optionalAttrs ((options.substrate.settings.wrappers or { }) ? backends) {
      substrate.settings.wrappers.backends.secret = {
        options = secretBackend;
        build = secretBackendBuild;
      };
    })
  ];
}
