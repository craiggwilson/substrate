# Home Manager class module: collects secretspec declarations from a
# user configuration, renders the secretspec manifest, and places it under the
# user's XDG config. No secret values are written; shells and user services
# resolve at runtime via $SECRETSPEC_FILE. Entries with a `file` policy are
# additionally materialized to runtime files by a systemd user oneshot.
#
# Import parameters: lib, plus providerPackages — a function of this
# configuration's pkgs returning the CLIs providers shell out to — both bound by
# the extension's contribution from
# substrate.settings.secrets.providerPackages.
{
  lib,
  providerPackages ? _pkgs: [ ],
}:
{ config, pkgs, ... }:
let
  inherit (import ./manifest.nix { inherit lib; })
    checkConflict
    materializerText
    paths
    render
    ;
  cfg = config.secretspec;

  hasFileEntries = builtins.any (e: e.file != null) (builtins.attrValues cfg.entries);

  manifestFile = pkgs.writeText "secretspec.toml" (render {
    project = config.home.username;
    inherit (cfg)
      entries
      providers
      scopes
      defaultProviders
      ;
  });

  # Same oneshot as the NixOS class, but in the user manager: runtime only,
  # restartable, ordered-after by consumers. providerPackages joins the PATH so
  # providers can shell out to their CLIs (op, sops, ...).
  materializeFiles = pkgs.writeShellApplication {
    name = "secretspec-materialize-files";
    runtimeInputs = [
      pkgs.secretspec
      pkgs.coreutils
    ]
    ++ providerPackages pkgs;
    # The user manager has no network-online target; consumers order after
    # this unit so resolution precedes their reads.
    text = materializerText {
      secretspec = "${pkgs.secretspec}";
      coreutils = "${pkgs.coreutils}";
      manifestPath = ''"${paths.homeManagerUserManifest}"'';
    } cfg.entries;
  };

  # The conflict check rides on ExecStart so anything touching the unit
  # forces it: a bad entry is an eval error, not a session surprise.
  materializerDrv = builtins.seq (checkConflict cfg.entries) materializeFiles;
in
{
  # Default materialized-file placement lives under state home
  # (~/.local/state), the XDG home for per-host state like credentials;
  # consumers override entries.<name>.file.path per file. The import is
  # pre-applied so options.nix's mutable parameters are bound here rather
  # than as module-system args.
  imports = [
    (import ./options.nix {
      inherit lib;
      filesDir = "${config.home.homeDirectory}/.local/state/secretspec/files";
      owner = config.home.username;
      group = "users";
    })
  ];

  config = lib.mkIf (cfg.entries != { }) {
    home.packages = [ pkgs.secretspec ];
    xdg.configFile."${paths.homeManagerManifest}".source = manifestFile;
    # secretspec only auto-detects from the working directory, so point the
    # CLI at the generated manifest for interactive shells.
    home.sessionVariables.SECRETSPEC_FILE = "${config.xdg.configHome}/${paths.homeManagerManifest}";

    # Restart the materializer when entries change: daemon-reload/start-services
    # at activation triggers restarts for changed units, keeping files fresh
    # per generation without waiting for the next login.
    systemd.user.startServices = lib.mkDefault "sdSwitch";

    systemd.user.services.secretspec-materialize = lib.mkIf (cfg.entries != { } && hasFileEntries) {
      Unit.description = "Materialize secretspec entries as runtime files";
      Install.WantedBy = [ "default.target" ];
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${materializerDrv}/bin/secretspec-materialize-files";
        Environment = [ "SECRETSPEC_FILE=${config.xdg.configHome}/${paths.homeManagerManifest}" ];
      };
    };
  };
}
