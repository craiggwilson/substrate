# Extensions

Extensions add capabilities to substrate. Import only what you need.

## Available Extensions

| Extension | Import Path | Description |
|-----------|-------------|-------------|
| `bubblewrap` | `substrateModules.bubblewrap` | Bubblewrap isolation via jail.nix |
| `home-manager` | `substrateModules.home-manager` | Home Manager configuration builder |
| `nixos` | `substrateModules.nixos` | NixOS configuration builder |
| `overlays` | `substrateModules.overlays` | Overlay management |
| `packages` | `substrateModules.packages` | Package definitions |
| `published-modules` | `substrateModules.published-modules` | Publishes your own modules under named outputs |
| `secrets` | `substrateModules.secrets` | Declarative secrets via SecretSpec |
| `shells` | `substrateModules.shells` | Development shells |
| `tags` | `substrateModules.tags` | Tag-based module filtering |
| `wrappers` | `substrateModules.wrappers` | Declarative executable wrapping (`wrap` module argument) |

## Composition Hooks

Core provides push-based hooks so extensions integrate with each other's
builders without either side referencing the other:

| Option | Context received by each function | Consumed by |
|--------|-----------------------------------|-------------|
| `substrate.settings.extraArgsGenerators` | `{ hostcfg, usercfg, inputs, pkgs }` | All module builds — merged results become module arguments |
| `substrate.settings.contributors` | per-entry class: host classes `{ inputs, substrate, hostname, hostcfg, userConfigs, pkgs }`, user classes `{ inputs, substrate, userName, usercfg, pkgs }` | Only the builder that speaks the entry's `class` (e.g., `nixos` extension for `"nixos"`) |
| `substrate.settings.wrappers.contributors` | `{ config, hostcfg, usercfg, inputs, pkgs, lib, wrapLib, forwarded }`, then the whole resolved spec | The `wrappers` extension — each entry at key `foo` adds what it contributes to any wrapper that names `foo.*` (e.g., `jail` registers `bubblewrap` → `wrap { bubblewrap.permissions = …; }`) |

Each contributor entry declares the `class` it targets and a `contribute`
function returning a list of modules, appended to the builder's module list;
builders select entries via `substrate.lib.contributionsFor`. Contribute
function patterns should end with `...` to tolerate extra context fields. An
extension targeting several classes registers one entry per class, and
contributions for classes with no enabled builder are simply never loaded.
`extraArgsGenerators` entries return
attrsets; each key is passed into modules as an argument of the same name.
`pkgs` matches the build target (host system pkgs for host builds, user
system pkgs for user builds), so helpers can be returned fully bound to
`pkgs`.

Both avenues stay open, and which one an argument uses is a property of what it
depends on. A generator runs in the builder, *outside* the configuration being
built, so everything it receives is build context — an argument that needs the
configuration it belongs to cannot come from one. A class module is defined
*inside* the configuration, so it can close over `config`; that is how `wrap`
reads the options declared beside it (see [Contributors](wrappers.md#contributors)). nixpkgs passes argument values through verbatim rather than
applying them, so a generator cannot hand over a closure to be called later
either.

`wrappers.contributors` is the same push pattern one level down: an *extension*
extends another extension's API. The `wrappers` extension owns the `wrap`
module argument but never references `jail-nix`; the `jail` extension registers
a contributor, and `wrap.package { bubblewrap.permissions = …; }` is only valid when
`jail` is loaded. A contributor declares its own `options` (validated by
`wrappers`, so error messages stay consistent) and what it contributes to a
wrapper — chain fragments, `PATH` entries, or a different program to wrap. Its
hooks receive the configuration the wrapper is built for, which is what lets a
contributor read the options declared next to it.
