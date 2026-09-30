# Theming extension: typed registries for palettes and per-app theme
# adapters, plus a runtime switcher. Definitions are pure data living in
# substrate settings so any module can reference them; all selection state
# (`theming.active`, `theming.live`) and application happen inside the
# target class configurations via contributed modules, so user/host modules
# drive themes and can flip them reactively.
#
# Palettes are pushed by theme modules (typically tagged leaves under
# `substrate.modules.theming.*`) into `substrate.settings.theming.palettes`.
# The contributed class module applies a palette's generic surfaces when it
# is active: GTK theme/icon/Adwaita CSS, pointer cursor, Qt/Kvantum, session
# GTK_THEME (Home Manager); console palette, Plymouth (NixOS). All are
# `mkDefault`, so explicit config and adapters override them.
# Program modules push their theme mapping into
# `substrate.settings.theming.apps.<name>`: `apply` (rebuild-time option
# fragments per class), `templates` (prebuilt files for live switching),
# `onSwitch` (hook script). Adding a theme or a themed app touches only
# that module — the extension wires them together.
#
# The switcher model (manifest, dest symlinks, dconf, hooks) follows nati's
# approach; it is substrate-native (a shell script + jq), not a nati
# integration.
{ lib, config, ... }:
let
  settings = config.substrate.settings;

  inherit (import ./types.nix { inherit lib; }) paletteType appType;
  mkColorLib = import ./colors.nix;

  # Resolved palette: declared data plus the color library (baseXX -> color
  # objects with hex/rgb/ansi views and mixers).
  resolveTheme =
    name: p:
    p
    // {
      inherit name;
      colors = mkColorLib p.colors p.ansi p.ansiMap;
    };

  resolvedPalettes = lib.mapAttrs resolveTheme settings.theming.palettes;

  # [ { class = ...; contribute = ...; } ]
  contributedFor = class: packagePath: {
    inherit class;
    contribute =
      { pkgs, ... }:
      [
        (import ./config-module.nix {
          inherit
            lib
            pkgs
            class
            adapters
            packagePath
            ;
          themes = resolvedPalettes;
        })
      ];
  };

  adapters = settings.theming.apps;
in
{
  options.substrate.settings.theming = {
    palettes = lib.mkOption {
      type = lib.types.attrsOf paletteType;
      default = { };
      description = ''
        Palette definitions, keyed by name: base16-required/base24-extensible
        colors as bare hex, optional ANSI slot mapping, and optional named
        surfaces (``gtk``/``icon``/``cursor``/``font``/``qt``/``plymouth``
        packages and a ``wallpaper`` path; package fields are
        ``pkgs -> package`` functions, resolved against each target's package
        set — this option tree is evaluated in the outer substrate config,
        where no pkgs is in scope). When a palette is active, the contributed
        class module applies its generic surfaces. Pure data — which palette
        is active is decided per configuration, never here.
      '';
    };

    apps = lib.mkOption {
      type = lib.types.attrsOf appType;
      default = { };
      description = ''
        App theme adapters, keyed by app name. Each entry contributes
        per-class build-time option fragments (`apply`), prebuilt template
        files for live switching (`templates`), and an `onSwitch` hook.
      '';
    };
  };

  config.substrate = {
    settings.extraArgsGenerators = [
      (
        { ... }:
        {
          theme = {
            palettes = resolvedPalettes;
            inherit adapters mkColorLib;
          };
        }
      )
    ];

    settings.contributors = [
      (contributedFor "nixos" [
        "environment"
        "systemPackages"
      ])
      (contributedFor "homeManager" [
        "home"
        "packages"
      ])
    ];
  };
}
