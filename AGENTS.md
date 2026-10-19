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
│   ├── default.nix      # Core module set
│   ├── finders.nix      # Module finder interface and "all" finder
│   ├── hosts.nix        # Host configuration type
│   ├── lib.nix          # Shared library functions
│   ├── modules.nix      # Module tree type definition
│   ├── outputs.nix      # Output builder registration
│   ├── overlays.nix     # Overlay management
│   ├── settings.nix     # Global settings
│   └── users.nix        # User configuration type
├── extensions/          # Optional extension modules
│   ├── bubblewrap/      # Bubblewrap isolation via jail.nix (the bubblewrap contributor)
│   ├── home-manager/    # Home Manager configuration builder
│   ├── nixos/           # NixOS configuration builder
│   ├── overlays/        # Overlay management
│   ├── packages/        # Package definitions
│   ├── darwin/           # nix-darwin configuration builder
│   ├── secrets/         # Declarative secrets (SecretSpec)
│   ├── shells/          # Development shells
│   ├── tags/            # Tag-based module filtering
│   └── wrappers/        # Declarative executable wrapping (wrap module arg)
├── builders/            # Build system adapters
│   ├── common.nix       # Shared builder core
│   ├── flake-parts/     # flake-parts integration
│   └── plain.nix        # Plain attrset builder (no flake/flake-parts)
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
substrate.moduleFinders.<name>.find = cfgs: [ ... ];
```

Where `cfgs` is a list of host/user configurations and the result is a list of matching modules.

### Extensions

Extensions add capabilities by:
1. Defining new options under `substrate.settings`
2. Adding output builders to `substrate.outputs.global` (invoked once) or
   `substrate.outputs.perSystem` (invoked once per system); entries are
   `{ build = fn; }` where fn receives the category's context. A value a
   consumer is meant to read goes through `substrate.publish` instead — see
   8.
3. Registering new finders in `substrate.moduleFinders`
4. Adding to `substrate.settings.supportedClasses`
5. Pushing module contributors to `substrate.settings.contributors`, each entry
   declaring the `class` it targets; builders consume only the entries whose
   class they speak (via `substrate.lib.contributionsFor`), without knowing
   which extension pushed them; e.g., home-manager integrates itself into NixOS
   hosts with a `class = "nixos"` entry instead of the nixos extension
   referencing it. An extension targeting several builders registers one entry
   per class; entries whose class has no enabled builder are simply not loaded.
6. Contributing module arguments, by whichever avenue fits what the argument
   depends on. Both stay open:
   - `substrate.settings.extraArgsGenerators` for an argument built from build
     context alone: each returned key becomes a module argument, and generators
     receive `{ hostcfg, usercfg, inputs, pkgs }`, so helpers can be returned
     already bound to `pkgs` (e.g., the bubblewrap extension provides `jailLib`).
   - A class module writing `_module.args` for an argument that needs the
     configuration it belongs to. A generator runs in the builder, *outside* the
     configuration being built, so there is no `config` there to name; nixpkgs
     also passes argument values through verbatim rather than applying them, so a
     closure would arrive unapplied. `wrap` is published this way (see
     `extensions/wrappers/class-module.nix`) so a contributor hook can read the
     options declared beside the wrapper.
   Extend another extension's argument from a class module with `lib.mkForce`.
   Two plain definitions of the same `_module.args` key conflict, so an argument
   has exactly one definition.
7. Registering into another extension's push registry, so extensions can
   extend each other's APIs without either side referencing the other.
   The wrappers extension owns the `wrap` module argument: one call, one
   wrapper. There is one mode — `wrap.package { … }` — because a wrapper wraps a
   package, and writing a script is nixpkgs' job (`writeShellApplication`,
   `writeScriptBin`); wrapping the result works like anything else. A spec is the
   *core vocabulary flat at the top level* (`package`, `env`, `args`, `files`,
   `prefix`, `stub`, ...) plus at most one key per contributor it names —
   `secrets.scope`, `bubblewrap.permissions`. An extension contributes
   `substrate.settings.wrappers.contributors.<name>` and the core renders the
   rest.
   A contributor entry is
   `{ priority, options, prefix, runtimeInputs, setup, program, envNames,
   context, incompatible }`. It only *adds*: `priority` (required integer,
   lower = further from the program, ordering the exec chain), `options` (its
   own submodule under its key), `prefix` (chain fragments), `runtimeInputs`
   (PATH), `setup` (shell before the chain), `program` (replace the package
   being wrapped, innermost contributor first), `envNames` (variables its chain
   introduces, handed to every contributor as `ctx.forwarded` so one that
   scrubs the environment can pass them on), `context` (anything else it needs,
   e.g. its own libraries), and `incompatible` (core fields its shape cannot
   honor — an error, never a silent omission). The core renders every core
   field itself, so a contributor can add to a wrapper but never drop from it.
   One shape renders every wrapper: the package tree (`symlinkJoin`) with one
   executable replaced by a stub. What a contributor contributes changes what the
   stub runs, never what the output contains — so naming one never costs
   completions, `man`, or desktop entries (see `render.nix` and `builders.nix`).
   When the target option is owned by a possibly-absent extension, guard the
   definition with `lib.optionalAttrs (options.<path> ? <name>)` — a plain
   definition (or even `mkIf false`) against an undeclared option is an
   evaluation error.
8. Publishing. Anything a consumer is meant to read goes through
   `substrate.publish`, and core turns it into an output. An extension does not
   write its own output builder: it declares a key under `substrate.publish`
   with a type that fits, then registers where the key lands in
   `substrate.settings.publishers` as `{ scope = "global" | "perSystem";
   output; build; }`. `build` receives the standard output-builder context and
   reads its key off `substrate`. One key is one namespace reaching one output
   in one scope; a value belonging under two output names keeps its extra
   output builder directly, the way any module can (published packages are the
   case that does — `packages` output plus a `packages` overlay under
   `overlays`). `substrate.publish` is a strict submodule, so assigning a key
   whose extension is absent is an error naming the key rather than a value that
   reaches no output. Core declares `substrate.publish.substrateModules` itself,
   the marker for "my module tree is a library another configuration can
   consume" — a consumer assigns it straight into `substrate.modules`, which
   merges, so the tree *is* the namespace. Types for published module sets come
   from `substrate.lib.publishedModuleType`; `deferredModule` alone rejects
   function modules, which real module sets contain.

Core must remain implementation-agnostic: hooks are named after core
concepts (hosts, users, package sets), never after specific builders or
targets. `substrate.settings/systems/nixpkgsConfig` and
`substrate.<hosts|users>.<name>.nixpkgsConfig` are core-level package-set
vocabulary (like `systems` itself), honored by whichever builder creates
package sets.
Extensions resolve flake inputs by role via
`slib.resolveInput "<role>" coreInputs`. `coreInputs` is
`inputs.substrate.inputs` from the consumer's view — substrate's own locked
input set — and falls back to the consumer's flake-shaped `inputs` attrset
where substrate is not one of their inputs. Consumers shape `coreInputs`
exclusively via
`inputs.substrate.inputs.<role>.follows` (override a substrate pin) or
`inputs.substrate.inputs.<role>.url` (add a role, e.g. for a third-party
extension). `coreInputs` is internal-only and is never passed into user
modules. The consumer's `inputs` attrset is the user-facing set: builders,
extension contexts, and class modules all receive it as `inputs`. Substrate
never reads the consumer's `inputs` for role resolution.
`substrate.lib` is internal plumbing for builders/extensions; it must never
be passed into host/user modules.

### Builders

Builders integrate substrate with build systems: flake-parts, a bare flake
(`flake`), and a plain attrset (`raw`, the same function as `flake`).
`builders/common.nix` holds everything a builder shares — evaluating the
configuration, resolving the nixpkgs role, building a package set per system,
and merging the output builders registered for a name. A builder supplies a
`lib` and the shape it returns, and walks `outputs.global` and
`outputs.perSystem` itself; `default.nix`'s `wrapBuilder` imports `./core` for
it. Two things a builder must not get wrong, because nothing else fails loudly
if they are wrong: bake `settings.overlays` and `settings.nixpkgsConfig` into
every package set it builds, and walk `outputs.perSystem` as well as
`outputs.global` (that walk is what runs core's configuration checks).
`tests/builders/conformance-test.nix` runs one body against every builder;
add a new builder there as well as in `default.nix`.

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
2. Register finder: `config.substrate.moduleFinders.<name>.find = cfgs: ...`
3. Optionally set as default: `config.substrate.settings.modulesFinder = "<name>"`
4. Widen `settings.modulesFinder`'s `type` — **only `type`**. Core already declares it,
   and redefining `description` or `default` makes `lib/modules.nix` throw
   "already declared" the first time the option is forced. `enum` supports type
   merging (`binOp` unions the allowed names), so adding one is safe:
   ```nix
   settings.modulesFinder = lib.mkOption { type = lib.types.enum [ finderName ]; };
   ```

`find` receives a list of configs and is called once per builder, sometimes twice for
the same host: NixOS hosts call it with `[hostcfg]` and again with `[hostcfg] ++
userConfigs` (`extensions/nixos/default.nix`), Home Manager with `[hostcfg usercfg]`. A
finder must derive its own roots from whatever configs it is handed rather than
assuming a particular shape.

Because `find` is only reached through `slib.findModulesForClass`, a finder whose option
declarations are wrong can still pass tests that call `moduleFinders.<name>.find`
directly. Cover `findModulesForClass` in at least one test.

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
