# Includes Extension

The `includes` extension is explicit graph-based module inclusion. Hosts and
users name entry modules, modules can include other modules, and the finder
walks the graph to return the reachable modules.

## Import

```nix
imports = [ inputs.substrate.substrateModules.includes ];
```

Do not import this alongside `tags`. Both set `substrate.settings.modulesFinder`.
See [Tags](tags.md) for the sibling module-selection extension.

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

## How It Works

An `includes` value can be one of two shapes:

| Shape | Example | What it means |
|------|---------|---------------|
| list | `[ "programs/git", config.substrate.modules.programs.git ]` | Include these modules |
| function | `({ hostcfg, usercfg, ... }: [ ... ])` | Compute the list from the host or user context |

The list may contain strings and/or module nodes. A module node is checked by the
module system, so a missing module fails during evaluation instead of later at
build time.

When a function is used, it receives a context attrset with these fields:

| Arg | Meaning |
|-----|---------|
| `hostcfg` | The host being built |
| `usercfg` | The current user being built, or `null` when the current config is the host |

```nix
{ config, ... }: {
  substrate.hosts.workstation.includes = [ config.substrate.modules.desktop ];
}
```

Because the function returns a list, `lib.optionals` composes cleanly:

```nix
substrate.hosts.workstation.includes = { hostcfg, ... }:
  lib.optionals (hostcfg.system == "aarch64-darwin") [ "darwin-stuff" ];
```

## Context

The function form receives the host/user context as `{ hostcfg, usercfg, ... }`.
Available fields are `name`, `system`, `usersOnly`, `users`, and `nixpkgsConfig`,
plus `tags` when the `tags` extension is loaded.

`includes` is the direct way to say which modules belong in a build by naming
them in a graph.

`tags` is the categorical way to say which modules belong together. Multiple
modules can share the same tags, and the finder includes the whole group.

Both models can express the same end result. The difference is how you choose to
describe it.

## Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.hosts.<name>.includes` | list or function | The modules to include for this host |
| `substrate.users.<name>.includes` | list or function | The modules to include for this user |
| `substrate.modules.<path>.includes` | list or function | The modules included transitively from this module |

## Notes

- Paths use `/` as a separator, e.g. `hardware/audio`.
- The finder fails on missing paths.
- Cycles are rejected, so the graph stays acyclic.
- Naming something that is not a module fails, and the error says so. A host or
  user config is the likely mistake: it has no address.
- Entries are not evaluated when `includes` is read, only when the walk reaches
  them. Naming a module is cheap; evaluating it is not.
- The returned modules are ordered by address, so the result is stable across
  runs.

---

See the [extension index](index.md) for the full list of extensions.
