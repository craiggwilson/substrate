{ lib, config, ... }:
let
  settings = config.substrate.settings;

  nameFromPath =
    path:
    let
      basename = baseNameOf path;
    in
    lib.removeSuffix ".nix" basename;

  mkPackages =
    final:
    lib.listToAttrs (
      lib.map (path: {
        name = nameFromPath path;
        value = final.callPackage path { };
      }) settings.publish.packages
    );

  mkPackagesDerivationsOnly = final: lib.filterAttrs (_: v: lib.isDerivation v) (mkPackages final);

  namespace = settings.packageNamespace;

  packagesOverlay = final: prev: {
    ${namespace} = (prev.${namespace} or { }) // (mkPackages final);
  };
in
{
  options.substrate = {
    settings = {
      packageNamespace = lib.mkOption {
        type = lib.types.str;
        description = "The namespace under which packages are exposed in the overlay. Example: \"hdwlinux\" results in pkgs.hdwlinux.<packageName>";
        default = "custom";
      };

      publish.packages = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "Paths to package files to publish as packages and overlay flake outputs.";
      };
    };

    packages = lib.mkOption {
      type = lib.types.lazyAttrsOf (lib.types.attrsOf lib.types.package);
      description = "The packages defined in settings.publish.packages, keyed by system.";
      default = { };
    };
  };

  config.substrate = lib.mkIf (settings.publish.packages != [ ]) {
    lib = {
      inherit mkPackages mkPackagesDerivationsOnly;
    };

    settings.overlays = [ packagesOverlay ];

    outputs = {
      global.overlays = [
        {
          build =
            { ... }:
            {
              packages = packagesOverlay;
            };
        }
      ];

      perSystem.packages = [
        {
          build = { pkgs, ... }: mkPackagesDerivationsOnly pkgs;
        }
      ];
    };
  };
}
