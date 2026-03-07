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

### Output

- `homeConfigurations.<username>` - Standalone Home Manager configurations

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

  # Register output builders
  config.substrate.outputs.myOutput = [
    {
      type = "per-system";
      build = { pkgs, substrate, ... }: {
        # Return attrset to merge into flake output
      };
    }
  ];

  # Register a finder
  config.substrate.finders.my-finder.find = cfgs:
    # Return list of modules
    [];
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
