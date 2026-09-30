# The module the theming extension contributes into each supported class.
# It owns the selection state — options inside the target configuration, so
# the user's modules set and read them — fans out the registries, and applies
# the generic theme surfaces the active palette describes (GTK theme/icon/CSS,
# pointer cursor, Qt/Kvantum on Home Manager; console palette and Plymouth on
# NixOS) using the target config's own option vocabulary. `theming.palette`
# exposes the resolved active palette (color library, wallpaper, dark flag,
# ...) for coupled app fragments that must mix theme data with target config;
# pure color mappings still belong in `settings.theming.apps.*.apply`.
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
    optionalAttrs
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

  fragments = mapAttrsToList (_name: a: a.apply.${class} theme) appliedAdapters;

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

  adwaitaCss = import ./adwaita.nix;

  # --- generic surfaces, driven by the active palette's fields ---
  #
  # The option KEYS must be statically known: the module system walks a
  # module's config structure during collection, before any option is
  # readable. So per-class key sets are fixed (branching on `class`, a
  # function argument, never on config) and every palette reference lives in
  # an `mkIf` condition or a value thunk, discharged after collection.
  # `mkOptionDefault` lets explicit config and adapter fragments override
  # every surface.

  surfacesOn = cfg.active != null;

  surfacesNixos = {
    console.colors = mkIf (surfacesOn && theme.ansi != { }) (
      lib.mkDefault (
        let
          s = theme.colors.ansi;
        in
        [
          s.black.hex
          s.red.hex
          s.green.hex
          s.yellow.hex
          s.blue.hex
          s.magenta.hex
          s.cyan.hex
          s.white.hex
          s.brightBlack.hex
          s.brightRed.hex
          s.brightGreen.hex
          s.brightYellow.hex
          s.brightBlue.hex
          s.brightMagenta.hex
          s.brightCyan.hex
          s.brightWhite.hex
        ]
      )
    );
    boot.plymouth = mkIf (surfacesOn && theme.plymouth != null) (
      lib.mkDefault {
        theme = theme.plymouth.name;
        themePackages = [ (theme.plymouth.package pkgs) ];
      }
    );
  };

  surfacesHomeManager = {
    gtk = mkIf (surfacesOn && (theme.gtk != null || theme.icon != null || theme.cursor != null)) (
      lib.mkDefault (
        {
          enable = true;
          gtk3 = {
            extraConfig = {
              gtk-application-prefer-dark-theme = theme.dark;
            };
            extraCss = adwaitaCss theme;
          };
          gtk4 = {
            extraConfig = {
              gtk-application-prefer-dark-theme = theme.dark;
            };
            extraCss = adwaitaCss theme;
          }
          // optionalAttrs (theme.gtk != null) {
            theme = {
              name = theme.gtk.name;
              package = theme.gtk.package pkgs;
            };
          };
        }
        // optionalAttrs (theme.gtk != null) {
          theme = {
            name = theme.gtk.name;
            package = theme.gtk.package pkgs;
          };
        }
        // optionalAttrs (theme.icon != null) {
          iconTheme = lib.mkDefault {
            name = theme.icon.name;
            package = theme.icon.package pkgs;
          };
        }
      )
    );
    home.sessionVariables.GTK_THEME = mkIf (surfacesOn && theme.gtk != null) (
      lib.mkDefault theme.gtk.name
    );
    home.pointerCursor = mkIf (surfacesOn && theme.cursor != null) (
      lib.mkDefault {
        enable = true;
        package = theme.cursor.package pkgs;
        name = theme.cursor.name;
        gtk.enable = true;
        x11.enable = true;
        hyprcursor = {
          enable = true;
          size = theme.cursor.size;
        };
      }
    );
    qt = mkIf (surfacesOn && theme.qt != null) (
      lib.mkDefault {
        enable = true;
        platformTheme.name = theme.qt.platformTheme;
        style.name = "kvantum";
      }
    );
    # Plain priority: unique keys merge additively with every other
    # xdg.configFile definition; no override semantics needed.
    xdg.configFile = mkIf (surfacesOn && theme.qt != null) (
      builtins.listToAttrs [
        (lib.nameValuePair "Kvantum/${theme.qt.name}" {
          source = "${theme.qt.package pkgs}/share/Kvantum/${theme.qt.name}";
        })
        (lib.nameValuePair "Kvantum/kvantum.kvconfig" {
          source = (pkgs.formats.ini { }).generate "kvantum.kvconfig" {
            General.theme = theme.qt.name;
          };
        })
      ]
    );
  };

  surfaces =
    if class == "nixos" then
      surfacesNixos
    else if class == "homeManager" then
      surfacesHomeManager
    else
      { };
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
        registered app adapter's `${class}` fragment and the palette's own
        generic surfaces (GTK/cursor/Qt on Home Manager, console/Plymouth on
        NixOS); unsetting it leaves theming entirely to other modules.
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
  # extraction. `surfaces` has static keys and per-option conditions, so it
  # is safe as a bare element; adapter fragments merge after it and
  # override; the live switcher comes last.
  config = mkMerge ([
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
    surfaces
    (mkIf (cfg.active != null) (mkMerge fragments))
    (mkIf (cfg.active != null && cfg.live) liveArtifacts)
  ]);
}
