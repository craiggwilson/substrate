# Home Manager class module: collects secretspec declarations from a
# user configuration, renders the secretspec manifest, and places it under the
# user's XDG config. No secret values are written; shells and user services
# resolve at runtime via $SECRETSPEC_FILE. Entries with a `file` policy are
# additionally materialized to runtime files by a systemd user oneshot.
#
# Import parameters: lib, plus the two helpers that turn declared providers into
# the CLIs a runtime context needs on its PATH. Both are bound by the extension's
# contribution rather than read from substrate settings, so they stay between the
# extension and its own class modules.
{
  lib,
  aliasesFor ? _cfg: _scope: [ ],
  providerPackages ? _cfg: _aliases: [ ],
}:
{
  config,
  pkgs,
  ...
}:
let
  inherit (import ./manifest.nix { inherit lib; })
    checkConflict
    manifestFile
    materializerText
    ;
  cfg = config.secretspec;

  hasFileEntries = builtins.any (e: e.file != null) (builtins.attrValues cfg.entries);

  # The shared render, so a wrapper in this configuration reproduces the same
  # store path this class module wrote.
  manifestDrv = manifestFile pkgs cfg;

  # Where the manifest is read from. It holds declarations only, so by default it
  # is read straight from the store: nothing to place, nothing to activate.
  # secretspec.manifestPath asks for a path on disk instead and moves every
  # consumer ($SECRETSPEC_FILE, the unit, any wrap stub) with it. Interpolated, so
  # the manifest stays in the closure of whatever reads it.
  manifestPath = if cfg.manifestPath == null then "${manifestDrv}" else cfg.manifestPath;

  # A user-supplied path is honored verbatim: one tmpfiles symlink, preceded by a
  # rule for its parent directory since L+ does not create one.
  placeManifest = lib.optionals (cfg.manifestPath != null) [
    "d ${builtins.dirOf cfg.manifestPath} 0755 - - -"
    "L+ ${cfg.manifestPath} - - - - ${manifestDrv}"
  ];

  # Same oneshot as the NixOS class, but in the user manager: runtime only,
  # restartable, ordered-after by consumers. The providers its entries can reach
  # join the PATH, so they can shell out to their CLIs (op, sops, ...).
  materializeFiles = pkgs.writeShellApplication {
    name = "secretspec-materialize-files";
    runtimeInputs = [
      pkgs.secretspec
      pkgs.coreutils
    ]
    ++ providerPackages cfg (aliasesFor cfg null);
    # The user manager has no network-online target; consumers order after
    # this unit so resolution precedes their reads.
    text = materializerText {
      secretspec = "${pkgs.secretspec}";
      coreutils = "${pkgs.coreutils}";
      manifestPath = lib.escapeShellArg manifestPath;
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

  config = lib.mkMerge [
    # The project name the manifest records, so the render stays a pure function
    # of the secretspec options: a wrapper anywhere in this configuration can
    # reproduce this manifest from them, rather than being told where it is.
    {
      secretspec.project = lib.mkDefault config.home.username;
    }

    (lib.mkIf (cfg.entries != { }) {
      home.packages = [ pkgs.secretspec ];
      # secretspec only auto-detects from the working directory, so point the
      # CLI at the generated manifest for interactive shells.
      home.sessionVariables.SECRETSPEC_FILE = manifestPath;

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
          Environment = [ "SECRETSPEC_FILE=${manifestPath}" ];
        };
      };

      systemd.user.tmpfiles.rules = placeManifest;
    })
  ];
}
