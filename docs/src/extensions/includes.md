# Includes Extension

The `includes` extension treats substrate modules as a directed acyclic graph.
Hosts and users name entry modules, and modules can include other modules by
referencing other module nodes. The finder walks the graph and returns the
reachable modules.

## Import

```nix
imports = [ inputs.substrate.substrateModules.includes ];
```

Do not import this alongside `tags`. Both set
`substrate.settings.modulesFinder`.

## Example

```nix
{
  imports = [ inputs.substrate.substrateModules.includes ];

  substrate.hosts.workstation.includes = [ "desktop" ];

  substrate.modules.desktop = {
    includes = [ "gui" ];
    nixos = { ... }: {
      services.xserver.enable = true;
    };
  };

  substrate.modules.gui = {
    nixos = { ... }: {
      programs.waybar.enable = true;
    };
  };
}
```

Here the host points at `desktop`, and `desktop` pulls in `gui` transitively.

## Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.hosts.<name>.includes` | list of string | Module paths to include from this host |
| `substrate.users.<name>.includes` | list of string | Module paths to include from this user |
| `substrate.modules.<path>.includes` | list of string | Module paths included transitively from this module |

## Notes

- Paths use `/` as a separator, e.g. `hardware/audio`.
- The finder fails on missing paths.
- Cycles are rejected, so the graph stays acyclic.
