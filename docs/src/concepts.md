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
│  │  Interpret each output name by the build system          ││
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
| `usersOnly` | bool (default `false`) | `true` marks the host home-only: users and tags only, no OS config is built |

```nix
substrate.hosts.workstation = {
  system = "x86_64-linux";
  users = [ "alice" "bob" ];
};
```

The `users` option references user names defined in `substrate.users`. This creates a typed reference - invalid user names cause evaluation errors.

### Home-only hosts

A host with `usersOnly = true` declares a machine substrate does *not* administer the OS for (a personal laptop, a company machine you only drop Home Manager on). It builds no NixOS configuration, but its name, tags, `system`, and `nixpkgsConfig` shape the Home Manager configs of its users: each user gets a host-scoped configuration keyed `<user>@<host>`, whose modules receive the host as the `host`/`hostcfg` arguments and select on the host's tags - the same context host-integrated users see inside a NixOS build.

## Users

Users represent user profiles. Each user has:

| `nixpkgsConfig` | attrs | Per-user nixpkgs config merged into its host-scoped package sets (under the host's) |

Users attach to hosts via `hosts.<name>.users`:
1. **Embedded in system hosts** - Home Manager runs inside the host's own configuration
2. **Host-scoped on home-only hosts** - Built as `homeConfigurations.<user>@<host>`

Substrate never builds a host-less ("vanilla") Home Manager configuration; a
user attached to no host produces no output. In every module context the
`host` argument is the machine's name.

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

| Class | Purpose |
|-------|---------|
| `nixos` | A module added to the NixOS system configurations |
| `homeManager` | A module added to the Home Manager user configurations |
| `generic` | A module added to *every* class's configuration |

```nix
substrate.modules.programs.git = {
  # A NixOS module - merged into the system configuration
  nixos = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.git ];
  };

  # A Home Manager module - merged into the user configuration
  homeManager = { pkgs, ... }: {
    programs.git.enable = true;
  };

  # A shared module, merged into both configurations:
  # declare the schema once, and every class sees it
  generic = { lib, ... }: {
    options.myConfig.app.terminal = lib.mkOption {
      description = "The terminal emulator.";
      type = lib.types.nullOr lib.types.package;
      default = null;
    };
  };
};
```

`generic` exists so an interface can be declared once and still be offered to
every class. The same fragment is included in each class configuration's
module list, so a default set there — or an option it *requires* — applies to
`nixos` and `homeManager` identically, and both fragments read the same
`myConfig.` paths without restating anything.

Because the fragment lands in configurations you did not write, it may
*declare* anything but may only *set* what is valid in every class. A
definition of an option `nixos` does not have fails the build at evaluation
time.

### Leaf Detection

Substrate distinguishes between intermediate nodes and leaf nodes:

- **Intermediate nodes**: Containers for organizing modules (`programs`, `hardware`)
- **Leaf nodes**: Actual module definitions (have `nixos`, `homeManager`, or `generic`)

Only leaf nodes are collected and included in configurations.

## Finders

Finders determine which modules to include in a configuration. The finder interface is:

```nix
substrate.moduleFinders.<name>.find = cfgs: [ ... ];
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

  # Modules contributed to configurations, each declaring its target class
  # (extensions push into this; builders consume via substrate.lib.contributionsFor)
  contributors = [ { class = "nixos"; contribute = ...; } ... ];

  # Files to publish under an output name. Extensions add to this namespace:
  # publish.packages, publish.shells, publish.nixosModules, ...
  publish = { ... };

  # Configuration validation checks, run by builders that support them
  checks = [ ... ];
};
```

`settings` is the core vocabulary; individual extensions declare their own keys
in it. For the exhaustive list of every option and which file declares it, see
the [option reference](reference/options.md).

## Output Builders

An output builder fills in one output *name* — for instance
`nixosConfigurations` or `packages` — and is invoked by whichever build is
active. Core has no opinion on what a name means; the builder decides. The
flake-parts builder maps each name to a flake output of the same name (that
one is inherently flake-based), and another builder could interpret the same
names differently — or ignore them.

Builders register under the category that matches how they run:

```nix
# Invoked once, results merged under the same output name
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
| `contributionsFor` | Collect the modules contributed for a given class. Builders call it with the class they speak; contributions targeting other classes are ignored |
| `extraArgsGenerator` | Generate `specialArgs` for configurations |
| `findModulesForClass` | Get modules for a specific class, via the configured finder |
| `hasClass` | Whether a class name is in `settings.supportedClasses` |
| `nameFromPath` | Basename of a path with `.nix` stripped (`foo.nix` → `foo`, `foo/` → `foo`) |
| `resolveInput` | Look up a flake input by role name, honoring `settings.inputs` overrides |
| `unique` | Deduplicate a list |

Extensions add to `substrate.lib` by assigning `config.substrate.lib.<name>`.

## Configuration Flow

1. **Definition**: You define hosts, users, and modules
2. **Finding**: The configured finder selects relevant modules
3. **Building**: Output builders fill in each output name
4. **Evaluation**: Nix evaluates the final configurations

```
Define → Find → Build → Evaluate
```

## Extension Points

Substrate is designed for extension:

1. **New finders**: Implement custom module selection logic
2. **New classes**: Add support for new configuration targets
3. **New outputs**: Register a builder for an additional output name
4. **New options**: Add configuration options to hosts/users/modules
5. **New builders**: Integrate substrate with a different build system; the
   flake-parts builder is just the first one. See
   [Creating Custom Builders](builders.md#creating-custom-builders).
6. **Module contributors**: Push modules into configurations via
   `substrate.settings.contributors`. Each entry declares the `class` it targets
   and a `contribute` function that receives that class's build context (`{ inputs,
   substrate, hostname, hostcfg, userConfigs }` for host classes; `{ inputs,
   substrate, userName, usercfg }` for user classes) and returns a list of modules.
   Builders consume only the entries whose class they speak (via
   `substrate.lib.contributionsFor`), so a contribution is never loaded into a
   configuration whose target extension is absent, and extensions integrate with
   builders without those builders being aware (e.g., the home-manager extension
   registers a `class = "nixos"` contribution so NixOS hosts get `home-manager`
   configuration without the nixos extension knowing about home-manager).
