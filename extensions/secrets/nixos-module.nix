# NixOS class module: collects secretspec declarations from the host
# configuration, renders the secretspec manifest, and places it at a fixed
# path. No secret values are written; services resolve at runtime. Entries
# with a `file` policy are additionally materialized to runtime files by the
# secretspec-materialize service.
#
# Import parameters: lib, plus providerPackages — a function of this
# configuration's pkgs returning the CLIs providers shell out to — both bound by
# the extension's contribution from
# substrate.settings.secrets.providerPackages. Pre-applying them here rather
# than as module-system args matches how options.nix's per-class defaults are
# bound, and keeps the module evaluable on its own.
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

  # A systemd system unit runs with no HOME, and secretspec resolves its global
  # config (and the audit log's state directory) through the XDG base directory
  # spec before it does anything else — without these it fails every call with
  # "Unable to determine location of config directory".
  #
  # Plain roots, as the spec intends: each program appends its own name, so this
  # yields /var/lib/secretspec/{config.toml,audit.log} and /var/lib/op/config.
  xdgRoot = "/var/lib";

  hasFileEntries = builtins.any (e: e.file != null) (builtins.attrValues cfg.entries);

  manifestFile = pkgs.writeText "secretspec.toml" (render {
    project = config.networking.hostName;
    inherit (cfg)
      entries
      providers
      scopes
      defaultProviders
      ;
  });

  # Resolve and install each materialized entry as a oneshot. Runtime only:
  # the store just holds the manifest's declarations. providerPackages joins the
  # PATH so providers can shell out to their CLIs (op, sops, ...).
  materializeFiles = pkgs.writeShellApplication {
    name = "secretspec-materialize-files";
    runtimeInputs = [
      pkgs.secretspec
      pkgs.coreutils
    ]
    ++ providerPackages pkgs;
    text = materializerText {
      secretspec = "${pkgs.secretspec}";
      coreutils = "${pkgs.coreutils}";
      manifestPath = paths.nixosManifest;
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

  config = lib.mkIf (cfg.entries != { }) {
    environment.etc."${paths.nixosEtcKey}".source = manifestFile;
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
          "SECRETSPEC_FILE=${paths.nixosManifest}"
          "XDG_CONFIG_HOME=${xdgRoot}"
          "XDG_STATE_HOME=${xdgRoot}"
        ];
      };
    };

    # Root-only, and the same directory the materialized files land in: it holds
    # the audit log, which records which secret was read by which unit.
    systemd.tmpfiles.rules = [ "d ${xdgRoot}/secretspec 0700 root root -" ];
  };
}
