# Secrets extension: declarative SecretSpec integration for substrate.
#
# Contributes a class module to every NixOS host (perHostContributors) and
# every Home Manager configuration (perUserContributors, consumed by the
# home-manager extension for both standalone and embedded users), where
# modules declare substrate.secrets.{entries,providers,scopes,defaultProviders}.
# Those declarations render into a per-configuration secretspec.toml manifest
# (declarations only; values stay in providers and resolve at runtime).
# Host modules also receive a pkgs-bound `secrets` helper (like jailLib) for
# wrapping service commands.
{ lib, ... }:
let
  inherit (import ./manifest.nix { inherit lib; }) paths;

  contributeToHosts = _: [ ./nixos-module.nix ];

  contributeToUsers = _: [ ./home-manager-module.nix ];

  secretsArgs =
    {
      hostcfg,
      pkgs,
      ...
    }:
    lib.optionalAttrs (hostcfg != null) {
      secrets = {
        manifestPath = paths.nixosManifest;
        package = pkgs.secretspec;
        # Wrap a command so its environment is populated at exec time from the
        # generated manifest, restricted to one scope. Intended for
        # systemd.services.<unit>.serviceConfig.ExecStart (the leading "@"
        # keeps the whole string as the executable line in systemd units).
        run =
          {
            scope,
            cmd,
            reason ? "runtime resolution for scope ${scope}",
          }:
          "@${pkgs.secretspec}/bin/secretspec run --file ${paths.nixosManifest} --scope ${scope} --caller substrate --caller-operation run --reason ${lib.escapeShellArg reason} -- ${cmd}";
      };
    };
in
{
  config.substrate.settings = {
    perHostContributors = [ contributeToHosts ];
    perUserContributors = [ contributeToUsers ];
    extraArgsGenerators = [ secretsArgs ];
  };
}
