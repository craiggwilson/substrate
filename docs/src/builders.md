# Builders

Builders integrate substrate with a build system. Each builder decides how
to interpret the output names extensions register under; the flake-parts
builder maps them to flake outputs.

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
5. **Produces outputs**: Maps each output name using the accumulated results

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
- `homeConfigurations.<user>@<host>` (home-only hosts only)
- `overlays.<name>`

A builder's `build` function receives the context its category dictates — see
[Output Builders](concepts.md#output-builders).

### Checks Integration

Extensions add validation checks to `substrate.settings.checks`. Each entry
needs `name`, `valid` and `message`; `warn` (default `false`) makes a failure a
warning instead of an error:

```nix
substrate.settings.checks = [
  {
    name = "every host has a user";
    valid = lib.all (h: h.users != [ ]) (lib.attrValues config.substrate.hosts);
    warn = false;
    message = "some host has no users";
  }
];
```

The adapter turns them into one flake check that prints a pass/warn/fail summary:

```nix
# builders/flake-parts/checks.nix
{
  perSystem =
    { pkgs, ... }:
    {
      checks.substrate-config =
        assert validated;  # throws listing every hard failure
        pkgs.runCommand "substrate-config-validation" { } ''
            echo "All substrate configuration checks passed!"
            cat <<'EOF'
          ${summary}
          EOF
            touch $out
        '';
    };
}
```

A hard failure throws during evaluation, so it surfaces as a broken
configuration rather than a failed build. Warnings only print through
`lib.warn`.

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
      # Fill in each output name from the substrate configuration
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
