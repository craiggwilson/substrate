# Getting Started

This guide walks you through setting up substrate in your Nix flake.

## Prerequisites

- Nix with flakes enabled
- Basic familiarity with NixOS modules and/or Home Manager

Input names (`nixpkgs`, `home-manager`, `jail-nix`, …) are conventions:
substrate looks up each input by the role it plays. If your flake names one
differently, map it once at the top level:

```nix
substrate.settings.inputs.nixpkgs = inputs.pkgs-unstable;
```

## Installation

Add substrate as a flake input alongside your other dependencies:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager.url = "github:nix-community/home-manager";
    substrate.url = "github:craiggwilson/substrate";
  };

  outputs = inputs:
    inputs.substrate.build.with-flake-parts { inherit inputs; } {
      # Your substrate configuration here
    };
}
```

## Basic Configuration

A minimal substrate configuration defines users, hosts, and modules:

```nix
inputs.substrate.build.with-flake-parts { inherit inputs; } {
  imports = [
    inputs.substrate.substrateModules.home-manager
    inputs.substrate.substrateModules.nixos
  ];

  substrate = {
    # Define a user
    users.alice = {
      system = "x86_64-linux";
    };

    # Define a host
    hosts.workstation = {
      system = "x86_64-linux";
      users = [ "alice" ];
    };

    # Define modules
    modules.programs.git = {
      homeManager = { pkgs, ... }: {
        programs.git = {
          enable = true;
          userName = "Alice";
          userEmail = "alice@example.com";
        };
      };
    };
  };
}
```

## Adding Extensions

Substrate is modular. Import only the extensions you need:

```nix
{
  imports = [
    # Configuration builders
    inputs.substrate.substrateModules.home-manager  # Home Manager configs
    inputs.substrate.substrateModules.nixos         # NixOS configs

    # Module filtering
    inputs.substrate.substrateModules.tags          # Tag-based module inclusion

    # Package management
    inputs.substrate.substrateModules.overlays      # Overlay management
    inputs.substrate.substrateModules.packages      # Package definitions
    inputs.substrate.substrateModules.shells        # Development shells
  ];
}
```

## Using Tags for Module Filtering

The tags extension provides flexible module inclusion based on tags:

```nix
{
  imports = [
    inputs.substrate.substrateModules.tags
  ];

  substrate = {
    # Declare available tags
    settings.tags = [
      "core"
      "desktop"
      "laptop"
      { "hardware:dell" = [ "laptop" ]; }  # Metatag with implications
    ];

    # Assign tags to users
    users.alice = {
      system = "x86_64-linux";
      tags = [ "desktop" ];
    };

    # Assign tags to hosts
    hosts.laptop = {
      system = "x86_64-linux";
      users = [ "alice" ];
      tags = [ "hardware:dell" ];  # Implies "laptop"
    };

    # Tag modules for conditional inclusion
    modules.programs.git = {
      tags = [ "core" ];  # Only included when user/host has "core" tag
      homeManager = { ... }: {
        programs.git.enable = true;
      };
    };

    modules.hardware.backlight = {
      tags = [ "laptop" ];  # Only included on laptops
      nixos = { ... }: {
        programs.light.enable = true;
      };
    };
  };
}
```

## Module Classes

Each module can define configuration for different classes:

| Class | Purpose | Used By |
|-------|---------|---------|
| `nixos` | NixOS system configuration | NixOS extension |
| `homeManager` | Home Manager user configuration | Home Manager extension |
| `generic` | Shared data/configuration | Available to all |

```nix
substrate.modules.programs.neovim = {
  # NixOS-level configuration
  nixos = { pkgs, ... }: {
    environment.systemPackages = [ pkgs.neovim ];
  };

  # User-level configuration
  homeManager = { pkgs, ... }: {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };
  };

  # Shared data (accessible via specialArgs)
  generic = {
    description = "Neovim text editor";
  };
};
```

## Sharing Helper Functions

Modules receive helper functions as arguments. Extensions like `tags` and
`jail` contribute helpers this way (`hasTag`, `jailLib`), and so can you —
add a generator under `substrate.settings.extraArgsGenerators`. Generators
receive `{ hostcfg, usercfg, inputs, pkgs }` and return an attrset whose keys
become module arguments, so both plain helpers and `pkgs`-bound helpers are
possible:

```nix
substrate.settings.extraArgsGenerators = [
  (
    { pkgs, ... }:
    {
      # a pkgs-bound helper, provided fully prepared to modules
      myTheme = import ./lib/theme.nix { inherit pkgs; };
    }
  )
];
```

```nix
substrate.modules.programs.zellij = {
  homeManager = { myTheme, ... }: {
    programs.zellij.config = myTheme.config;
  };
};
```

This replaces depth-sensitive relative imports of shared helpers from within
modules.

## Flake Outputs

Substrate generates standard flake outputs:

- `nixosConfigurations.<hostname>` - NixOS system configurations
- `homeConfigurations.<username>` - Standalone Home Manager configurations
- `packages.<system>.<name>` - Custom packages
- `overlays.<name>` - Nixpkgs overlays
- `devShells.<system>.<name>` - Development shells

## Next Steps

- Read [Concepts](./concepts.md) for deeper understanding
- Explore [Extensions](./extensions.md) for available functionality
- See [Testing](./testing.md) for running and writing tests
