# Home Manager class module: collects substrate.secrets declarations from a
# user configuration, renders the secretspec manifest, and places it under the
# user's XDG config. No secret values are written; shells and user services
# resolve at runtime via $SECRETSPEC_FILE.
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
  cfg = config.substrate.secrets;

  manifestFile = pkgs.writeText "secretspec.toml" (render {
    project = config.home.username;
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
    home.packages = [ pkgs.secretspec ];
    xdg.configFile."${paths.homeManagerManifest}".source = manifestFile;
    # secretspec only auto-detects from the working directory, so point the
    # CLI at the generated manifest for interactive shells.
    home.sessionVariables.SECRETSPEC_FILE = "${config.xdg.configHome}/${paths.homeManagerManifest}";
    # External CLIs a provider shells out to (op, sops, age, ...) are not
    # installed here; consuming configs add them as they normally would.
  };
}
