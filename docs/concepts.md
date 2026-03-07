# Core Concepts

This document explains the fundamental concepts in substrate.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        Your Flake                           │
├─────────────────────────────────────────────────────────────┤
│  substrate.build.with-flake-parts { inputs } { ... }        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Hosts     │  │   Users     │  │      Modules        │  │
│  │             │  │             │  │                     │  │
│  │ workstation │  │   alice     │  │ programs.git        │  │
│  │ laptop      │  │   bob       │  │ hardware.audio      │  │
│  └─────────────┘  └─────────────┘  │ services.syncthing  │  │
│                                    └─────────────────────┘  │
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                      Finders                            ││
│  │  Determine which modules to include for each config     ││
│  │  • "all" - include all modules                          ││
│  │  • "by-tags" - filter by tag matching                   ││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                   Output Builders                       ││
│  │  Generate flake outputs from substrate configuration    ││
│  │  • nixosConfigurations                                  ││
│  │  • homeConfigurations                                   ││
│  │  • packages, overlays, devShells                        ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

## Hosts

Hosts represent machines (physical or virtual). Each host has:

| Option | Type | Description |
|--------|------|-------------|
| `system` | string | Architecture (e.g., `x86_64-linux`) |
| `users` | list of strings | Users to include in this host's configuration |

```nix
substrate.hosts.workstation = {
  system = "x86_64-linux";
  users = [ "alice" "bob" ];
};
```

The `users` option references user names defined in `substrate.users`. This creates a typed reference - invalid user names cause evaluation errors.

## Users

Users represent user profiles. Each user has:

| Option | Type | Description |
|--------|------|-------------|
| `system` | string | Architecture for standalone Home Manager configs |

```nix
substrate.users.alice = {
  system = "x86_64-linux";
};
```

Users can be:
1. **Embedded in hosts** - Included via `hosts.<name>.users`
2. **Standalone** - Built as independent Home Manager configurations

## Modules

Modules are the building blocks of configuration. They're organized in a tree structure:

```nix
substrate.modules = {
  programs = {
    git = { ... };
    neovim = { ... };
  };
  hardware = {
    audio = { ... };
    bluetooth = { ... };
  };
  services = {
    syncthing = { ... };
  };
};
```

### Module Classes

Each module can define configuration for different "classes":

```nix
substrate.modules.programs.git = {
  # NixOS module - system-level configuration
  nixos = { config, pkgs, ... }: {
    programs.git.enable = true;
  };

  # Home Manager module - user-level configuration
  homeManager = { config, pkgs, ... }: {
    programs.git = {
      enable = true;
      userName = "Alice";
    };
  };

  # Generic - shared data accessible to all
  generic = {
    programs.git = {
      description = "Git version control";
      category = "development";
    };
  };
};
```

### Leaf Detection

Substrate distinguishes between intermediate nodes and leaf nodes:

- **Intermediate nodes**: Containers for organizing modules (`programs`, `hardware`)
- **Leaf nodes**: Actual module definitions (have `nixos`, `homeManager`, or `generic`)

Only leaf nodes are collected and included in configurations.

## Finders

Finders determine which modules to include in a configuration. The finder interface is:

```nix
substrate.finders.<name>.find = cfgs: [ ... ];
```

Where:
- `cfgs` is a list of host/user configurations
- Returns a list of matching module leaf nodes

### Built-in Finders

| Finder | Description |
|--------|-------------|
| `all` | Returns all modules (no filtering) |
| `by-tags` | Filters modules by tag matching (requires tags extension) |

### Setting the Default Finder

```nix
substrate.settings.modulesFinder = "by-tags";  # or "all"
```

## Settings

Global settings control substrate behavior:

```nix
substrate.settings = {
  # Systems to build for
  systems = [ "x86_64-linux" "aarch64-linux" ];

  # Which finder to use
  modulesFinder = "all";

  # Supported module classes (extensions add to this)
  supportedClasses = [ "nixos" "homeManager" "generic" ];

  # Extra arguments passed to configurations
  extraArgsGenerators = [ ... ];
};
```

## Output Builders

Output builders generate flake outputs. They're registered by extensions:

```nix
config.substrate.outputs.homeConfigurations = [
  {
    type = "global";  # or "per-system"
    build = { inputs, substrate }: { ... };
  }
];
```

### Output Types

| Type | Description | Example |
|------|-------------|---------|
| `global` | Not system-specific | `nixosConfigurations`, `homeConfigurations` |
| `per-system` | Built per-system | `packages`, `devShells` |

## Library Functions

Substrate provides utility functions via `substrate.lib`:

| Function | Description |
|----------|-------------|
| `unique` | Deduplicate a list |
| `findModulesForClass` | Get modules for a specific class |
| `extraArgsGenerator` | Generate specialArgs for configurations |

## Configuration Flow

1. **Definition**: You define hosts, users, and modules
2. **Finding**: The configured finder selects relevant modules
3. **Building**: Output builders generate flake outputs
4. **Evaluation**: Nix evaluates the final configurations

```
Define → Find → Build → Evaluate
```

## Extension Points

Substrate is designed for extension:

1. **New finders**: Implement custom module selection logic
2. **New classes**: Add support for new configuration targets
3. **New outputs**: Generate additional flake outputs
4. **New options**: Add configuration options to hosts/users/modules
