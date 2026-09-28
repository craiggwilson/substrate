# NixOS class module: collects secretspec declarations from the host
# configuration, renders the secretspec manifest, and places it at a fixed
# path. No secret values are written; services resolve at runtime.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (import ./manifest.nix { inherit lib; })
    paths
    render
    ;
  cfg = config.secretspec;

  manifestFile = pkgs.writeText "secretspec.toml" (render {
    project = config.networking.hostName;
    inherit (cfg)
      entries
      providers
      scopes
      defaultProviders
      ;
  });
in
{
  imports = [ ./options.nix ];

  config = lib.mkIf (cfg.entries != { }) {
    environment.etc."${paths.nixosEtcKey}".source = manifestFile;
    environment.systemPackages = [ pkgs.secretspec ];
    # External CLIs a provider shells out to (op, sops, age, ...) are not
    # installed here; consuming configs add them as they normally would.
  };
}
