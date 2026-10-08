{ lib, config, ... }:
let
  settingsCfg = config.substrate.settings or { };
  packagesCfg = config.substrate.packages or { };

  nameFromPath = config.substrate.lib.nameFromPath;

  mkPackages =
    final:
    lib.listToAttrs (
      lib.map (path: {
        name = nameFromPath path;
        value = final.callPackage path { };
      }) ((packagesCfg.internal or [ ]) ++ (packagesCfg.publish or [ ]))
    );

  mkPublishedPackages =
    final:
    lib.listToAttrs (
      lib.map (path: {
        name = nameFromPath path;
        value = final.callPackage path { };
      }) (packagesCfg.publish or [ ])
    );

  mkPackagesDerivationsOnly = final: lib.filterAttrs (_: v: lib.isDerivation v) (mkPackages final);

  namespace = settingsCfg.packages.namespace or "custom";

  packagesOverlay = final: prev: {
    ${namespace} = (prev.${namespace} or { }) // (mkPackages final);
  };

  publishedPackagesOverlay = final: prev: {
    ${namespace} = (prev.${namespace} or { }) // (mkPublishedPackages final);
  };
in
{
  options.substrate.settings.packages.namespace = lib.mkOption {
    type = lib.types.str;
    description = "The namespace under which packages are exposed in the overlay. Example: \"hdwlinux\" results in pkgs.hdwlinux.<packageName>";
    default = "custom";
  };

  options.substrate.packages = {
    internal = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Package definition files available to substrate itself.";
    };

    publish = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      description = "Package definition files to expose in public outputs.";
    };
  };

  config.substrate =
    lib.mkIf ((packagesCfg.internal or [ ]) != [ ] || (packagesCfg.publish or [ ]) != [ ])
      {
        lib = {
          inherit mkPackages mkPackagesDerivationsOnly;
        };

        settings.overlays = [ packagesOverlay ];

        outputs = {
          global.overlays = [
            {
              build = _: {
                packages = publishedPackagesOverlay;
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
