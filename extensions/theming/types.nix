# Typed definitions for the theming registries: palettes (pure color data +
# pkgs-bound theme packages) and app adapters (per-program theming fragments
# and runtime templates). Registries are defined in the outer substrate
# evaluation (class fragments run in target configs and must not carry data
# that other configs need); selection state lives in the target class
# configurations, never here.
{ lib }:
let
  inherit (lib.types)
    attrsOf
    bool
    float
    functionTo
    int
    lines
    listOf
    nullOr
    package
    path
    raw
    str
    submodule
    ;

  isHex = s: builtins.match "^[0-9a-fA-F]{6}$" s != null;
  hex = lib.types.addCheck str isHex;

  # The common vocabulary: base00..base0F (two-digit hex indices). The
  # base24 convention adds base10..base17 (slots 16-23) as optional extras.
  digitString = "0123456789ABCDEF";

  requiredKeys = map (i: "base0" + builtins.substring i 1 digitString) (lib.range 0 15);

  missingRequired = colors: builtins.filter (k: !colors ? ${k}) requiredKeys;

  themePackageType =
    extra:
    submodule {
      options = {
        name = lib.mkOption {
          type = str;
          description = "Theme name within the package.";
        };
        package = lib.mkOption {
          type = functionTo package;
          example = lib.literalExpression ''
            pkgs: pkgs.catppuccin-gtk.override { variant = "mocha"; }
          '';
          description = ''
            Package providing the theme, as a function from the target
            configuration's package set to a derivation. Palettes are defined
            in the outer substrate evaluation, where no pkgs is in scope; the
            contributed module resolves these against each host/user's
            package set.
          '';
        };
      }
      // extra;
    };

  paletteType = submodule {
    options = {
      colors = lib.mkOption {
        type = attrsOf hex;
        example = {
          base00 = "1e1e2e";
          base05 = "cdd6f4";
          base0D = "89b4fa";
        };
        description = ''
          Palette colors as bare six-digit hex strings (no leading #), keyed
          base00..base0F (plus optional base10..base17 base24 extras). The
          base16 set is required so every palette speaks one common
          vocabulary; derived representations (rgb, ansi, mixins) come from
          the color library.
        '';
        apply =
          v:
          let
            missing = missingRequired v;
          in
          if missing == [ ] then
            v
          else
            builtins.throw ''
              theming: palette colors is missing required keys: ${toString missing}
            '';
      };

      dark = lib.mkOption {
        type = bool;
        default = true;
        description = "Whether the palette is a dark theme.";
      };

      ansi = lib.mkOption {
        type = attrsOf hex;
        default = { };
        example = {
          black = "1e1e2e";
          red = "f38ba8";
        };
        description = ''
          Named ANSI slot colors (black, red, …, brightWhite) as bare hex
          strings. Optional; palettes without it can still theme TTY/terminal
          surfaces that take explicit color lists.
        '';
      };

      ansiMap = lib.mkOption {
        type = attrsOf str;
        default = { };
        example = {
          "1e1e2e" = "black";
          "f38ba8" = "red";
        };
        description = ''
          Map from bare palette hex to ANSI slot name, used to resolve the
          ansi field on color objects. Optional (null where unmapped).
        '';
      };

      gtk = lib.mkOption {
        type = nullOr (themePackageType { });
        default = null;
        example = {
          name = "catppuccin-mocha-lavender-standard";
          package = lib.literalExpression "pkgs: pkgs.catppuccin-gtk";
        };
        description = "GTK theme name and provider package, if any.";
      };

      icon = lib.mkOption {
        type = nullOr (themePackageType { });
        default = null;
        description = "Icon theme name and provider package, if any.";
      };

      cursor = lib.mkOption {
        type = nullOr (themePackageType {
          size = lib.mkOption {
            type = int;
            default = 24;
            description = "Cursor size in pixels.";
          };
        });
        default = null;
        description = "Cursor theme name, provider package, and size, if any.";
      };

      font = lib.mkOption {
        type = nullOr (submodule {
          options = {
            name = lib.mkOption {
              type = str;
              description = "UI font family name.";
            };
            size = lib.mkOption {
              type = float;
              default = 11.0;
              description = "UI font size in points.";
            };
          };
        });
        default = null;
        description = "UI font family and size, if any.";
      };

      qt = lib.mkOption {
        type = nullOr (themePackageType {
          platformTheme = lib.mkOption {
            type = str;
            default = "qtct";
            description = "Qt platform theme name (e.g. \"qtct\" or \"kvantum\").";
          };
        });
        default = null;
        description = ''
          Qt/Kvantum theme name and provider package, if any. Applied on
          Home Manager: style and platform theme wiring plus the Kvantum
          configuration files pointing at the theme.
        '';
      };

      plymouth = lib.mkOption {
        type = nullOr (themePackageType { });
        default = null;
        description = "Plymouth boot theme name and provider package, if any (applied on NixOS).";
      };

      wallpapers = lib.mkOption {
        type = listOf path;
        default = [ ];
        description = ''
          Wallpaper store paths for this theme — several per theme so users
          (or their daemons) can rotate. Consumed through
          ``theming.palette.wallpapers``.
        '';
      };

      extra = lib.mkOption {
        type = attrsOf raw;
        default = { };
        description = ''
          Theme-specific data no typed field anticipates (an app's internal
          theme-name string, a wallpaper focus point, an accent beyond the
          base16 roles). Adapters read it as ``theme.extra``; the extension
          itself never interprets it.
        '';
      };
    };
  };

  templateEntryType = submodule {
    options = {
      content = lib.mkOption {
        type = lib.types.either lib.types.str lib.types.path;
        example = lib.literalExpression ''
          pkgs.formats.json { }.generate "colors.json" colors
        '';
        description = ''
          Rendered file content, as a string or a store path (e.g. a
          `pkgs.formats.*` `generate` result, which has no string renderer).
        '';
      };
      dest = lib.mkOption {
        type = nullOr str;
        default = null;
        example = "$HOME/.config/app/themes/substrate.json";
        description = ''
          Symlink target for runtime switching, expanded against \$HOME by the
          switcher. Null keeps the file available in the theme farm for
          onSwitch hooks to place themselves.
        '';
      };
    };
  };

  appType = submodule {
    options = {
      enabled = lib.mkOption {
        type = functionTo bool;
        default = _: false;
        example = lib.literalExpression ''
          { config, ... }: config.programs.zellij.enable
        '';
        description = ''
          Predicate returning whether theming for this app should be active
          given the evaluation context. Receives the same adapter arguments
          (``{ theme, pkgs, config, lib, class, ... }``). Defaults to false so
          apps must opt in.
        '';
      };

      apply = lib.mkOption {
        type = attrsOf (functionTo (attrsOf raw));
        default = { };
        example = lib.literalExpression ''
          homeManager = { theme, pkgs, ... }: { programs.zellij.themes.hdwlinux = myAdapter theme.colors; };
        '';
        description = ''
          Per-class build-time fragments: function from ``{ theme, pkgs, ... }``
          to an attrset of option assignments. ``theme`` is the resolved palette
          (colors as color objects, package fields as ``pkgs -> package``
          functions to resolve with the given ``pkgs``, plus ``dark``,
          ``wallpapers`` and ``extra``); future fields may be added to the
          argument set, so functions should end their patterns with ``...``.
          Rebuild-only surfaces live here; the active theme is read from the
          target configuration, so flipping it re-renders everything.
        '';
      };

      templates = lib.mkOption {
        type = nullOr (functionTo (attrsOf templateEntryType));
        default = null;
        example = lib.literalExpression ''
          { theme, ... }: { "waybar/colors.css" = { content = css theme.colors; dest = "\$HOME/.config/waybar/colors.css"; }; }
        '';
        description = ''
          Function from the same ``{ theme, pkgs, ... }`` argument to rendered
          files for live switching, prebuilt per palette into a theme link
          farm. Template keys are farm paths and may contain directories;
          prefix them with the app name to avoid collisions between adapters.
        '';
      };

      onSwitch = lib.mkOption {
        type = nullOr (functionTo lines);
        default = null;
        example = lib.literalExpression ''
          { theme, ... }: "ln -sfn \\"$2/waybar/colors.css\\" \$HOME/.config/waybar/colors.css"
        '';
        description = ''
          Function from the same ``{ theme, pkgs, ... }`` argument to a shell
          script, rendered per palette into the theme farm under
          ``onswitch/<app>`` and run after each live switch (with
          $1 = theme name, $2 = farm path) so apps can place files or reload
          themselves where the generic switcher cannot reach. Receives the
          theme record, so hook bodies can bake theme colors; the farm path
          itself is only known at runtime ($2).
        '';
      };
    };
  };
in
{
  inherit paletteType appType;
}
