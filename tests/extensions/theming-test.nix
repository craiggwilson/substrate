# Tests for substrate theming extension
{
  pkgs ? import <nixpkgs> { },
}:
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib)
    lib
    runTests
    evalSubstrate
    ;

  mkColorLib = import ../../extensions/theming/colors.nix;
  switcher = import ../../extensions/theming/switcher.nix;
  configModule = import ../../extensions/theming/config-module.nix;

  throws = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;

  # Minimal base24 palette (base00..base0F required + base10/11 extras).
  paletteColors = {
    base00 = "1e1e2e";
    base01 = "181825";
    base02 = "313244";
    base03 = "45475a";
    base04 = "585b70";
    base05 = "cdd6f4";
    base06 = "f5e0dc";
    base07 = "b4befe";
    base08 = "f38ba8";
    base09 = "fab387";
    base0A = "f9e2af";
    base0B = "a6e3a1";
    base0C = "94e2d5";
    base0D = "89b4fa";
    base0E = "cba6f7";
    base0F = "f2cdcd";
    base10 = "11111b";
    base11 = "eba0ac";
  };

  ansiColors = {
    black = "1e1e2e";
    red = "f38ba8";
    green = "a6e3a1";
    yellow = "f9e2af";
    blue = "89b4fa";
    magenta = "f5e0dc";
    cyan = "94e2d5";
    white = "cdd6f4";
    brightBlack = "585b70";
    brightRed = "eba0ac";
    brightGreen = "a6e3a1";
    brightYellow = "f5e0dc";
    brightBlue = "89b4fa";
    brightMagenta = "cba6f7";
    brightCyan = "94e2d5";
    brightWhite = "b4befe";
  };

  ansiMap = {
    "1e1e2e" = "black";
    "f38ba8" = "red";
    "89b4fa" = "blue";
    "cba6f7" = "brightMagenta";
  };

  fakeDrv = outPath: {
    inherit outPath;
    isDerivation = true;
    type = "derivation";
    overrideAttrs = f: fakeDrv outPath;
  };

  fakePkgs = rec {
    jq = fakeDrv "/fake/jq";
    writeText = name: text: fakeDrv "text-${name}" // { inherit name text; };
    writeShellScript = name: text: fakeDrv "script-${name}" // { inherit name text; };
    writeShellApplication = args: fakeDrv "app-${args.name}";
    linkFarm = name: entries: fakeDrv "farm-${name}" // { inherit name entries; };
    formats.ini = _: {
      generate = name: _: fakeDrv "ini-${name}";
    };
  };

  # A resolved theme in the shape registries and adapters see.
  resolvedTheme =
    name: p:
    p
    // {
      inherit name;
      colors = mkColorLib p.colors p.ansi p.ansiMap;
    };

  samplePaletteRaw = {
    colors = paletteColors;
    ansi = ansiColors;
    ansiMap = ansiMap;
    dark = true;
    gtk = {
      name = "catppuccin-mocha-lavender-standard";
      package = _pkgs: fakeDrv "/fake/gtk";
    };
    icon = {
      name = "Papirus-Dark";
      package = _pkgs: fakeDrv "/fake/icon";
    };
    cursor = {
      name = "Nordzy-cursors";
      package = _pkgs: fakeDrv "/fake/cursor";
      size = 24;
    };
    font = {
      name = "JetBrainsMono Nerd Font";
      size = 11.0;
    };
  };

  themingEval =
    extraModules: evalSubstrate ([ ../../extensions/theming/default.nix ] ++ extraModules);

  baseEval = themingEval [
    {
      config.substrate.settings.theming = {
        palettes.foo = samplePaletteRaw;
        apps.zellij.apply.homeManager = theme: {
          programs.zellij.themes.hdwlinux = theme.colors.base0D.hex;
        };
        apps.zellij.templates = theme: {
          "zellij/hdwlinux.kdl" = {
            content = "theme \"${theme.name}\" {\n  bg = \"${theme.colors.base00.hexWithHashtag}\"\n}";
            dest = "\$HOME/.config/zellij/themes/hdwlinux.kdl";
          };
        };
        apps.opencode.templates = theme: {
          "opencode.json" = {
            content = builtins.toJSON { theme = theme.colors.hex; };
            dest = null;
          };
        };
        # no-dest template + runtime hook that consumes the farm path ($2):
        apps.btop.templates = theme: {
          "btop/hdwlinux.theme" = {
            content = "bg: ${theme.colors.base00.hex}";
            dest = null;
          };
        };
        apps.btop.onSwitch =
          theme:
          "ln -sfn \"$2/btop/hdwlinux.theme\" ~/.config/btop/themes/ && btop-reload ${theme.name} ${theme.colors.base00.hex}";
        # adapter targeting both classes:
        apps.tty.apply = {
          nixos = theme: {
            console.colors = theme.colors.ansi.black.hex;
          };
          homeManager = theme: {
            programs.foo = theme.name;
          };
        };
      };
    }
  ];

  extraArgs = baseEval.config.substrate.lib.extraArgsGenerator {
    hostcfg = {
      name = "testhost";
    };
    usercfg = null;
    inputs = { };
    pkgs = fakePkgs;
  };

  # Eval the contributed module for a class against stub options.
  evalClassWith =
    base: class: modules:
    let
      contributed = base.config.substrate.lib.contributionsFor class {
        inputs = { };
        substrate = base.config.substrate;
        userName = "testuser";
        hostname = "testhost";
        hostcfg = { };
        usercfg = { };
        userConfigs = [ ];
        pkgs = fakePkgs;
      };
    in
    lib.evalModules {
      modules =
        contributed
        ++ [
          (
            { lib, ... }:
            {
              options = {
                assertions = lib.mkOption {
                  type = lib.types.listOf lib.types.raw;
                  default = [ ];
                };
                programs.zellij.themes.hdwlinux = lib.mkOption {
                  type = lib.types.raw;
                  default = null;
                };
                programs.foo = lib.mkOption {
                  type = lib.types.raw;
                  default = null;
                };
                console.colors = lib.mkOption {
                  type = lib.types.raw;
                  default = null;
                };
                environment.systemPackages = lib.mkOption {
                  type = lib.types.listOf lib.types.raw;
                  default = [ ];
                };
                home.packages = lib.mkOption {
                  type = lib.types.listOf lib.types.raw;
                  default = [ ];
                };
                home.pointerCursor = lib.mkOption {
                  type = lib.types.raw;
                  default = null;
                };
                home.sessionVariables = lib.mkOption {
                  type = lib.types.attrsOf lib.types.raw;
                  default = { };
                };
                gtk = lib.mkOption {
                  type = lib.types.attrsOf lib.types.raw;
                  default = { };
                };
                qt = lib.mkOption {
                  type = lib.types.attrsOf lib.types.raw;
                  default = { };
                };
                xdg.configFile = lib.mkOption {
                  type = lib.types.attrsOf lib.types.raw;
                  default = { };
                };
                boot.plymouth = lib.mkOption {
                  type = lib.types.attrsOf lib.types.raw;
                  default = { };
                };
                systemd.user.tmpfiles.rules = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                systemd.user.services = lib.mkOption {
                  type = lib.types.attrsOf lib.types.raw;
                  default = { };
                };
              };
            }
          )
        ]
        ++ modules;
    };

  evalClass = evalClassWith baseEval;

  # Separate fixture for the palette-driven surfaces: a rich palette with
  # every package field populated, and no adapters, so surface output is
  # attributable to the extension alone.
  richPalette = samplePaletteRaw // {
    gtk = {
      name = "rich-standard";
      package = _pkgs: fakeDrv "/fake/rich-gtk";
    };
    icon = {
      name = "RichIcons";
      package = _pkgs: fakeDrv "/fake/rich-icon";
    };
    cursor = {
      name = "RichCursors";
      package = _pkgs: fakeDrv "/fake/rich-cursor";
      size = 28;
    };
    qt = {
      name = "rich-kv";
      package = _pkgs: fakeDrv "/fake/rich-kvantum";
      platformTheme = "qtct";
    };
    plymouth = {
      name = "rich-plymouth";
      package = _pkgs: fakeDrv "/fake/rich-plymouth";
    };
    wallpaper = "/fake/wallpaper.jpg";
  };

  surfacesEval = themingEval [
    {
      config.substrate.settings.theming.palettes.rich = richPalette;
    }
  ];
  evalSurfacesClass = evalClassWith surfacesEval;

