# Builders

Builders integrate substrate with a build system. Each builder decides how
to interpret the output names extensions register under. Every builder does the
same work — evaluate the configuration, resolve the nixpkgs role, build a
package set per system, call the registered output builders, and merge their
results — so they differ only in where they get a `lib` from and in the shape
they return.

## Available Builders

| Builder | Description |
|---------|-------------|
| `with-flake-parts` | Integration with flake-parts |
| `flake` | Plain flake, no flake-parts dependency |
| `raw` | Plain attrset, no flake required |

`flake` and `raw` are the same function under two names. Use `flake` from a
`flake.nix` and `raw` from a non-flake `default.nix`; both return the same
attrset.

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│  Your entry point                                             │
│                                                               │
│    flake.nix          flake.nix + flake-parts       default.nix│
│       │                        │                        │      │
│       ▼                        ▼                        ▼      │
│    build.flake     build.with-flake-parts         build.raw  │
└───────────────────────────────┬───────────────────────────────┘
                                ▼
┌───────────────────────────────────────────────────────────────┐
│  builders/common.nix        the flake-parts adapter instead,   │
│                             for that one builder              │
│                                                               │
│    • evaluates or reads the substrate configuration           │
│    • resolves the nixpkgs role from coreInputs                │
│    • builds one package set per system, with                  │
│        overlays = settings.overlays                           │
│        config  = settings.nixpkgsConfig                       │
│    • merges the builders registered for each output name      │
└───────────────────────────────┬───────────────────────────────┘
                                ▼
┌───────────────────────────────────────────────────────────────┐
│  substrate.outputs                                             │
│                                                               │
│    global      nixosConfigurations, homeConfigurations,       │
│                overlays, nixosModules, …    invoked once      │
│                                                               │
│    perSystem   packages, devShells, checks   once per system  │
└───────────────────────────────┬───────────────────────────────┘
                                ▼
┌───────────────────────────────────────────────────────────────┐
│  Output builders, registered by the extensions you imported   │
│                                                               │
│    nixos ─────────────────────▶ NixOS configurations          │
│    home-manager ──────────────▶ Home Manager configurations   │
│    packages, shells ─────────▶ derivations                   │
│    overlays, published-modules                                │
│    core ─────────────────────▶ configuration checks          │
└───────────────────────────────┬───────────────────────────────┘
                                ▼
                  The builder's shape: a flake output
                  attrset, or the same thing unwrapped
