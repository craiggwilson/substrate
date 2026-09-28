# Secrets extension: declarative SecretSpec integration for substrate.
#
# Contributes a class module for each target it supports (nixos, homeManager),
# routed by class so a manifest is only ever placed where that builder exists.
# There modules declare secretspec.{entries,providers,scopes,defaultProviders},
# which render into a per-configuration secretspec.toml manifest (declarations
# only; values stay in providers and resolve at runtime). Host modules also
# receive a pkgs-bound `secrets` helper (like jailLib) for wrapping service
# commands.
{ lib, ... }:
let
  inherit (import ./manifest.nix { inherit lib; }) paths;

  nixosContribution = _: [ ./nixos-module.nix ];

  homeManagerContribution = _: [ ./home-manager-module.nix ];

  secretsArgs =
    { hostcfg, pkgs, ... }:
    let
      # The fixed host manifest is placed by the NixOS builder, which only
      # runs for hosts that carry a system (usersOnly = false). Users of
      # home-only hosts get the shell-expandable XDG form the home-manager
      # module places.
      manifestPath =
        if hostcfg != null && !(hostcfg.usersOnly or false) then
          paths.nixosManifest
        else
          paths.homeManagerUserManifest;
      prefix =
        {
          scope,
          reason ? "runtime resolution for scope ${scope}",
        }:
        "${pkgs.secretspec}/bin/secretspec run --file ${manifestPath} --scope ${scope} --caller substrate --caller-operation run --reason ${lib.escapeShellArg reason} --";
    in
    {
      secrets = {
        inherit
          manifestPath
          prefix
          ;
        package = pkgs.secretspec;
        # Wrap a command so its environment is populated at exec time from the
        # generated manifest, restricted to one scope. The leading "@" keeps
        # the whole string usable as a systemd ExecStart on hosts; user builds
        # omit it for shell composition. To inject secrets into a wrapped
        # program via other machinery (e.g. the wrap extension), use
        # secrets.prefix and append the command yourself.
        run =
          {
            scope,
            cmd,
            reason ? "runtime resolution for scope ${scope}",
          }:
          (lib.optionalString (hostcfg != null) "@")
          + prefix {
            inherit
              scope
              reason
              ;
          }
          + " ${cmd}";
      };
    };
in
{
  config.substrate.settings = {
    contributors = [
      {
        class = "nixos";
        contribute = nixosContribution;
      }
      {
        class = "homeManager";
        contribute = homeManagerContribution;
      }
    ];
    extraArgsGenerators = [ secretsArgs ];
  };
}
