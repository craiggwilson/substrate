# Substrate

A Nix module framework for building flakes — or plain attrsets — with modular,
extensible configuration management.

Substrate organizes NixOS and Home Manager configuration into a single module
tree, and selects only the modules each host or user actually needs before
anything is evaluated.

Published docs: https://craiggwilson.com/substrate/

```nix
substrate.modules.programs.git = {
  nixos = { ... };        # merged into NixOS system configurations
  homeManager = { ... };  # merged into Home Manager user configurations
  generic = { ... };      # merged into every class's configuration
};
```

## Why

Substrate grew out of a personal setup that had been using a tags-based
approach for years: every module was imported into every build and disabled
based on tags. That works, but importing everything and throwing most of it
away makes evaluation slow — and it gets slower with every module added.

Substrate flips that around. Instead of importing everything and disabling,
a [finder](./docs/src/concepts.md#finders) selects the modules that match
before they ever enter a configuration. Modules that don't apply to a host or
user are never evaluated.

The other goals:

- **One place per concern.** A module's NixOS, Home Manager, and shared
  configuration live side by side in one tree, instead of being split across
  separate `nixos/` and `home-manager/` module directories that have to be
  kept in sync by hand.
- **Works with and without flakes.** The flake-parts builder is one option,
  not a requirement. The `raw` builder produces the same outputs as a plain
  attrset, driven by an `inputs` attrset from npins, niv, or a flake — see
  [raw Builder](./docs/src/builders.md#raw-builder).
- **Not tied to any build system.** Builders are pluggable; flake-parts and
  raw are just the first two. Core knows about hosts, users, and package
  sets — never about a specific builder.

## Inspirations

Substrate is in the same family as the
[dendritic pattern](https://github.com/mightyiam/dendritic) and its
implementations and libraries, such as
[dendrix](https://github.com/denful/dendrix) and the other
[denful](https://github.com/denful) projects. Those are worth a look, and
substrate borrows the spirit: many small modules, each owning one concern,
composed into per-host and per-user configurations.

It differs in a few deliberate ways:

- **No flake-parts requirement.** Dendritic setups are built on flake-parts;
  substrate treats the build system as an implementation detail behind the
  builder interface.
- **No shape constraints on the module tree.** Some of these libraries
  restrict what may appear on the path to a leaf module; substrate allows any
  number of intermediate nodes, and leaf detection is simply "has class keys
  (`nixos`, `homeManager`, `generic`)".
- **Finders as a first-class interface.** Module selection is pluggable —
  tag-based filtering is one finder, "include everything" is another, and
  writing your own is a one-liner.

Honestly, the biggest reason substrate exists is that building things is fun.
It was written for personal use; if someone else finds it useful, great.

## Quick Start

With flakes and flake-parts:

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

Without flakes (npins example):

```nix
# default.nix
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

## Documentation

Documentation is an [mdBook](https://rust-lang.github.io/mdBook/), built with a
generated option reference and a link check:

```bash
nix build .#docs   # HTML at result/book/index.html
```

The published book lives at https://craiggwilson.com/substrate/.

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
