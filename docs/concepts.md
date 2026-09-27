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

  # Flake inputs keyed by role, for when your input names differ
  # (e.g., inputs.nixpkgs = inputs.pkgs-unstable)
  inputs = { ... };

  # Supported module classes (extensions add to this)
  supportedClasses = [ "nixos" "homeManager" "generic" ];

  # nixpkgs config baked into every package set substrate creates
  # (overridable per host/user via <entity>.nixpkgsConfig)
  nixpkgsConfig = { ... };

  # Extra arguments passed to configurations
  extraArgsGenerators = [ ... ];

  # Modules contributed to every host/user configuration (extensions push into these)
  perHostContributors = [ ... ];
  perUserContributors = [ ... ];
};
```

## Output Builders

Output builders generate flake outputs. They're registered by extensions
under the category that matches how they run:

```nix
# Invoked once, results merged into the flake output of the same name
config.substrate.outputs.global.homeConfigurations = [
  {
    build = { inputs, substrate }: { ... };
  }
];

# Invoked once per system in settings.systems, results merged under
# <output>.<system>
config.substrate.outputs.perSystem.packages = [
  {
    build = { pkgs, system, inputs, substrate }: { ... };
  }
];
```

### Builder Categories

| Category | Build function receives | Example outputs |
|----------|------------------------|-----------------|
| `global` | `{ inputs, substrate }` | `nixosConfigurations`, `homeConfigurations`, `overlays` |
| `perSystem` | `{ pkgs, system, inputs, substrate }` | `packages`, `devShells` |

Multiple extensions may contribute builders to the same output name; all of
their results are merged.

## Library Functions

Substrate provides utility functions via `substrate.lib`. These are
**internal to builders and extensions** and are not passed into host/user
modules. To share helper functions with modules, contribute them via
`substrate.settings.extraArgsGenerators` — each key of the returned attrset
arrives in modules as an argument of the same name, computed per build with
`{ hostcfg, usercfg, inputs, pkgs }` available.

| Function | Description |
|----------|-------------|
| `unique` | Deduplicate a list |
| `findModulesForClass` | Get modules for a specific class |
| `extraArgsGenerator` | Generate specialArgs for configurations |
| `resolveInput` | Look up a flake input by role name, honoring `settings.inputs` overrides |

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
5. **Module contributors**: Push modules into host or user builds via
   `substrate.settings.perHostContributors` / `perUserContributors`. Each
   contributor is a function that receives build context (`{ inputs, substrate,
   hostname, hostcfg, userConfigs }` for hosts; `{ inputs, substrate, userName,
   usercfg }` for users) and returns a list of modules. Builders consume these
   without knowing which extension produced them, and extensions integrate with
   builders without those builders being aware (e.g., the home-manager extension
   registers a `perHostContributors` entry so NixOS hosts get `home-manager`
   configuration without the nixos extension knowing about home-manager).
