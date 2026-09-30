# The module the theming extension contributes into each supported class.
# It owns the selection state — options inside the target configuration, so
# the user's modules set and read them — fans out the registries, and applies
# the built-in surface adapters (surfaces.nix) alongside any user-registered
# app adapters: every fragment is `theme -> option assignments`, called with
# the target's package set. `theming.palette` exposes the resolved active
# palette (color library, wallpaper, dark flag, package fields) to coupled app
# fragments that must mix theme data with target config.
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

  # The extension's built-in surface adapters, replaced outright by any user
  # adapter registered under the same name, then ordered so user adapter
  # fragments merge after the surfaces (later wins at equal priority).
  builtInSurfaces = import ./surfaces.nix { inherit lib; };

  surfaceAdapters = filterAttrs (
    name: a: !(adapters ? ${name}) && a.apply ? ${class}
  ) builtInSurfaces;

  appAdapters = filterAttrs (_: a: a.apply ? ${class}) adapters;

  adapterArgs = {
    inherit
      theme
      pkgs
      ;
  };

  fragments =
    mapAttrsToList (_: a: a.apply.${class} adapterArgs) surfaceAdapters
    ++ mapAttrsToList (_: a: a.apply.${class} adapterArgs) appAdapters;

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
        adapter's `${class}` fragment — the built-in surfaces (GTK/cursor/Qt
        on Home Manager, console/Plymouth on NixOS) plus any user-registered
        app adapters; unsetting it leaves theming entirely to other modules.
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

    palette = mkOption {
      type = types.raw;
      default = null;
      description = ''
        The resolved active palette (color library under `.colors`, plus
        `wallpaper`, `dark`, and the theme package fields), or null when no
        theme is active. Read it from coupled app fragments that must mix
        theme data with target config; pure color mappings belong in a
        `settings.theming.apps.<name>.apply` adapter instead.
      '';
    };
  };

  # Top-level mkMerge with sibling branches. A single `mkIf` whose condition
  # reads one `theming` option while the merged definitions also carry values
  # that read a sibling (`theming.live`) recurses during definition
  # extraction. Adapter fragments may only be forced at discharge (their keys
  # are computed from `theme`, which reads config), which the `mkIf` wrapper
  # guarantees — the collector treats it as opaque.
  config = mkMerge [
    (mkIf (cfg.active != null) {
      assertions = [
        {
          assertion = hasAttr cfg.active themes;
          message = ''
            theming.active is "${cfg.active}", which is not a registered
            palette (known: ${concatStringsSep ", " (builtins.attrNames themes)}).
          '';
        }
      ];
      theming.palette = theme;
    })
    (mkIf (cfg.active != null) (mkMerge fragments))
    (mkIf (cfg.active != null && cfg.live) liveArtifacts)
  ];
}
