# Tags Extension

Provides categorical, aspect-like module grouping and filtering.

See [Includes](includes.md) for the sibling module-selection extension.

`tags` groups modules by shared properties. Multiple modules can belong to the
same grouping, and the finder includes the whole group.

`includes` is the explicit graph-based alternative: name the modules directly
and let the finder walk the graph.

Both models can produce the same builds. The difference is whether you think in
groups or in explicit inclusion paths.

### Import

```nix
imports = [ inputs.substrate.substrateModules.tags ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.tags.definitions` | list | Available tag definitions |
| `substrate.settings.tags.selectors` | attrset | Named boolean requirements used for module filtering |
| `substrate.settings.tags.separator` | string | Character separating hierarchical tag levels (default `:`) |
| `substrate.hosts.<name>.tags` | list | Tags for a host |
| `substrate.users.<name>.tags` | list | Tags for a user |
| `substrate.modules.<path>.tags` | list | Tags required for a module |
| `substrate.modules.<path>.tags` | list | Concrete tags or named selectors required for a module |

### Tag Types

**Simple tags:**
```nix
substrate.settings.tags.definitions = [ "core" "desktop" "laptop" ];
```

**Metatags with implications:**
```nix
substrate.settings.tags.definitions = [
  "laptop"
  "portable"
  { "hardware:dell" = [ "laptop" "portable" ]; }
];
```

When a host/user has `hardware:dell`, they automatically get `laptop` and `portable`.

### Tag Selectors

Selectors are named boolean requirements for module filtering. They are separate
from tags: hosts and users can only receive concrete tags, and tag implications
cannot produce selectors.

```nix
substrate.settings.tags.selectors = {
  workstation = {
    and = [
      "common"
      { or = [ "desktop" "laptop" ]; }
      { not = "server"; }
    ];
  };
};

substrate.modules.programs.shared = {
  tags = [ "workstation" ];
  homeManager = { ... };
};
```

Selector expressions can contain concrete tag names and one of `and`, `or`, or
`not` at each level. `and` and `or` take non-empty lists; `not` takes one
expression. Selector names can be used in module `tags` and with `hasTag`.

### Hierarchical Tags

Tags support hierarchy via a separator character, `:` by default:

```nix
substrate.settings.tags.definitions = [
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