```

The last box is why a builder is so small: extensions declare what an output
name means and core routes the calls, so a builder never needs to know which
extensions are loaded. It walks `substrate.outputs` and returns a shape.

The one structural difference between the builders is where the configuration
is evaluated. `flake` and `raw` evaluate it themselves, via
`common.nix`'s `fromModule`. `with-flake-parts` is itself a flake-parts
module: flake-parts owns the module system and evaluates everything together,
so substrate reads the result afterwards via `fromConfig`. That is why the
flake-parts builder is an adapter plus a configuration module rather than a
function, and why substrate options can be set alongside other flake-parts
options in one module.

## Output shape

Every builder names its outputs the same way. Global outputs sit at the top
level:

- `nixosConfigurations.<hostname>`
- `homeConfigurations.<user>@<host>` (home-only hosts only)
- `overlays.<name>`
- `nixosModules.<name>`, `homeManagerModules.<name>`, `substrateModules.<name>`

Per-system outputs are keyed by system under their own name, once for each
system in `substrate.settings.systems`:

- `packages.<system>.<name>`
- `devShells.<system>.<name>`
- `checks.<system>.<name>`

`with-flake-parts` produces these through flake-parts' `perSystem` and `flake`
options. The plain builders place both maps at the top level, where a name
claimed by both global and per-system is an error rather than a silent
overwrite.

A builder's `build` function receives the context its category dictates — see
[Output Builders](concepts.md#output-builders).

## Input contract

Every builder takes two input sets:

- `coreInputs` — flake-shaped inputs substrate resolves its own extension
  dependencies from (`nixpkgs`, `home-manager`, `jail-nix`, …). It defaults to
  `inputs.substrate.inputs` when substrate is one of `inputs` — substrate's own
  locked inputs, with any `follows` already applied — and to `inputs`
  otherwise.
- `inputs` — the consumer's flake-shaped inputs, passed unchanged to builders,
  extension contexts, and user modules as the `inputs` module argument.

Values must have `outPath` and at least one of `outputs` or `lib`. Non-flake
sources from pin tools are adapted with
[with-inputs](https://github.com/denful/with-inputs) before being passed to
substrate; passing a value without `outPath` and `outputs`/`lib` causes
`substrate.lib.resolveInput` to throw guidance pointing to with-inputs and this
document.

Consumers shape `coreInputs` exclusively through `inputs.substrate.inputs`:
`follows` overrides a substrate pin, `url` adds a role for a third-party
extension. Your own `inputs.<role>` is never read for role resolution; it
reaches your modules as the `inputs` module argument. That means
`coreInputs.nixpkgs` (substrate's own `nixpkgs-unstable` pin) and
`inputs.nixpkgs` are independent by default — two separate evaluations. Add
`inputs.substrate.inputs.nixpkgs.follows = "nixpkgs";` when you want one
nixpkgs across everything substrate builds.

Pass `coreInputs = inputs` to resolve roles against the consumer's set instead.
That is what you want when substrate's locked inputs are not there to be
resolved — a pin tool whose substrate source cannot resolve its own transitive
inputs leaves `inputs.substrate.inputs` as `{ self; }`.

[with-inputs](https://github.com/denful/with-inputs) converts npins, niv,
lon, and similar sources into flake-shaped inputs, including real flake
semantics such as `follows` and nested inputs. Because the conversion happens
once in your pin file, substrate's role-name coupling disappears: pass the
converted inputs through and extensions resolve them by role without knowing
where they came from.

## Configuration checks

Extensions add validation checks to `substrate.settings.checks`. Each entry
needs `name`, `valid` and `message`; `warn` (default `false`) makes a failure a
warning instead of an error:

```nix
substrate.settings.checks = [
  {
    name = "every host has a user";
    valid = lib.all (h: h.users != [ ]) (lib.attrValues config.substrate.hosts);
    warn = false;
    message = "some host has no user";
  }
];
```

Core registers a per-system output builder that turns them into one check
derivation printing a pass/warn/fail summary, so every builder emits
`checks.<system>.substrate-config` and the same validation runs whichever you
pick:

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

Run it with:

```bash
nix build .#checks.x86_64-linux.substrate-config       # flake
nix build -f . checks.x86_64-linux.substrate-config    # plain attrset
```

Under a flake it runs as part of `nix flake check`, because `checks` is an
output name the flake schema already understands.

## System nixpkgs pin

NixOS systems set `nixpkgs.flake.source` to the nixpkgs input, exactly as
nixpkgs' flake entry point does — so the deployed system pins its own nixpkgs
in `/etc/nix/registry.json` and NIX_PATH, and `<nixpkgs>` on the machine
resolves to the nixpkgs the system was built with. This adds the nixpkgs source
to the system closure; opt out with `nixpkgs.flake.source = lib.mkForce null;`
in any NixOS module.

## flake-parts Builder

Integrates with [flake-parts](https://flake.parts/). The builder is a thin
adapter: `builders/flake-parts/default.nix` wraps `flake-parts-lib.mkFlake`,
hands substrate's core modules to it, and `builders/flake-parts/adapter.nix`
turns substrate's registered outputs into flake-parts' `perSystem` and `flake`
options.

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

## flake Builder

Substrate's outputs are already a valid flake output set, so the plain builder
works as a `flake.nix` with no build-system dependency at all:

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    substrate.url = "github:craiggwilson/substrate";
  };

  outputs = inputs: inputs.substrate.build.flake { inherit inputs; } ./config.nix;
}
```

That is the whole builder. `nix flake check`, `nix develop`, and
`nix build .#nixosConfigurations.myhost.config.system.build.toplevel` all work,
because the attrset it returns is the flake output schema — and flake validates
the parts of it that have a required shape. `checks.<system>.*`,
`devShells.<system>.*` and `packages.<system>.*` must be derivations,
`nixosConfigurations.<name>.config.system.build.toplevel` must be a derivation,
and `overlays.<name>` must be overlays. Names outside the schema are ignored.

