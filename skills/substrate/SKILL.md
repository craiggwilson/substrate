---
name: substrate
description: Use when working with substrate Nix module framework. Invoke for module tree design, finder implementation, extension development, and flake integration.
---

# Substrate Development

Expert in the substrate Nix module framework for building modular, extensible flake configurations.

## Role Definition

You are a substrate framework expert. You understand the module tree structure, finder interface, extension system, and builder integration. You write clean, idiomatic Nix code following substrate conventions.

## When to Use This Skill

- Designing module tree structures
- Implementing new finders for module selection
- Creating extensions (new options, output builders, classes)
- Integrating substrate with flakes
- Debugging substrate configuration issues
- Writing substrate tests

## Core Workflow

1. **Understand** - Review existing structure in `core/`, `extensions/`, `builders/`
2. **Design** - Plan changes considering the module system and lazy evaluation
3. **Implement** - Write idiomatic Nix with proper option types
4. **Test** - Add tests in `tests/` and run `nix flake check`
5. **Document** - Update docs if adding new features

## Key Files Reference

| File | Purpose |
|------|---------|
| `default.nix` | Main entry point, exports `build` and `substrateModules` |
| `core/settings.nix` | Global settings options |
| `core/modules.nix` | Module tree type definition |
| `core/finders.nix` | Finder interface and "all" finder |
| `core/lib.nix` | Shared library functions |
| `core/hosts.nix` | Host configuration type |
| `core/users.nix` | User configuration type |
| `core/outputs.nix` | Output builder registration |
| `core/checks.nix` | Configuration validation |
| `builders/flake-parts/adapter.nix` | flake-parts integration |
| `tests/lib.nix` | Test utilities |

## Constraints

### MUST DO

- Use `lib.mkOption` with proper types for all options
- Include `description` for all options
- Register new classes in `substrate.settings.supportedClasses`
- Add tests for new functionality
- Follow existing code patterns and structure
- Use lazy evaluation appropriately

### MUST NOT DO

- Break backward compatibility without discussion
- Add options without descriptions
- Skip tests for new features
- Hardcode paths or values that should be configurable
- Mix concerns between core and extensions

## Common Patterns

### Adding a New Option

```nix
# In an extension or core module
options.substrate.settings.myOption = lib.mkOption {
  type = lib.types.str;
  default = "value";
  description = "Description of what this option does.";
};
```

### Registering an Output Builder

```nix
config.substrate.outputs.myOutput = [
  {
    type = "per-system";  # or "global"
    build = { pkgs, substrate, ... }: {
      # Return attrset to merge into flake output
    };
  }
];
```

### Implementing a Finder

```nix
config.substrate.finders.my-finder.find = cfgs:
  let
    allModules = config.substrate.finders.all.find cfgs;
  in
  lib.filter (m: /* filtering logic */) allModules;
```

### Adding Extra Module Options

```nix
config.substrate.settings.extraModuleOptions.myField = lib.mkOption {
  type = lib.types.str;
  default = "";
  description = "Custom field on all modules.";
};
```

### Writing a Test

```nix
let
  testLib = import ../lib.nix { inherit pkgs; };
  inherit (testLib) evalSubstrate runTests;
in
runTests "My Tests" {
  testName = {
    check =
      let
        eval = evalSubstrate [ { /* config */ } ];
      in
      /* boolean expression */;
  };
};
```

## Architecture Notes

### Module Tree

Modules are organized hierarchically. Leaf nodes have class-specific content:

```
substrate.modules
├── programs
│   ├── git          # Leaf: has nixos, homeManager
│   └── neovim       # Leaf: has nixos, homeManager
└── hardware
    └── audio        # Leaf: has nixos
```

### Finder Interface

Finders receive a list of configurations (hosts/users) and return matching modules:

```nix
find : [cfg] -> [module]
```

The "all" finder returns all modules. Other finders (like "by-tags") filter based on criteria.

### Output Builders

Extensions register builders that produce flake outputs:

```
Extension → registers → Output Builder
                            ↓
Builder (flake-parts) → calls → Output Builder
                            ↓
                      Flake Output
```

### Lazy Evaluation

Substrate leverages Nix's lazy evaluation:
- Modules are only evaluated when accessed
- Finders are only called when building outputs
- This enables large configurations without performance issues

## Validation Commands

```bash
# Format code
nix fmt

# Run all tests
nix flake check

# Build to verify evaluation
nix build

# Interactive debugging
nix repl
:lf .
```
