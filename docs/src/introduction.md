# Introduction

Substrate is a modular framework for building Nix flakes with extensible
configuration management.

It provides a structured approach to organizing NixOS and Home Manager
configurations through:

- **Hosts and Users** — Define machines and user profiles with typed
  configuration
- **Modules** — Organize configuration into a tree structure with class-based
  outputs (`nixos`, `homeManager`, `generic`)
- **Finders** — Pluggable module discovery and filtering, e.g. tag-based
  inclusion
- **Extensions** — Add capabilities like overlays, packages, shells, secrets
  and custom types
- **Builders** — Integrate with build systems like flake-parts

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
        settings.tags = [
          "core"
          "desktop"
          "laptop"
        ];

        users.alice.tags = [ "desktop" ];

        hosts.myhost = {
          system = "x86_64-linux";
          users = [ "alice" ];
          tags = [ "laptop" ];
        };

        modules.programs.git = {
          tags = [ "core" ];
          homeManager =
            { pkgs, ... }:
            {
              programs.git.enable = true;
            };
        };
      };
    };
}
```

## Where to go next

If you are new to substrate, read
[Getting Started](getting-started.md), which walks through installation and a
first configuration. [Core Concepts](concepts.md) then explains the mental
model — hosts, users, modules, finders and output builders — that the rest of
the book assumes.

If you are extending substrate, start with the
[extension overview](extensions/index.md), which describes the composition
hooks extensions use to integrate with each other, then read
[Writing an Extension](extensions/writing.md).