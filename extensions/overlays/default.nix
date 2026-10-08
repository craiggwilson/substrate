# Publishes overlays to consumers, and lets extensions and users declare
# overlays without listing them in the published set.
#
# `substrate.settings.overlays` itself is core vocabulary: builders bake it
# into every package set substrate creates. This extension owns the naming and
# publication of overlays on top of that.
{ lib, config, ... }:
let
  overlaysCfg = config.substrate.overlays or { };

  overlayType = lib.types.functionTo (lib.types.functionTo lib.types.attrs);

  # Internal first, then published, then whatever else landed in
  # settings.overlays. mkBefore keeps this ahead of user assignments so the
  # ordering does not depend on module evaluation order.
  publishedOverlays = (overlaysCfg.internal or [ ]) ++ (lib.attrValues (overlaysCfg.publish or { }));
in
{
  options.substrate.overlays = {
    internal = lib.mkOption {
      type = lib.types.listOf overlayType;
      default = [ ];
      description = "Overlays applied to the package sets substrate builds, but not published to consumers.";
    };

    publish = lib.mkOption {
      type = lib.types.attrsOf overlayType;
      default = { };
      description = ''
        Named overlays exposed to consumers under the `overlays` output. These
        are also applied to the package sets substrate builds.
      '';
    };
  };

  config.substrate.settings.overlays = lib.mkBefore publishedOverlays;

  config.substrate.outputs.global.overlays = [
    {
      build = _: (overlaysCfg.publish or { });
    }
  ];
}
