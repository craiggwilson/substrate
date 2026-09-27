# Extensions

Extensions add capabilities to substrate. Import only what you need.

## Available Extensions

| Extension | Import Path | Description |
|-----------|-------------|-------------|
| `home-manager` | `substrateModules.home-manager` | Home Manager configuration builder |
| `nixos` | `substrateModules.nixos` | NixOS configuration builder |
| `tags` | `substrateModules.tags` | Tag-based module filtering |
| `overlays` | `substrateModules.overlays` | Overlay management |
| `packages` | `substrateModules.packages` | Package definitions |
| `shells` | `substrateModules.shells` | Development shells |
| `jail` | `substrateModules.jail` | Jail/container support |
| `types` | `substrateModules.types` | Custom type definitions |

## Composition Hooks

Core provides push-based hooks so extensions integrate with each other's
builders without either side referencing the other:

| Option | Context received by each function | Consumed by |
|--------|-----------------------------------|-------------|
| `substrate.settings.extraArgsGenerators` | `{ hostcfg, usercfg, inputs, pkgs }` | All module builds — merged results become module arguments |
| `substrate.settings.perHostContributors` | `{ inputs, substrate, hostname, hostcfg, userConfigs, pkgs }` | Host builders (e.g., `nixos` extension) |
| `substrate.settings.perUserContributors` | `{ inputs, substrate, userName, usercfg, pkgs }` | User builders (e.g., `home-manager` extension) |

Each contributor entry is a function that returns a list of modules, appended
to the builder's module list. Contributor function patterns should end with
`...` to tolerate extra context fields. `extraArgsGenerators` entries return
attrsets; each key is passed into modules as an argument of the same name.
`pkgs` matches the build target (host system pkgs for host builds, user
system pkgs for user builds), so helpers can be returned fully bound to
`pkgs`.

## Home Manager Extension

Generates `homeConfigurations` flake output.

### Import

```nix
imports = [ inputs.substrate.substrateModules.home-manager ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.homeManagerModules` | list | External HM modules to include |
| `substrate.users.<name>.nixpkgsConfig` | attrs | Extra nixpkgs config for this user's standalone package set |

Standalone builds import a user package set with
`substrate.settings.nixpkgsConfig` merged with the user's `nixpkgsConfig`.
Users on NixOS hosts share the host's package set instead (HM
`useGlobalPkgs`).

### Output

- `homeConfigurations.<username>` - Standalone Home Manager configurations

### NixOS Integration

When the NixOS extension is also loaded, this extension automatically
integrates Home Manager into every host configuration by registering a
`perHostContributors` entry (`home-manager.users.<name>` etc. with your
`homeManager`-class modules). The nixos extension has no knowledge of this
integration; it simply appends pushed contributors.

### Usage

```nix
substrate.users.alice = {
  system = "x86_64-linux";
};

substrate.modules.programs.git = {
  homeManager = { ... }: {
    programs.git.enable = true;
  };
};
```

## NixOS Extension

Generates `nixosConfigurations` flake output.

### Import

```nix
imports = [ inputs.substrate.substrateModules.nixos ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.nixosModules` | list | External NixOS modules to include |
| `substrate.hosts.<name>.nixpkgsConfig` | attrs | Extra nixpkgs config for this host's package set |

Host package sets are created once per distinct `(system, nixpkgs config)`
combination — `substrate.settings.nixpkgsConfig` merged with the host's
`nixpkgsConfig` — and handed to `nixosSystem` via `nixpkgs.pkgs`, so the
configuration's `pkgs` and the `pkgs` given to `extraArgsGenerators` are the
same value. Because the package set is fixed at creation, set nixpkgs config
through these options; modules that assign `nixpkgs.config` directly are
rejected by nixpkgs' own assertion. `nixpkgs.overlays` set by external
modules is still honored (appended onto the package set).

### Output

- `nixosConfigurations.<hostname>` - NixOS system configurations

### Usage

```nix
substrate.hosts.workstation = {
  system = "x86_64-linux";
  users = [ "alice" ];
};

substrate.modules.hardware.audio = {
  nixos = { ... }: {
    sound.enable = true;
    hardware.pulseaudio.enable = true;
  };
};
```

## Tags Extension

Provides tag-based module filtering.

### Import

```nix
imports = [ inputs.substrate.substrateModules.tags ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.tags` | list | Available tags |
| `substrate.hosts.<name>.tags` | list | Tags for a host |
| `substrate.users.<name>.tags` | list | Tags for a user |
| `substrate.modules.<path>.tags` | list | Tags required for a module |

### Tag Types

**Simple tags:**
```nix
substrate.settings.tags = [ "core" "desktop" "laptop" ];
```

**Metatags with implications:**
```nix
substrate.settings.tags = [
  "laptop"
  "portable"
  { "hardware:dell" = [ "laptop" "portable" ]; }
];
```

