# NixOS class module: collects secretspec declarations from the host
# configuration, renders the secretspec manifest, and places it at a fixed
# path. No secret values are written; services resolve at runtime. Entries
# with a `file` policy are additionally materialized to runtime files by the
# secretspec-materialize service.
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

  # A systemd system unit runs with no HOME, and secretspec resolves its global
  # config (and the audit log's state directory) through the XDG base directory
  # spec before it does anything else — without these it fails every call with
  # "Unable to determine location of config directory".
  #
  # Plain roots, as the spec intends: each program appends its own name, so this
  # yields /var/lib/secretspec/{config.toml,audit.log} and /var/lib/op/config.
  xdgRoot = "/var/lib";

  hasFileEntries = builtins.any (e: e.file != null) (builtins.attrValues cfg.entries);

  # The shared render, so a wrapper in this configuration reproduces the same
  # store path this class module wrote.
  manifestDrv = manifestFile pkgs cfg;

  # Where the manifest is read from. It holds declarations only, so by default it
  # is read straight from the store: nothing to place, nothing to activate, no
  # activation ordering. secretspec.manifestPath asks for a path on disk instead
  # and moves every consumer (stub, unit, $SECRETSPEC_FILE) with it.
  # Interpolated, so the manifest stays in the closure of whatever reads it.
  manifestPath = if cfg.manifestPath == null then "${manifestDrv}" else cfg.manifestPath;

  # A user-supplied path is honored verbatim: one tmpfiles symlink, preceded by a
  # rule for its parent directory since L+ does not create one.
  placeManifest = lib.optionals (cfg.manifestPath != null) [
    "d ${builtins.dirOf cfg.manifestPath} 0755 - - -"
    "L+ ${cfg.manifestPath} - - - - ${manifestDrv}"
  ];

  # Resolve and install each materialized entry as a oneshot. Runtime only: the
  # store just holds the manifest's declarations. The providers its entries can
  # reach join the PATH, so they can shell out to their CLIs (op, sops, ...).
  materializeFiles = pkgs.writeShellApplication {
    name = "secretspec-materialize-files";
    runtimeInputs = [
      pkgs.secretspec
      pkgs.coreutils
    ]
    ++ providerPackages cfg (aliasesFor cfg null);
    text = materializerText {
      secretspec = "${pkgs.secretspec}";
      coreutils = "${pkgs.coreutils}";
      manifestPath = lib.escapeShellArg manifestPath;
    } cfg.entries;
  };

  # The conflict check rides on ExecStart so anything touching the service
  # forces it: a bad entry is an eval error, not a runtime surprise.
  materializerDrv = builtins.seq (checkConflict cfg.entries) materializeFiles;
in
{
  # Default materialized-file placement: under /var/lib, the NixOS equivalent
  # of state home; consumers override entries.<name>.file.path per file. The
  # import is pre-applied so options.nix's mutable parameters are bound here
  # rather than as module-system args.
  imports = [ (import ./options.nix { inherit lib; }) ];

  config = lib.mkMerge [
    # The project name the manifest records, so the render stays a pure function
    # of the secretspec options: a wrapper anywhere in this configuration can
    # reproduce this manifest from them, rather than being told where it is.
    {
      secretspec.project = lib.mkDefault config.networking.hostName;
    }

    (lib.mkIf (cfg.entries != { }) {
      environment.systemPackages = [ pkgs.secretspec ];

      systemd.services.secretspec-materialize = lib.mkIf (cfg.entries != { } && hasFileEntries) {
        description = "Materialize secretspec entries as runtime files";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${materializerDrv}/bin/secretspec-materialize-files";
          Environment = [
            "SECRETSPEC_FILE=${manifestPath}"
            "XDG_CONFIG_HOME=${xdgRoot}"
            "XDG_STATE_HOME=${xdgRoot}"
          ];
        };
      };

      # Root-only, and the same directory the materialized files land in: it holds
      # the audit log, which records which secret was read by which unit.
      systemd.tmpfiles.rules = [
        "d ${xdgRoot}/secretspec 0700 root root -"
      ]
      ++ placeManifest;
    })
  ];
}
