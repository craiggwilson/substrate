# The module the theming extension contributes into each supported class.
# It owns the selection state — options inside the target configuration, so
# the user's modules set and read them — and fans out the registries:
# build-time apply fragments for the active palette, and (when live = true)
# the runtime switcher artifacts built from every palette.
{
  lib,
  pkgs,
  class,
  themes,
  adapters,
  packagePath,
}:
{ config, ... }:
let
  inherit (lib)
    concatStringsSep
    filterAttrs
    hasAttr
    mapAttrsToList
    mkIf
    mkMerge
    mkOption
    setAttrByPath
    types
    ;

  cfg = config.theming;

  theme =
    if cfg.active == null then
      null
    else
      (themes.${cfg.active} or (builtins.throw ''
        theming.active is "${cfg.active}", which is not a registered palette (known: ${concatStringsSep ", " (builtins.attrNames themes)})
      '')
      );

  appliedAdapters = filterAttrs (_: a: a.apply ? ${class}) adapters;

  fragments = mapAttrsToList (_name: adapter: adapter.apply.${class} theme) appliedAdapters;

  live = import ./switcher.nix { inherit lib pkgs; } {
    inherit themes;
    apps = adapters;
  };

  liveArtifacts = {
    systemd.user.tmpfiles.rules = [
      "d %h/.local/theming 0755 - - - -"
      "L+ %h/.local/theming/manifest.json - - - - ${live.manifestFile}"
    ];

    systemd.user.services.theming-boot = {
      description = "Apply the active substrate theme on session startup";
      wantedBy = [ "graphical-session.target" ];
      after = [ "graphical-session-pre.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${live.package}/bin/theming switch ${cfg.active}";
      };
    };
  }
  // setAttrByPath packagePath ([ live.package ] ++ live.themePackages);
in
{
  options.theming = {
    active = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "catppuccin-mocha";
      description = ''
        Name of a palette registered in
        `substrate.settings.theming.palettes`. Setting it applies every
        registered app adapter's `${class}` fragment for that palette;
        unsetting it leaves theming entirely to other modules.
      '';
    };

    live = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Install the runtime switcher: a manifest prebuilt for every palette,
        the `theming` command (dconf settings + template symlink swaps +
        onSwitch hooks, no rebuild), a session-start service applying
        `theming.active`, and the theme packages the switcher names.
      '';
    };
  };

  # Top-level mkMerge with sibling mkIf branches: a single `mkIf` whose
  # condition reads one `theming` option while the merged definitions also
  # carry values that read a sibling (`theming.live`) recurses during
  # definition extraction.
  config = mkMerge ([
    (mkIf (cfg.active != null) (
      mkMerge (
        [
          {
            assertions = [
              {
                assertion = hasAttr cfg.active themes;
                message = ''
                  theming.active is "${cfg.active}", which is not a registered
                  palette (known: ${concatStringsSep ", " (builtins.attrNames themes)}).
                '';
              }
            ];
          }
        ]
        ++ fragments
      )
    ))
    (mkIf (cfg.active != null && cfg.live) liveArtifacts)
  ]);
}
