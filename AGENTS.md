# AI Agent Instructions for Substrate

This document provides guidance for AI agents working with the substrate codebase.

## Project Overview

Substrate is a Nix module framework for building flakes with modular, extensible configuration management. It is **not** tied to any specific module inclusion strategy - the tag-based finder is just one implementation of the finder interface.

## Project Structure

```
substrate/
├── default.nix          # Main entry point (build, substrateModules)
├── flake.nix            # Standalone flake with test checks
├── core/                # Core modules (always loaded)
│   ├── checks.nix       # Configuration validation
│   ├── finders.nix      # Module finder interface and "all" finder
│   ├── hosts.nix        # Host configuration type
│   ├── lib.nix          # Shared library functions
│   ├── modules.nix      # Module tree type definition
│   ├── outputs.nix      # Output builder registration
│   ├── settings.nix     # Global settings
│   └── users.nix        # User configuration type
├── extensions/          # Optional extension modules
│   ├── home-manager/    # Home Manager configuration builder
│   ├── jail/            # Bubblewrap isolation via jail.nix (wrap.withBubblewrap)
│   ├── nixos/           # NixOS configuration builder
│   ├── overlays/        # Overlay management
│   ├── packages/        # Package definitions
│   ├── secrets/         # Declarative secrets (SecretSpec)
│   ├── shells/          # Development shells
│   ├── tags/            # Tag-based module filtering
│   ├── types/           # Custom type definitions
│   └── wrappers/        # Declarative executable wrapping (wrap module arg)
├── builders/            # Build system adapters
│   └── flake-parts/     # flake-parts integration
├── tests/               # Test suite
│   ├── lib.nix          # Test utilities
│   ├── core/            # Core module tests
│   ├── extensions/      # Extension tests
│   └── builders/        # Builder tests
├── docs/                # Comprehensive documentation
└── skills/              # AI agent skill files
```

## Key Concepts

### Module Tree

Modules are organized in a tree structure under `substrate.modules`. Leaf nodes contain class-specific configurations:

```nix
substrate.modules.programs.git = {
  nixos = { ... };       # NixOS module
  homeManager = { ... }; # Home Manager module
  generic = { ... };     # Shared configuration
};
```

### Finders

Finders determine which modules to include in a configuration. The interface is:

```nix
substrate.finders.<name>.find = cfgs: [ ... ];
```

Where `cfgs` is a list of host/user configurations and the result is a list of matching modules.

### Extensions

Extensions add capabilities by:
1. Defining new options under `substrate.settings`
2. Adding output builders to `substrate.outputs.global` (invoked once) or
   `substrate.outputs.perSystem` (invoked once per system); entries are
   `{ build = fn; }` where fn receives the category's context
3. Registering new finders in `substrate.finders`
4. Adding to `substrate.settings.supportedClasses`
5. Pushing module contributors to `substrate.settings.contributors`, each entry
   declaring the `class` it targets; builders consume only the entries whose
   class they speak (via `substrate.lib.contributionsFor`), without knowing
   which extension pushed them; e.g., home-manager integrates itself into NixOS
   hosts with a `class = "nixos"` entry instead of the nixos extension
   referencing it. An extension targeting several builders registers one entry
   per class; entries whose class has no enabled builder are simply not loaded.
6. Contributing module arguments via `substrate.settings.extraArgsGenerators`
   (each returned key becomes a module argument; generators receive
   `{ hostcfg, usercfg, inputs, pkgs }`, so helpers can be returned already
   bound to `pkgs`; e.g., the jail extension provides `jailLib`)
7. Registering into another extension's push registry, so extensions can
   extend each other's APIs without either side referencing the other; e.g.,
   jail contributes `substrate.settings.wrappers.backends.isolate` and the
   wrappers extension surfaces every registered backend at key `foo` as `wrap.withFoo` (and
   `settings.wrappers.defaultBackend` picks where the bare `wrap` functor goes).
   When the target option is owned by a possibly-absent extension, guard the
   definition with `lib.optionalAttrs (options.<path> ? <name>)` — a plain
   definition (or even `mkIf false`) against an undeclared option is an
   evaluation error.

Core must remain implementation-agnostic: hooks are named after core
concepts (hosts, users, package sets), never after specific builders or
targets. `substrate.settings/systems/nixpkgsConfig` and
`substrate.<hosts|users>.<name>.nixpkgsConfig` are core-level package-set
vocabulary (like `systems` itself), honored by whichever builder creates
package sets.
Extensions must resolve flake inputs by role via
`config.substrate.lib.resolveInput "<role>" inputs` (which honors
`substrate.settings.inputs` overrides) rather than reading `inputs.<name>`
directly.
`substrate.lib` is internal plumbing for builders/extensions; it must never
be passed into host/user modules.

### Builders

Builders integrate substrate with build systems. Currently only flake-parts is supported. The builder:
1. Evaluates the substrate configuration
2. Calls registered output builders
3. Produces flake outputs

## Nix Idioms Used

- **Module system**: All configuration uses `lib.evalModules`
- **Option types**: Extensive use of `lib.types.*` for validation
- **Lazy evaluation**: Configuration is evaluated on-demand
- **Attribute merging**: Multiple modules can contribute to the same option

## Testing

Tests use a custom test harness in `tests/lib.nix`:

```nix
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) evalSubstrate runTests;
in
runTests "Test Suite Name" {
  testName = {
    check = /* boolean expression */;
  };
};
```

Run all tests:
```bash
nix flake check
```

## Common Tasks

### Adding a New Extension

1. Create `extensions/<name>/default.nix`
2. Define options under `substrate.settings` or `substrate.<name>`
3. Add output builders if needed
4. Export from `default.nix` in `substrateModules`
5. Add tests in `tests/extensions/<name>-test.nix`
6. Register test in `flake.nix` checks

### Adding a New Finder

1. Create extension or modify existing one
2. Register finder: `config.substrate.finders.<name>.find = cfgs: ...`
3. Optionally set as default: `config.substrate.settings.modulesFinder = "<name>"`

### Modifying Core Behavior

1. Core modules are in `core/`
2. Changes affect all configurations
3. Ensure backward compatibility
4. Update tests in `tests/core/`

## Code Style

- Follow Nix formatting conventions (use `nixfmt-rfc-style`)
- Document options with `description`
- Use `lib.mkOption` with proper types
- Prefer composition over inheritance
- Keep modules focused and single-purpose

## Validation

Before submitting changes:

```bash
# Format code
nix fmt

# Run tests
nix flake check

# Build to verify no evaluation errors
nix build
```