When a host/user has `hardware:dell`, they automatically get `laptop` and `portable`.

### Hierarchical Tags

Tags support hierarchy via `:` separator:

```nix
substrate.settings.tags = [
  "desktop"
  "desktop:wayland"
  "desktop:wayland:hyprland"
];
```

Having `desktop:wayland:hyprland` automatically implies `desktop:wayland` and `desktop`.

### hasTag Function

The tags extension provides a `hasTag` function in specialArgs:

```nix
substrate.modules.programs.waybar = {
  tags = [ "desktop:wayland" ];
  homeManager = { hasTag, ... }: {
    programs.waybar = {
      enable = true;
      settings = {
        mainBar = {
          modules-left = [ "hyprland/workspaces" ];
          # Conditionally add battery module
          modules-right = 
            (if hasTag "laptop" then [ "battery" ] else [])
            ++ [ "clock" ];
        };
      };
    };
  };
};
```

## Overlays Extension

Manages nixpkgs overlays.

### Import

```nix
imports = [ inputs.substrate.substrateModules.overlays ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.overlays` | list | Overlays to apply |

### Usage

```nix
substrate.settings.overlays = [
  (final: prev: {
    myPackage = prev.callPackage ./pkgs/my-package { };
  })
  inputs.some-flake.overlays.default
];
```

## Packages Extension

Defines custom packages.

### Import

```nix
imports = [ inputs.substrate.substrateModules.packages ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.packages` | list of paths | Package definition files |
| `substrate.settings.packageNamespace` | string | Namespace in overlay (default: `custom`) |

### Output

- `packages.<system>.<name>` - Package derivations
- `overlays.packages` - Overlay adding packages under namespace

### Usage

```nix
substrate.settings = {
  packages = [
    ./pkgs/my-tool.nix
    ./pkgs/another-tool.nix
  ];
  packageNamespace = "myproject";
};
```

Package file format:
```nix
# pkgs/my-tool.nix
{ lib, pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "my-tool";
  version = "1.0.0";
  # ...
}
```

Packages are available as `pkgs.myproject.my-tool`.

## Shells Extension

Defines development shells.

### Import

```nix
imports = [ inputs.substrate.substrateModules.shells ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.shells` | attrsOf path | Shell definition files |

### Output

- `devShells.<system>.<name>` - Development shells

### Usage

```nix
substrate.settings.shells = {
  default = ./shells/default.nix;
  rust = ./shells/rust.nix;
};
```

Shell file format:
```nix
# shells/rust.nix
{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    rustc
    cargo
    rust-analyzer
  ];
}
```

## Jail Extension

Provides jail.nix support for container-style isolation.

### Import

```nix
imports = [ inputs.substrate.substrateModules.jail ];
```

Requires a `jail-nix` input — resolved by the usual precedence: an explicit
`jail-nix` argument, `substrate.settings.inputs."jail-nix"`, or a flake input
named `jail-nix`.

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.jail.basePermissions` | function or null | Base permissions all jails inherit |
| `substrate.settings.jail.additionalCombinators` | function or null | Custom combinators exposed to jail definitions |

### Module argument

This extension contributes a pkgs-bound `jailLib` to every module build via
`extraArgsGenerators`, so modules can use jail.nix directly without extending
it themselves:

```nix
substrate.modules.services.web = {
  nixos = { pkgs, jailLib, ... }: {
    # jailLib is jail.nix's lib already extended with the host's pkgs,
    # e.g. jailLib.mkJail { ... }
  };
};
```

## Creating Custom Extensions

Extensions are standard NixOS modules:

```nix
# extensions/my-extension/default.nix
{ lib, config, ... }:
{
  # Add new options
  options.substrate.settings.myOption = lib.mkOption {
    type = lib.types.str;
    default = "value";
    description = "My custom option";
  };

  # Add to supported classes (if adding a new class)
  config.substrate.settings.supportedClasses = [ "myClass" ];

  # Register output builders (global = once; perSystem = once per system)
  config.substrate.outputs.perSystem.myOutput = [
    {
      build = { pkgs, system, substrate, ... }: {
        # Return attrset to merge into the flake output
      };
    }
  ];

  # Register a finder
  config.substrate.finders.my-finder.find = cfgs:
    # Return list of modules
    [];

  # Push modules into host/user builds (consumed by builders, blind to producers)
  config.substrate.settings.perHostContributors = [
    ({ inputs, hostname, hostcfg, userConfigs, ... }: [
      # Return modules to append to each host configuration
      { }
    ])
  ];
}
```

Export in `default.nix`:
```nix
{
  # ...existing exports...
  substrateModules = {
    # ...existing modules...
    my-extension = import ./extensions/my-extension;
  };
}
```
