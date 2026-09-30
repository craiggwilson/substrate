# Builds the runtime-switcher artifacts from resolved themes and app
# adapters: one link farm per palette (all template files prebuilt, plus a
# per-theme onswitch/ directory of rendered hook scripts), a manifest
# describing every theme's settings and file destinations, and the switcher
# package. Pure — callers decide where the outputs get installed.
{
  lib,
  pkgs,
}:
{ themes, apps }:
let
  inherit (lib)
    attrValues
    flatten
    unique
    ;

  themeEntries =
    name: theme:
    lib.concatLists (
      lib.mapAttrsToList (
        appName: app:
        lib.optionals (app.templates != null) (
          lib.mapAttrsToList
            (fileName: entry: {
              name = fileName;
              path = pkgs.writeText "theming-${name}-${appName}" entry.content;
            })
            (
              app.templates {
                inherit
                  theme
                  pkgs
                  ;
              }
            )
        )
        ++ lib.optionals (app.onSwitch != null) [
          {
            name = "onswitch/${appName}";
            path = pkgs.writeShellScript "theming-onswitch-${name}-${appName}" (
              app.onSwitch {
                inherit
                  theme
                  pkgs
                  ;
              }
            );
          }
        ]
      ) apps
    );

  themeFarm = name: theme: pkgs.linkFarm "theming-${name}" (themeEntries name theme);

  themeDestinations =
    name: theme:
    lib.filter (e: e.dest != null) (
      lib.concatLists (
        lib.mapAttrsToList (
          _appName: app:
          if app.templates == null then
            [ ]
          else
            lib.mapAttrsToList
              (fileName: entry: {
                src = "${farms.${name}}/${fileName}";
                dest = entry.dest;
              })
              (
                app.templates {
                  inherit
                    theme
                    pkgs
                    ;
                }
              )
        ) apps
      )
    );

  manifest = builtins.mapAttrs (name: theme: {
    path = "${themeFarm name theme}";
    dark = theme.dark;
    gtk = if theme.gtk != null then theme.gtk.name else null;
    icon = if theme.icon != null then theme.icon.name else null;
    font = if theme.font != null then theme.font.name else null;
    font_size = if theme.font != null then theme.font.size else null;
    cursor_theme = if theme.cursor != null then theme.cursor.name else null;
    cursor_size = if theme.cursor != null then theme.cursor.size else null;
    apps = themeDestinations name theme;
  }) themes;

  farms = builtins.mapAttrs themeFarm themes;

  manifestFile = pkgs.writeText "theming-manifest.json" (builtins.toJSON manifest);

  package = pkgs.writeShellApplication {
    name = "theming";
    runtimeInputs = [ pkgs.jq ];
    text = builtins.readFile ./switcher.sh;
  };

  # Theme packages every installed palette references; the dconf names only
  # resolve against themes actually present in the session. Palette package
  # fields are pkgs functions (outer eval has no package set), bound here to
  # the target's pkgs.
  packagesOf =
    field: theme: if theme.${field} != null then [ (theme.${field}.package pkgs) ] else [ ];

  themePackages = unique (
    flatten (
      map (t: packagesOf "gtk" t ++ packagesOf "icon" t ++ packagesOf "cursor" t) (attrValues themes)
    )
  );
in
{
  inherit
    farms
    manifest
    manifestFile
    package
    themePackages
    ;
}
