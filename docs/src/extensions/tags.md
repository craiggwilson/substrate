# Tags Extension

Provides tag-based module filtering.

### Import

```nix
imports = [ inputs.substrate.substrateModules.tags ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.tags.options` | list | Available tags |
| `substrate.settings.tags.separator` | string | Character separating hierarchical tag levels (default `:`) |
| `substrate.hosts.<name>.tags` | list | Tags for a host |
| `substrate.users.<name>.tags` | list | Tags for a user |
| `substrate.modules.<path>.tags` | list | Tags required for a module |

### Tag Types

**Simple tags:**
```nix
substrate.settings.tags.options = [ "core" "desktop" "laptop" ];
```

**Metatags with implications:**
```nix
substrate.settings.tags.options = [
  "laptop"
  "portable"
  { "hardware:dell" = [ "laptop" "portable" ]; }
];
```

When a host/user has `hardware:dell`, they automatically get `laptop` and `portable`.

### Hierarchical Tags

Tags support hierarchy via a separator character, `:` by default:

```nix
substrate.settings.tags.options = [
  "desktop"
  "desktop:wayland"
  "desktop:wayland:hyprland"
];
```

Having `desktop:wayland:hyprland` automatically implies `desktop:wayland` and `desktop`.

Change `substrate.settings.tags.separator` to use a different character — `.` makes
`desktop.wayland.hyprland` hierarchical instead, and `:` stops being special:

```nix
substrate.settings.tags.separator = ".";
```

The separator governs *implication* only. Module matching and `hasTag` are plain
string-prefix tests and ignore it, so `hasTag "gui"` matches a `gui-something` tag
either way.

### hasTag Function

The tags extension provides a `hasTag` function in specialArgs:

```nix
substrate.modules.programs.waybar = {
  tags = [ "desktop:wayland" ];
  homeManager =
    { hasTag, ... }:
    {
      programs.waybar = {
        enable = true;
        settings = {
          mainBar = {
            modules-left = [ "hyprland/workspaces" ];
            # Conditionally add battery module
            modules-right =
              (if hasTag "laptop" then [ "battery" ] else [ ])
              ++ [ "clock" ];
          };
        };
      };
    };
};
```

---

See the [extension index](index.md) for the composition hooks and the full list.
