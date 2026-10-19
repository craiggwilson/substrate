{
  lib,
  config,
  inputs,
  ...
}:
let
  settingsCfg = config.substrate.settings or { };
  packagesCfg = config.substrate.packages or { };
  publishCfg = config.substrate.publish.packages or { };

  entryType = lib.types.either (lib.types.functionTo lib.types.raw) lib.types.path;

  # Every entry is a function of the context a package definition needs, or a
  # path to one. It cannot be a bare derivation because the substrate
  # configuration is evaluated before any package set exists: settings.overlays
  # produces the package sets, so an entry cannot close over `pkgs` on its own.
  # Write function entries as `{ pkgs, ... }: ...` so they tolerate additions to
  # that set.
  entryArgs = final: {
    inherit (config) substrate;
    inherit lib inputs;
    pkgs = final;
  };

  # A path entry is callPackage'd, which is what a package file has always been.
  # A function entry receives the context and decides for itself.
  runEntry =
    entry: context: if lib.isFunction entry then entry context else context.pkgs.callPackage entry { };

  mkPackages =
    final:
    lib.mapAttrs (_: entry: runEntry entry (entryArgs final)) (
      (packagesCfg.internal or { }) // publishCfg
    );

  mkPublishedPackages = final: lib.mapAttrs (_: entry: runEntry entry (entryArgs final)) publishCfg;

  mkPackagesDerivationsOnly = final: lib.filterAttrs (_: v: lib.isDerivation v) (mkPackages final);

  mkPublishedPackagesDerivationsOnly =
    final: lib.filterAttrs (_: v: lib.isDerivation v) (mkPublishedPackages final);

  namespace = settingsCfg.packages.namespace or "custom";

  packagesOverlay = final: prev: {
    ${namespace} = (prev.${namespace} or { }) // (mkPackages final);
  };

  publishedPackagesOverlay = final: prev: {
    ${namespace} = (prev.${namespace} or { }) // (mkPublishedPackages final);
  };

  hasEntries = (packagesCfg.internal or { }) != { } || publishCfg != { };

  # The overlay output is keyed off the published set alone. An internal-only
  # configuration has nothing to publish, and emitting an empty overlay would
  # advertise a namespace that never gets filled.
  hasPublishedEntries = publishCfg != { };
in
{
  options.substrate.settings.packages.namespace = lib.mkOption {
    type = lib.types.str;
    description = "The namespace under which packages are exposed in the overlay. Example: \"hdwlinux\" results in pkgs.hdwlinux.<packageName>";
    default = "custom";
  };

  # Entries are named by their attribute key, so a package is called what you
  # wrote rather than what its file was called.
  options.substrate.packages = {
    internal = lib.mkOption {
      type = lib.types.attrsOf entryType;
      default = { };
      description = ''
        Packages substrate itself can use, as a name-to-entry attribute set.
        An entry is either a path to a package definition, which is
        callPackage'd, or a function of { pkgs, lib, inputs, substrate }, where
        pkgs is the package set being built. Not exposed under any output name.
      '';
    };
  };

  options.substrate.publish.packages = lib.mkOption {
    type = lib.types.attrsOf entryType;
    default = { };
    description = ''
      Packages exposed to consumers under the `packages` output, as a
      name-to-entry attribute set. An entry is either a path to a package
      definition, which is callPackage'd, or a function of
      { pkgs, lib, inputs, substrate }. These also land in the package sets
      substrate builds, under the configured namespace, and in the `overlays`
      output as the `packages` overlay.
    '';
  };

  # The library functions are published unconditionally on purpose. Any guard that
  # reads `substrate.packages` to decide whether to define them — including one
  # wrapped around this whole attrset — makes reading `substrate.lib` depend on
  # `substrate.packages`, which is circular for the natural way to populate the
  # entries:
  #   config.substrate.publish.packages = config.substrate.lib.definitionsIn ./pkgs;
  # That reads one while defining the other. So the guard goes on the nested
  # definitions only, where nothing reads them back.
  config.substrate = {
    lib = {
      inherit mkPackages mkPackagesDerivationsOnly;
    };

    settings.overlays = lib.mkIf hasEntries [ packagesOverlay ];

    settings.publishers.packages = {
      scope = "perSystem";
      output = "packages";
      build = { pkgs, ... }: mkPublishedPackagesDerivationsOnly pkgs;
    };

    # The published set reaches two outputs in two scopes, and a publish key is
    # one namespace reaching one output. The `packages` output is registered
    # above; this overlay is the other half, so it stays a direct builder.
    outputs.global.overlays = lib.mkIf hasPublishedEntries [
      {
        build = _: {
          packages = publishedPackagesOverlay;
        };
      }
    ];
  };
}