To add outputs the flake schema has no place for — a `formatter`, an `apps`
set, `hydraJobs` — merge them with the builder's result:

```nix
outputs =
  inputs:
  inputs.substrate.build.flake { inherit inputs; } ./config.nix
  // {
    formatter = inputs.nixpkgs.legacyPackages.${builtins.currentSystem}.nixpkgs-fmt;
  };
```

## raw Builder

The plain builder under the name a non-flake `default.nix` reaches for. Use it
when you evaluate substrate without a flake, or when you manage inputs with a
pin tool such as [npins](https://github.com/xzfc/npins) or
[niv](https://github.com/nmattia/niv). The result is the same attrset `flake`
returns, reached through `nix build -f .` instead of `nix build`.

### Usage

For a repository that already has a `flake.nix`, use
[flake-compat](https://github.com/edolstra/flake-compat) to reuse the flake's
locked and resolved inputs:

```nix
# default.nix
let
  flake = (import flake-compat { src = ./.; }).defaultNix;
  substrate = import flake.inputs.substrate;
in
substrate.build.raw {
  inputs = flake.inputs;
} {
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

For a repository without a flake, use
[with-inputs](https://github.com/denful/with-inputs) to convert npins/niv
sources into flake-shaped inputs:

```nix
# default.nix with npins
let
  sources = import ./npins;   # npins add github denful with-inputs
  withInputs = import sources.with-inputs;
  substrate = import sources.substrate;
in
substrate.build.raw {
  inputs = withInputs sources { } (i: i);
} {
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

### Non-flake build recipes

Build and activate a NixOS system:

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

Run the configuration checks:

```bash
nix build -f . checks.x86_64-linux.substrate-config
```

## Creating Custom Builders

A builder's job is small, because `builders/common.nix` already holds the part
that has nothing to do with the build system: evaluating the configuration,
resolving the nixpkgs role, building a package set per system, and merging the
output builders registered for a name. What a builder adds is a `lib` and the
shape it returns.

`common.nix` exposes three entry points, named for where the configuration
comes from:

| Entry point | Use it when |
|-------------|-------------|
| `fromConfig { lib, inputs, coreInputs, substrate }` | your builder is itself a module system and already has an evaluated `substrate` config — this is what the flake-parts adapter uses |
| `fromModule { lib, inputs, module, coreInputs ? … }` | you need to evaluate a module yourself — this is what `builders/plain.nix` uses |
| `defaultCoreInputs inputs` | the default for `coreInputs`, i.e. `inputs.substrate.inputs or inputs` |

The first two end in the same place: `fromModule` evaluates and then calls
`fromConfig`. Either way you get the context every output builder receives
(`globalArgs`, `perSystemArgs`), the `merge` helper, `pkgsFor` as a function of
system, and `outputs`/`settings`. Walk the two maps however your build system
wants them and return whatever shape it expects. `builders/plain.nix` is the
smallest complete example:

```nix
let
  c = (import ./common.nix).fromModule { inherit lib inputs module; };
  global = lib.mapAttrs (_: builders: c.merge c.globalArgs builders) c.outputs.global;
  perSystem = lib.mapAttrs (
    _: builders: lib.genAttrs c.settings.systems (system: c.merge (c.perSystemArgs system (c.pkgsFor system)) builders)
  ) c.outputs.perSystem;
in
global // perSystem
```

Two things to get right, both of which the conformance test
(`tests/builders/conformance-test.nix`) holds you to:

- **Bake `settings.overlays` and `settings.nixpkgsConfig` into every package
  set you build.** `pkgsFor` does both. Skip it and packages disappear from
  NixOS and Home Manager configurations with no error anywhere.
- **Walk `outputs.perSystem`, not just `outputs.global`.** That is what makes
  core's configuration checks run; a builder that skips it silently drops
  validation.

Add the builder to `build` in `default.nix`:

```nix
{
  build = {
    with-flake-parts = wrapBuilder (import ./builders/flake-parts/default.nix);
    flake = wrapBuilder plain;
    raw = wrapBuilder plain;
    with-my-builder = wrapBuilder (import ./builders/my-builder);
  };
}
```

`wrapBuilder` is what imports `./core`, so a builder never does that itself.
Add it to the conformance test's `builders` attrset at the same time — that is
the whole registration cost for a new build system.
