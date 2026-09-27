# Builders

Builders integrate substrate with build systems to produce flake outputs.

## Available Builders

| Builder | Description |
|---------|-------------|
| `with-flake-parts` | Integration with flake-parts |

## flake-parts Builder

The primary builder integrates with [flake-parts](https://flake.parts/).

### Usage

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    substrate.url = "github:craiggwilson/substrate";
  };

  outputs = inputs:
    inputs.substrate.build.with-flake-parts { inherit inputs; } {
      # Substrate configuration module
    };
}
```

### How It Works

1. **Wraps flake-parts**: Uses `flake-parts-lib.mkFlake` internally
2. **Loads core modules**: Automatically imports substrate core
3. **Evaluates configuration**: Processes your substrate config
4. **Calls output builders**: Invokes registered builders from extensions
5. **Produces outputs**: Generates standard flake outputs

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    substrate.build.with-flake-parts         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                    flake-parts                          ││
│  │  ┌─────────────────────────────────────────────────────┐││
│  │  │              substrate adapter                      │││
│  │  │                                                     │││
│  │  │  • Configures systems from substrate.settings       │││
│  │  │  • Creates pkgs with overlays                       │││
│  │  │  • Calls per-system output builders                 │││
│  │  │  • Calls global output builders                     │││
│  │  │  • Runs configuration checks                        │││
│  │  └─────────────────────────────────────────────────────┘││
│  └─────────────────────────────────────────────────────────┘│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Output Types

The adapter handles two types of outputs:

**Per-system outputs** (built for each system in `substrate.settings.systems`):
- `packages.<system>.<name>`
- `devShells.<system>.<name>`
- `checks.<system>.<name>`

**Global outputs** (not system-specific):
- `nixosConfigurations.<hostname>`
- `homeConfigurations.<username>`
- `overlays.<name>`

### Builder Arguments

Builders are registered under the category that matches how they run; the
category determines their arguments:

**Per-system builders (`substrate.outputs.perSystem.<name>`):**
```nix
{
  build = { pkgs, system, inputs, substrate }: {
    # Return attrset to merge into output
  };
}
```

**Global builders (`substrate.outputs.global.<name>`):**
```nix
{
  build = { inputs, substrate }: {
    # Return attrset to merge into output
  };
}
```

### Checks Integration

The adapter includes a checks module that validates substrate configuration:

```nix
# builders/flake-parts/checks.nix
{
  perSystem = { pkgs, ... }: {
    checks.substrate-config = pkgs.runCommand "substrate-checks" { } ''
      # Runs validation checks from substrate.settings.checks
    '';
  };
}
```

### Combining with Other flake-parts Modules

You can use other flake-parts modules alongside substrate:

```nix
inputs.substrate.build.with-flake-parts { inherit inputs; } {
  imports = [
    inputs.substrate.substrateModules.home-manager
    inputs.substrate.substrateModules.nixos
    
    # Other flake-parts modules
    inputs.treefmt-nix.flakeModule
    inputs.devshell.flakeModule
  ];

  # Substrate configuration
  substrate = { ... };

  # Other flake-parts configuration
  perSystem = { pkgs, ... }: {
    treefmt.programs.nixfmt.enable = true;
  };
}
```

## Creating Custom Builders

To create a builder for a different build system:

```nix
# builders/my-builder/default.nix
{
  build =
    args@{ inputs, ... }:
    module:
    let
      # Evaluate substrate configuration
      evaluated = inputs.nixpkgs.lib.evalModules {
        modules = [
          ../core  # Include substrate core
          module   # User's configuration
        ];
      };
      
      substrate = evaluated.config.substrate;
      outputs = substrate.outputs;
    in
    {
      # Generate flake outputs from substrate configuration
      # Call registered output builders
      # Return final flake attrset
    };
}
```

Export in `default.nix`:
```nix
{
  build = {
    with-flake-parts = ...;
    with-my-builder = (import ./builders/my-builder).build;
  };
}
```

## Output Builder Registration

Extensions register output builders under the category that fits:

```nix
config.substrate.outputs.perSystem.packages = [
  {
    build = { pkgs, ... }:
      # Return packages attrset
      { my-package = pkgs.hello; };
  }
];
```

Multiple builders can register for the same output - results are merged:

```nix
# Extension A
config.substrate.outputs.perSystem.packages = [
  { build = { ... }: { pkg-a = ...; }; }
];

# Extension B
config.substrate.outputs.perSystem.packages = [
  { build = { ... }: { pkg-b = ...; }; }
];

# Result: packages = { pkg-a = ...; pkg-b = ...; }
```