in
runTests "Theming Extension" {
  # ── color library ──────────────────────────────────────────────────────────

  colorLib-shape = {
    check =
      let
        cl = mkColorLib paletteColors ansiColors ansiMap;
      in
      cl.base00.hex == "1e1e2e"
      && cl.base00.hexWithHashtag == "#1e1e2e"
      &&
        cl.base00.rgb == [
          30
          30
          46
        ]
      && cl.base00.rgbString == "30 30 46"
      && cl.base00.ansi == "black"
      && cl.base0D.ansi == "blue"
      && cl.base07.ansi == null
      && cl.hex.base05 == "cdd6f4"
      &&
        cl.rgb.base05 == [
          205
          214
          244
        ]
      && cl.ansi.blue.hex == "89b4fa"
      && cl.ansi.base08 == "red";
  };

  colorLib-constructors = {
    check =
      let
        cl = mkColorLib paletteColors ansiColors ansiMap;
      in
      (cl.fromHex "#89b4fa").hex == "89b4fa"
      && (cl.fromHex "89b4fa").hex == "89b4fa"
      &&
        (cl.fromRgb [
          137
          180
          250
        ]).hex == "89b4fa"
      && (cl.fromRgb "137 180 250").hex == "89b4fa"
      && (cl.fromAnsi "blue").hex == "89b4fa";
  };

  colorLib-transforms = {
    check =
      let
        cl = mkColorLib paletteColors ansiColors ansiMap;
      in
      (cl.mix cl.ansi.black cl.ansi.white 1 2).hex == "757a91"
      && (cl.lighten cl.base00 0 1).hex == "1e1e2e"
      && (cl.darken cl.base05 0 1).hex == "cdd6f4"
      && (cl.lighten cl.base00 1 1).hex == "ffffff"
      && (cl.darken cl.base05 1 1).hex == "000000";
  };

  # ── palette registry ───────────────────────────────────────────────────────

  registry-palettes-merge = {
    check =
      let
        p = baseEval.config.substrate.settings.theming.palettes.foo;
      in
      p.colors.base0D == "89b4fa" && p.cursor.size == 24 && p.font.name == "JetBrainsMono Nerd Font";
  };

  registry-rejects-bad-hex = {
    check = throws (
      (themingEval [
        {
          config.substrate.settings.theming.palettes.bad.colors = paletteColors // {
            base00 = "#1e1e2e";
          };
        }
      ]).config.substrate.settings.theming.palettes.bad.colors
    );
  };

  registry-rejects-incomplete-palette = {
    check = throws (
      (themingEval [
        {
          config.substrate.settings.theming.palettes.thin.colors = {
            base00 = "1e1e2e";
            base05 = "cdd6f4";
          };
        }
      ]).config.substrate.settings.theming.palettes.thin.colors
    );
  };

  # ── theme module argument ──────────────────────────────────────────────────

  arg-theme-palettes-resolved = {
    check =
      let
        t = extraArgs.theme.palettes.foo.colors;
      in
      t.base00.hex == "1e1e2e"
      &&
        t.base0D.rgb == [
          137
          180
          250
        ]
      && extraArgs.theme.adapters.zellij.apply.homeManager != null;
  };

  # ── contributed class module: selection + static fan-out ──────────────────

  contribute-inactive-is-noop = {
    check =
      let
        ev = evalClass "homeManager" [ ];
      in
      ev.config.theming.active == null
      && ev.config.home.packages == [ ]
      && ev.config.programs.zellij.themes.hdwlinux == null;
  };

  contribute-applies-active-palette = {
    check =
      let
        ev = evalClass "homeManager" [
          {
            config.theming.active = "foo";
          }
        ];
      in
      ev.config.programs.zellij.themes.hdwlinux == "89b4fa";
  };

  contribute-unknown-theme-fails = {
    check = throws (
      (evalClass "homeManager" [
        {
          config.theming.active = "nope";
        }
      ]).config.programs.zellij.themes.hdwlinux
    );
  };

  # ── live switcher artifacts ────────────────────────────────────────────────

  live-install-and-boot = {
    check =
      let
        ev = evalClass "homeManager" [
          {
            config.theming = {
              active = "foo";
              live = true;
            };
          }
        ];
        rules = ev.config.systemd.user.tmpfiles.rules;
        svc = ev.config.systemd.user.services.theming-boot;
      in
      builtins.any (r: builtins.match ".*manifest.json.*" r != null) rules
      && !(builtins.any (r: builtins.match ".*onswitch.*" r != null) rules)
      && svc.serviceConfig.ExecStart == "app-theming/bin/theming switch foo"
      && svc.wantedBy == [ "graphical-session.target" ]
      && builtins.length ev.config.home.packages == 4;
  };

  switcher-manifest-content = {
    check =
      let
        built =
          switcher
            {
              inherit lib;
              pkgs = fakePkgs;
            }
            {
              themes = {
                foo = resolvedTheme "foo" samplePaletteRaw;
              };
              apps = {
                zellij.templates = theme: {
                  "zellij-theme.kdl" = {
                    content = "theme \"${theme.name}\"";
                    dest = "\$HOME/.config/zellij/themes/hdwlinux.kdl";
                  };
                };
                opencode.templates = theme: {
                  "opencode.json" = {
                    content = theme.colors.base00.hex;
                    dest = null;
                  };
                };
                btop.templates = null;
                btop.onSwitch = _theme: "btop-reload";
              };
            };
        manifest = built.manifest.foo;
      in
      manifest.path == "farm-theming-foo"
      && manifest.gtk == "catppuccin-mocha-lavender-standard"
      && manifest.cursor_size == 24
      && manifest.font == "JetBrainsMono Nerd Font"
      && manifest.dark == true
      &&
        manifest.apps == [
          {
            src = "farm-theming-foo/zellij-theme.kdl";
            dest = "\$HOME/.config/zellij/themes/hdwlinux.kdl";
          }
        ]
      && manifest ? apps
      && built.manifestFile.name == "theming-manifest.json"
      &&
        map (d: d.outPath) built.themePackages == [
          "/fake/gtk"
          "/fake/icon"
          "/fake/cursor"
        ];
  };

  switcher-collects-all-theme-packages = {
    check =
      let
        built =
          switcher
            {
              inherit lib;
              pkgs = fakePkgs;
            }
            {
              themes = {
                a = resolvedTheme "a" (samplePaletteRaw // { icon = null; });
                b = resolvedTheme "b" samplePaletteRaw;
              };
              apps = { };
            };
      in
      map (d: d.outPath) built.themePackages == [
        "/fake/gtk"
        "/fake/cursor"
        "/fake/icon"
      ];
  };
  # ── end-to-end consumer flow ───────────────────────────────────────────────

  e2e-class-filter = {
    check =
      let
        hm = evalClass "homeManager" [
          {
            config.theming.active = "foo";
          }
        ];
        nx = evalClass "nixos" [
          {
            config.theming.active = "foo";
          }
        ];
      in
      hm.config.programs.zellij.themes.hdwlinux == "89b4fa"
      && hm.config.programs.foo == "foo"
      && hm.config.console.colors == null
      && nx.config.console.colors == "1e1e2e"
      && nx.config.programs.zellij.themes.hdwlinux == null
      && nx.config.programs.foo == null
      && nx.config.home.packages == [ ];
  };

  e2e-farm-and-hook = {
    check =
      let
        built =
          switcher
            {
              inherit lib;
              pkgs = fakePkgs;
            }
            {
              themes = {
                foo = resolvedTheme "foo" samplePaletteRaw;
              };
              apps = baseEval.config.substrate.settings.theming.apps;
            };
        entries = built.farms.foo.entries;
        hook = lib.findFirst (e: e.name == "onswitch/btop") { } entries;
        tmpl = lib.findFirst (e: e.name == "btop/hdwlinux.theme") { } entries;
      in
      hook.path.text
      == "ln -sfn \"$2/btop/hdwlinux.theme\" ~/.config/btop/themes/ && btop-reload foo 1e1e2e"
      && tmpl.name == "btop/hdwlinux.theme"
      && lib.any (e: e.name == "zellij/hdwlinux.kdl") entries
      && lib.any (e: e.name == "opencode.json") entries
      &&
        built.manifest.foo.apps == [
          {
            src = "farm-theming-foo/zellij/hdwlinux.kdl";
            dest = "\$HOME/.config/zellij/themes/hdwlinux.kdl";
          }
        ];
  };

  # ── palette-driven generic surfaces ──────────────────────────────────────

  surfaces-homeManager-gtk-cursor-qt = {
    check =
      let
        ev = evalSurfacesClass "homeManager" [
          {
            config.theming.active = "rich";
          }
        ];
      in
      ev.config.theming.palette.name == "rich"
      && ev.config.theming.palette.wallpaper == "/fake/wallpaper.jpg"
      && ev.config.gtk.enable == true
      && ev.config.gtk.theme.name == "rich-standard"
      && ev.config.gtk.iconTheme.name == "RichIcons"
      && ev.config.gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme == true
      && lib.strings.hasInfix "@define-color accent_color #f9e2af" ev.config.gtk.gtk3.extraCss
      && lib.strings.hasInfix "@define-color accent_color #f9e2af" ev.config.gtk.gtk4.extraCss
      && ev.config.home.sessionVariables.GTK_THEME == "rich-standard"
      && ev.config.home.pointerCursor.name == "RichCursors"
      && ev.config.home.pointerCursor.package.outPath == "/fake/rich-cursor"
      && ev.config.home.pointerCursor.hyprcursor.size == 28
      && ev.config.qt.platformTheme.name == "qtct"
      && ev.config.qt.style.name == "kvantum"
      && ev.config.xdg.configFile."Kvantum/rich-kv".source == "/fake/rich-kvantum/share/Kvantum/rich-kv"
      && ev.config.xdg.configFile."Kvantum/kvantum.kvconfig".source.outPath == "ini-kvantum.kvconfig";
  };

  surfaces-nixos-console-plymouth = {
    check =
      let
        ev = evalSurfacesClass "nixos" [
          {
            config.theming.active = "rich";
          }
        ];
      in
      builtins.length ev.config.console.colors == 16
      &&
        ev.config.console.colors == [
          "1e1e2e"
          "f38ba8"
          "a6e3a1"
          "f9e2af"
          "89b4fa"
          "f5e0dc"
          "94e2d5"
          "cdd6f4"
          "585b70"
          "eba0ac"
          "a6e3a1"
          "f5e0dc"
          "89b4fa"
          "cba6f7"
          "94e2d5"
          "b4befe"
        ]
      && ev.config.boot.plymouth.theme == "rich-plymouth"
      && (builtins.head ev.config.boot.plymouth.themePackages).outPath == "/fake/rich-plymouth";
  };

  surfaces-no-switcher-when-live-false = {
    check =
      let
        ev = evalSurfacesClass "homeManager" [
          {
            config.theming.active = "rich";
          }
        ];
      in
      ev.config.systemd.user.services.theming-boot or null == null;
  };

  surfaces-absent-when-inactive = {
    check =
      let
        ev = evalSurfacesClass "homeManager" [ ];
      in
      ev.config.gtk == { }
      && ev.config.qt == { }
      && ev.config.home.pointerCursor == null
      && ev.config.xdg.configFile == { }
      && ev.config.theming.palette == null;
  };
}
