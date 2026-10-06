# Substrate

A modular framework for building Nix flakes with extensible configuration management.

## Overview

Substrate provides a structured approach to organizing NixOS and Home Manager configurations through:

- **Hosts and Users** - Define machines and user profiles with typed configuration
- **Modules** - Organize configuration into a tree structure with class-based outputs (nixos, homeManager, generic)
- **Finders** - Pluggable module discovery and filtering (e.g., tag-based inclusion)
- **Extensions** - Add capabilities like overlays, packages, shells, and custom types
- **Builders** - Integrate with build systems like flake-parts

## Quick Start

Add substrate as a flake input:

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
      imports = [
        inputs.substrate.substrateModules.home-manager
        inputs.substrate.substrateModules.nixos
        inputs.substrate.substrateModules.tags
      ];

      substrate = {
        settings.tags = [ "core" "desktop" "laptop" ];

        users.alice = {
          tags = [ "desktop" ];
        };

        hosts.myhost = {
          system = "x86_64-linux";
          users = [ "alice" ];
          tags = [ "laptop" ];
        };

        modules.programs.git = {
          tags = [ "core" ];
          homeManager = { pkgs, ... }: {
            programs.git.enable = true;
          };
        };
      };
    };
}
```

## Documentation

Documentation is an [mdBook](https://rust-lang.github.io/mdBook/), built with a
generated option reference and a link check:

```bash
nix build .#docs   # HTML at result/book/index.html
```

Or read it as plain Markdown under [docs/src](./docs/src/):

- [Introduction](./docs/src/introduction.md) - Overview and quick start
- [Getting Started](./docs/src/getting-started.md) - Installation and first configuration
- [Core Concepts](./docs/src/concepts.md) - Hosts, users, modules, finders, builders
- [Extensions](./docs/src/extensions/index.md) - Available extensions and composition hooks
- [Builders](./docs/src/builders.md) - Build system integration
- [Testing](./docs/src/testing.md) - Running and writing tests

## Running Tests

```bash
nix flake check
```

## License

MIT - see [LICENSE](./LICENSE)
