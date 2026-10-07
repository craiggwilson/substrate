# Builders

Builders integrate substrate with a build system. Each builder decides how
to interpret the output names extensions register under; the flake-parts
builder maps them to flake outputs.

## Available Builders

| Builder | Description |
|---------|-------------|
| `with-flake-parts` | Integration with flake-parts |
| `raw` | Plain attrset, no flake required |

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

Core registers a per-system output builder that turns them into one check
that prints a pass/warn/fail summary. Both builders emit it, so the same
validation runs whether you use flake-parts or the raw builder:

```nix
# core/checks.nix
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

## raw Builder

The `raw` builder produces the same outputs as the flake-parts builder, but as
a plain attrset with no flake and no flake-parts dependency. Use it when you
manage inputs with a pin tool such as [npins](https://github.com/xzfc/npins) or
[niv](https://github.com/nmattia/niv), or when you want to evaluate substrate
from a non-flake `default.nix`.

### Usage

```nix
# default.nix with npins
let
  sources = import ./npins;
  substrate = import sources.substrate;
in
substrate.build.raw { inputs = sources; } {
  imports = [
    substrate.substrateModules.nixos
    substrate.substrateModules.home-manager
  ];

  substrate.hosts.myhost = {
    system = "x86_64-linux";
    users = [ "alice" ];
  };
}
```

### Input contract

`inputs` is an attrset keyed by role name (`nixpkgs`, `home-manager`,
`jail-nix`, …). Values may be flakes or pinned source trees. Extensions use
flake outputs when present and fall back to the equivalent path import
otherwise, so both shapes work without extra configuration.

### Output shape

Output names match the flake-parts builder exactly; the only difference is that
per-system outputs are keyed by system directly under each output name:

- `nixosConfigurations.<hostname>`
- `homeConfigurations.<user>@<host>`
- `overlays.<name>`
- `packages.<system>.<name>`
- `devShells.<system>.<name>`
- `checks.<system>.<name>`

### System nixpkgs pin

NixOS systems built through the raw builder set `nixpkgs.flake.source` to the
pinned nixpkgs, exactly as nixpkgs' flake entry point does — so the deployed
system pins its own nixpkgs in `/etc/nix/registry.json` and NIX_PATH, and
`<nixpkgs>` on the machine resolves to the nixpkgs the system was built with.
This adds the nixpkgs source to the system closure; opt out with
`nixpkgs.flake.source = lib.mkForce null;` in any NixOS module.

One residual difference from flake builds: `system.nixos.version` carries no
revision suffix (e.g. `26.11pre-git` rather than `26.11.20261005.aa48d34`),
because a plain source import cannot know its git revision.

### Non-flake build recipes

Build and activate a NixOS system without flakes:

```bash
nix build -f . nixosConfigurations.myhost.config.system.build.toplevel
sudo nix build --profile /nix/var/nix/profiles/system -f . \
  nixosConfigurations.myhost.config.system.build.toplevel
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

Build and activate a Home Manager configuration:

```bash
nix build -f . homeConfigurations.alice@myhost.activationPackage
./result/activate
```

Run the substrate configuration checks (the `nix flake check` equivalent):

```bash
nix build -f . checks.x86_64-linux.substrate-config
```

## Creating Custom Builders

To create a builder for a different build system, follow the same contract
registered by `substrate.outputs`. The `raw` builder is a working reference
implementation:

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
