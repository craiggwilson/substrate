# Extensions

Extensions add capabilities to substrate. Import only what you need.

## Available Extensions

| Extension | Import Path | Description |
|-----------|-------------|-------------|
| `home-manager` | `substrateModules.home-manager` | Home Manager configuration builder |
| `nixos` | `substrateModules.nixos` | NixOS configuration builder |
| `tags` | `substrateModules.tags` | Tag-based module filtering |
| `theming` | `substrateModules.theming` | Palettes, app theme adapters, runtime theme switcher |
| `overlays` | `substrateModules.overlays` | Overlay management |
| `packages` | `substrateModules.packages` | Package definitions |
| `secrets` | `substrateModules.secrets` | Declarative secrets via SecretSpec |
| `wrappers` | `substrateModules.wrappers` | Declarative executable wrapping (`wrap` module argument) |
| `shells` | `substrateModules.shells` | Development shells |
| `jail` | `substrateModules.jail` | Jail/container support |
| `types` | `substrateModules.types` | Custom type definitions |

## Composition Hooks

Core provides push-based hooks so extensions integrate with each other's
builders without either side referencing the other:

| Option | Context received by each function | Consumed by |
|--------|-----------------------------------|-------------|
| `substrate.settings.extraArgsGenerators` | `{ hostcfg, usercfg, inputs, pkgs }` | All module builds — merged results become module arguments |
| `substrate.settings.contributors` | per-entry class: host classes `{ inputs, substrate, hostname, hostcfg, userConfigs, pkgs }`, user classes `{ inputs, substrate, userName, usercfg, pkgs }` | Only the builder that speaks the entry's `class` (e.g., `nixos` extension for `"nixos"`) |
| `substrate.settings.wrappers.backends` | `{ pkgs }` at module-arg generation; then the backend's validated spec | The `wrappers` extension — each entry at key `foo` surfaces as the callable `wrap.withFoo` (e.g., `jail` registers `bubblewrap` → `wrap.withBubblewrap`) |

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

`wrappers.backends` is the same push pattern one level down: an *extension*
extends another extension's API. The `wrappers` extension owns the `wrap`
module argument but never references `jail-nix`; the `jail` extension registers
a backend, and `wrap.withBubblewrap` appears only when `jail` is loaded. A backend
declares the `keys` its spec accepts (validated by `wrappers`, so error
messages stay consistent) and a `build` function that turns the spec into a
derivation.

## Home Manager Extension

Generates `homeConfigurations` flake output.

### Import

```nix
imports = [ inputs.substrate.substrateModules.home-manager ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.homeManagerModules` | list | External HM modules to include |
| `substrate.users.<name>.nixpkgsConfig` | attrs | Extra nixpkgs config for this user's host-scoped package sets (merged under the host's) |

Host-scoped builds import a package set with
`substrate.settings.nixpkgsConfig` merged with the user's `nixpkgsConfig` and
the host's. Users on system hosts share the host's package set instead (HM
`useGlobalPkgs`).

### Output

- `homeConfigurations.<user>@<host>` - Home Manager for users of `usersOnly` hosts.
  There is no host-less variant: users of system hosts are delivered through
  NixOS integration.

### NixOS Integration

When the NixOS extension is also loaded, this extension automatically
integrates Home Manager into every host configuration by registering a
`class = "nixos"` contributor (`home-manager.users.<name>` etc. with your
`homeManager`-class modules). The nixos extension has no knowledge of this
integration; it simply appends the contributors whose class it speaks.

### Usage

```nix
substrate.users.alice = {
  system = "x86_64-linux";
};

substrate.modules.programs.git = {
  homeManager = { ... }: {
    programs.git.enable = true;
  };
};
```

## NixOS Extension

Generates `nixosConfigurations` flake output.

### Import

```nix
imports = [ inputs.substrate.substrateModules.nixos ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.nixosModules` | list | External NixOS modules to include |
| `substrate.hosts.<name>.usersOnly` | bool (default `false`) | Home-only host: no system built; users get host-scoped Home Manager configs |
| `substrate.hosts.<name>.nixpkgsConfig` | attrs | Extra nixpkgs config for this host's package set |

Host package sets are created once per distinct `(system, nixpkgs config)`
combination — `substrate.settings.nixpkgsConfig` merged with the host's
`nixpkgsConfig` — and handed to `nixosSystem` via `nixpkgs.pkgs`, so the
configuration's `pkgs` and the `pkgs` given to `extraArgsGenerators` are the
same value. Because the package set is fixed at creation, set nixpkgs config
through these options; modules that assign `nixpkgs.config` directly are
rejected by nixpkgs' own assertion. `nixpkgs.overlays` set by external
modules is still honored (appended onto the package set).

### Output

- `nixosConfigurations.<hostname>` - NixOS system configurations

### Usage

```nix
substrate.hosts.workstation = {
  system = "x86_64-linux";
  users = [ "alice" ];
};

substrate.modules.hardware.audio = {
  nixos = { ... }: {
    sound.enable = true;
    hardware.pulseaudio.enable = true;
  };
};
```

## Tags Extension

Provides tag-based module filtering.

### Import

```nix
imports = [ inputs.substrate.substrateModules.tags ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.tags` | list | Available tags |
| `substrate.hosts.<name>.tags` | list | Tags for a host |
| `substrate.users.<name>.tags` | list | Tags for a user |
| `substrate.modules.<path>.tags` | list | Tags required for a module |

### Tag Types

**Simple tags:**
```nix
substrate.settings.tags = [ "core" "desktop" "laptop" ];
```

**Metatags with implications:**
```nix
substrate.settings.tags = [
  "laptop"
  "portable"
  { "hardware:dell" = [ "laptop" "portable" ]; }
];
```

When a host/user has `hardware:dell`, they automatically get `laptop` and `portable`.

### Hierarchical Tags

Tags support hierarchy via `:` separator:

```nix
substrate.settings.tags = [
  "desktop"
  "desktop:wayland"
  "desktop:wayland:hyprland"
];
```

Having `desktop:wayland:hyprland` automatically implies `desktop:wayland` and `desktop`.

### hasTag Function

The tags extension provides a `hasTag` function in specialArgs:

```nix
substrate.modules.programs.waybar = {
  tags = [ "desktop:wayland" ];
  homeManager = { hasTag, ... }: {
    programs.waybar = {
enable = true;
settings = {
  mainBar = {
    modules-left = [ "hyprland/workspaces" ];
    # Conditionally add battery module
    modules-right = 
      (if hasTag "laptop" then [ "battery" ] else [])
      ++ [ "clock" ];
  };
};
    };
  };
};
```

## Overlays Extension

Manages nixpkgs overlays.

### Import

```nix
imports = [ inputs.substrate.substrateModules.overlays ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.overlays` | list | Overlays to apply |

### Usage

```nix
substrate.settings.overlays = [
  (final: prev: {
    myPackage = prev.callPackage ./pkgs/my-package { };
  })
  inputs.some-flake.overlays.default
];
```

## Packages Extension

Defines custom packages.

### Import

```nix
imports = [ inputs.substrate.substrateModules.packages ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.packages` | list of paths | Package definition files |
| `substrate.settings.packageNamespace` | string | Namespace in overlay (default: `custom`) |

### Output

- `packages.<system>.<name>` - Package derivations
- `overlays.packages` - Overlay adding packages under namespace

### Usage

```nix
substrate.settings = {
  packages = [
    ./pkgs/my-tool.nix
    ./pkgs/another-tool.nix
  ];
  packageNamespace = "myproject";
};
```

Package file format:
```nix
# pkgs/my-tool.nix
{ lib, pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "my-tool";
  version = "1.0.0";
  # ...
}
```

Packages are available as `pkgs.myproject.my-tool`.

## Shells Extension

Defines development shells.

### Import

```nix
imports = [ inputs.substrate.substrateModules.shells ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.shells` | attrsOf path | Shell definition files |

### Output

- `devShells.<system>.<name>` - Development shells

### Usage

```nix
substrate.settings.shells = {
  default = ./shells/default.nix;
  rust = ./shells/rust.nix;
};
```

Shell file format:
```nix
# shells/rust.nix
{ pkgs }:
pkgs.mkShell {
  packages = with pkgs; [
    rustc
    cargo
    rust-analyzer
  ];
}
```

## Jail Extension

Adds bubblewrap isolation via
[jail.nix](https://git.sr.ht/~alexdavid/jail.nix), primarily as a
`wrap.withBubblewrap` backend (see the Wrappers Extension). It also exposes the raw
pkgs-bound jail.nix callable as `jailLib` for integrations the backend does not
cover, such as `jailLib.mkOverlay`.

### Import

```nix
imports = [ inputs.substrate.substrateModules.jail ];
```

Requires a `jail-nix` input — resolved by the usual precedence: an explicit
`jail-nix` argument, `substrate.settings.inputs."jail-nix"`, or a flake input
named `jail-nix`. The `wrap.withBubblewrap` backend additionally requires the
`wrappers` extension; without it jail is available only through `jailLib`.

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.jail.basePermissions` | function or null | Base permissions all jails inherit |
| `substrate.settings.jail.additionalCombinators` | function or null | Custom combinators exposed to jail definitions |

### Wrapping in a jail

With the `wrappers` extension loaded, jail registers `wrap.withBubblewrap`. `permissions`
is passed straight to jail.nix — either a list of combinators or a function
receiving them:

```nix
{ pkgs, wrap, ... }:
{
  home.packages = [
    (wrap.withBubblewrap {
package = pkgs.firefox;
permissions = c: with c; [
  network
  gui
  (readwrite "$HOME/.mozilla")
];
    })
  ];
}
```

The backend accepts `package`, optional `name` (default
`<pkg>-isolated`), and `permissions`. To compose a jail around an already-wrapped
program, nest it like any other backend:

```nix
wrap.withBubblewrap { package = wrap.withScript { package = pkgs.foo; env.X = "1"; }; }
```

### Module argument (`jailLib`)

For overlay-style jail of whole package sets, the extension contributes a
pkgs-bound jail.nix callable as `jailLib` via `extraArgsGenerators`:

```nix
substrate.modules.overlays.jailed = {
  generic = { jailLib, ... }: {
    config = {
nixpkgs.overlays = [
  (final: prev: jailLib.mkOverlay {
    inherit final prev;
    packages = c: with c; { firefox = [ network gui gpu ]; };
  })
];
    };
  };
};
```

`jailLib` is the result of `jail-nix.lib.extend` applied with the build's
`pkgs` plus `basePermissions`/`additionalCombinators` from the options above.

## Secrets Extension

Adds declarative secrets to host and user configurations via
[SecretSpec](https://secretspec.dev). Modules declare secrets; the extension
renders a per-configuration `secretspec.toml` manifest containing declarations
only — values stay in their providers (1Password, keyring, sops, age, ...) and
are resolved at runtime, never at activation and never in the Nix store.

### Import

```nix
imports = [ inputs.substrate.substrateModules.secrets ];
```

### Options

These are top-level options, named after the tool they configure (like
`programs` or `sops`), defined in each target system's module space (NixOS
and Home Manager) and merged per configuration like any other option:

| Option | Description |
|--------|-------------|
| `secretspec.entries.<name>` | Secret declaration (description, required, default, prompt, asPath, providers, ref) |
| `secretspec.providers.<alias>` | Provider URI and optional provider credentials |
| `secretspec.scopes.<name>.secrets` | Allowlist of entries a service may receive |
| `secretspec.defaultProviders` | Fallback chain for entries without their own providers |

The generated manifest is placed at `/etc/secretspec.toml` on NixOS and
`~/.config/secretspec/secretspec.toml` under Home Manager (exported there as
`$SECRETSPEC_FILE`). `secretspec` is installed automatically; external CLIs a
provider shells out to (op, sops, age, ...) are added by the consuming
module or config as usual, keeping the extension provider-agnostic.
Every declared secret must already exist in its provider — the extension
never generates or mints values.

### Usage

```nix
# A nixos-class module declares what it needs and wraps its service:
{ pkgs, secrets, ... }:
{
  secretspec = {
    providers.team = {
      uri = "onepassword://Prod";
      credentials.service_account_token = "env";
    };
    entries.GITHUB_TOKEN = {
      description = "GitHub API token";
      providers = [ "team" ];
      ref = { item = "GitHub"; field = "token"; };
    };
    scopes.github-mcp.secrets = [ "GITHUB_TOKEN" ];
  };

  systemd.services.github-mcp = {
    serviceConfig = {
      ExecStart = secrets.run {
        scope = "github-mcp";
        cmd = "${pkgs.github-mcp}/bin/github-mcp";
      };
      # Provider bootstrap credential (see Runtime Model below):
      EnvironmentFile = "/run/secrets/provider-token.env";
    };
  };
}
```

Home Manager class modules use the same options; in shells the CLI works
directly (`secretspec get NAME`, `eval "$(secretspec export)"`) because
`$SECRETSPEC_FILE` points at the generated manifest.

### Runtime Model

- `secrets.run` wraps a command with `secretspec run` scoped to one scope;
  resolved values are injected into the child's environment at exec time.
  To layer secrets into a wrapped program, use `secrets.prefix` with the
  `wrap.withScript` backend's `prefix` option (the only built-in that supports exec
  chains).
- Entries with `asPath = true` are materialized as temporary files at
  resolution, for consumers that insist on a path.
- Manifest references are store-visible (vault/item/field names, like
  sops-nix filenames); values are not.
- Provider credentials are the bootstrap problem the extension deliberately
  does not solve: feed them via `EnvironmentFile`, the OS keyring, or
  `secretspec config provider login`.
- Scopes minimize secret delivery; they are not an authorization boundary.

## Theming Extension

Turns per-app theme wiring from a central convention into a plugin model, in
three parts:

- **Palette definitions** — pure color data (base16-required, base24-extensible),
  pushed into `substrate.settings.theming.palettes.<name>`. Any module can
  reference them.
- **App adapters** — per-program theme mappings, pushed into
  `substrate.settings.theming.apps.<name>`: `apply` (rebuild-time option
  fragments per class), `templates` (prebuilt files for live switching),
  `onSwitch` (per-theme hook scripts the switcher runs after applying).
- **Selection and switching** — `theming.active` / `theming.live` are options
  *inside each nixos/homeManager configuration* (contributed by the
  extension), never in substrate settings. Flipping `theming.active` re-renders
  every registered adapter; with `theming.live = true` a shell switcher
  (`theming switch <name>`, dconf + template symlinks + onSwitch hooks, no
  rebuild) is installed for runtime changes, applying `theming.active` at
  session start.

Adding a theme or a themed app touches only that theme's/app's module.

### Import

```nix
imports = [ inputs.substrate.substrateModules.theming ];
```

### Usage

Registry pushes (`palettes`, `apps`) happen at the **top level** of a module
file — the outer substrate evaluation, where there is no `pkgs`. Class
fragments (`generic`/`nixos`/`homeManager`) run in separate target configs
(where `theming.active` lives) and must not carry registry data: a palette
defined in a class fragment exists only in the configs that select it, while
the switcher and adapters need every registered palette in every config.
Palette package fields are `pkgs -> package` functions, resolved per target.

```nix
# modules/theming/catppuccin/default.nix — outer eval:
{
  config.substrate.settings.theming.palettes.catppuccin-mocha = {
    colors = { base00 = "1e1e2e"; /* … base0F, optional base10..base17 */ };
    dark = true;
    gtk = { name = "catppuccin-mocha"; package = pkgs: pkgs.catppuccin-gtk; };
    icon = { name = "Papirus-Dark"; package = pkgs: pkgs.papirus-icon-theme; };
  };

  # optional tagged leaf so hosts/users can select it like any module:
  config.substrate.modules.theming.catppuccin.tags = [ "theming:catppuccin" ];
}

# modules/programs/zellij/default.nix — registers its adapter:
{
  config.substrate.settings.theming.apps.zellij = {
    apply.homeManager = theme: {
      programs.zellij.themes.hdwlinux = myAdapter theme.colors;
    };
    templates = theme: {
      # farm paths: prefix with the app name so adapters never collide
      "zellij/hdwlinux.kdl" = {
        content = builtins.toJSON theme.colors.hexWithHashtag;
        dest = "$HOME/.config/zellij/themes/hdwlinux.kdl";
      };
    };
  };
}

# In the user's homeManager config (target eval):
{
  theming = {
    active = "catppuccin-mocha";
    live = true; # install the runtime switcher
  };
}
```

### Choosing an adapter pattern

| The app's theme reaches it via… | Use | Live-switchable? |
|---|---|---|
| home-manager / NixOS options (config baked into a store path) | `apply.<class>` | rebuild only |
| a file at a known path it re-reads | `templates` + `dest` | yes |
| a file it re-reads, but needs a kick (signal, restart) | `templates` + `onSwitch` | yes |
| a file in a dir it manages itself, selected by config it owns | template without `dest` + `onSwitch` consuming `$2` | yes |
| dconf/GSettings names (gtk/icon/cursor/font) | palette fields — no adapter needed | yes |
| anything unreachable at runtime (console colors…) | `apply.nixos` | rebuild only |

`apply` fragments receive the resolved palette record and return option
assignments per class; an adapter may target both classes. `onSwitch` is a
function from theme to script text (hooks can bake theme colors), rendered
into each theme farm under `onswitch/<app>` and executed with `$1` = theme
name, `$2` = that theme's farm path. Pick `apply` or `templates` per app —
pointing both at the same destination lets live switching and rebuilds fight
over the file.

```nix
# app with no-dest template + self-placing hook (e.g. btop):
config.substrate.settings.theming.apps.btop = {
  templates = theme: {
    "btop/hdwlinux.theme" = { content = btopTheme theme.colors; };  # dest = null
  };
  onSwitch = theme: "ln -sfn \"$2/btop/hdwlinux.theme\" $HOME/.config/btop/themes/ && btop-reload";
};
```

### Module argument

`theme` is added to every host/user configuration:

| Attribute | Description |
|-----------|-------------|
| `theme.palettes` | resolved palettes: `palettes.<name>.colors` is a color library (each `baseXX` a color object with `hex`/`hexWithHashtag`/`rgb`/`rgbString`/`ansi`, plus `fromHex`/`mix`/`lighten`/`darken`) |
| `theme.adapters` | the app adapter registry, for introspection |
| `theme.mkColorLib` | build a color library from raw hex attrsets directly |

Core hooks used: `extraArgsGenerators` (the `theme` arg), `contributors`
(one entry per class). Live wallpaper handling is intentionally out of scope
for v1.

## Wrappers Extension

Provides `wrap` — a pkgs-bound module argument (the `jailLib` pattern) for
declaratively wrapping executables: inject environment variables, prepend CLI
args, and chain exec prefixes. It has no options and no target modules; each
call returns a derivation you install through your usual mechanism
(`home.packages`, `environment.systemPackages`, a systemd unit, ...).

Three callables differ in **placement** (what tree the result exposes) and
**stub generator** (shell script vs compiled binary):

| Callable | Placement | Stub | Keeps completions/man/siblings? |
|----------|-----------|------|--------------------------------|
| `wrap.withShell { }` | in-place (copies the package tree) | `makeWrapper` (shell) | **Yes** — desktop `Exec=` entries are rewritten to route through the wrapper |
| `wrap.withBinary { }` | in-place (copies the package tree) | `makeBinaryWrapper` (compiled) | **Yes** — but supports no shell code (see below) |
| `wrap.withScript { }` | standalone (a lone script package) | the script *is* the package | **No** — only the wrapper script is exposed |

The bare functor — `wrap { ... }` — dispatches to the configured default
backend (`substrate.settings.wrappers.defaultBackend`, normally `"shell"`):
the in-place `makeWrapper` backend preserving the original tree, so completions,
man pages, sibling binaries, and desktop entries keep working — the safe choice
when the wrapper *replaces* a package. Set `defaultBackend = "binary"` for a
fleet of macOS-safe compiled stubs, or point it at any contributed backend;
the named callables are unaffected, and specs that use options the new default
doesn't support fail as undeclared-option errors. The two non-default built-ins
are explicit because each trades something away:

- **`wrap.withBinary { }`** emits a compiled stub (no bash, no shebang). Its
  option set is a strict subset: no `preHook` or `prefix` (the stub runs no
  shell code).
- **`wrap.withScript { }`** is a single standalone script. Nothing from the
  original package comes along, so installing it *instead of* the package loses
  completions/man/siblings unless you also install the original. In exchange it
  is the only backend with `cmd` (text wrappers with no base package), `prefix`
  (arbitrary exec-chains like `uwsm app --` or a secrets launcher), `postHook`,
  and renaming.

### Import

```nix
imports = [ inputs.substrate.substrateModules.wrappers ];
```

### Options by backend

| Option | `wrap.withShell` | `wrap.withBinary` | `wrap.withScript` | Description |
|--------|:------:|:-------------:|:------------:|-------------|
| `package` | ✓ | ✓ | ✓* | Derivation to wrap; exe resolved with `lib.getExe` |
| `env` | ✓ | ✓ | ✓* | Attrset of exported variables (shell-escaped) |
| `args` | ✓ | ✓ | ✓* | CLI args prepended before `"$@"` |
| `runtimeInputs` | ✓ | ✓ | ✓* | Packages added to the wrapper's `PATH` |
| `preHook` | ✓ | ✗ | ✓* | Shell run before the program starts |
| `postHook` | ✗ | ✗ | ✓ | Shell run after the program (its exit code propagates) |
| `prefix` | ✗ | ✗ | ✓ | Raw exec-line fragments placed before the exe (launchers, `secrets.prefix`) |
| `name` | ✗ | ✗ | ✓ | Rename the wrapper command |
| `cmd` | ✗ | ✗ | ✓ | Raw script body, no base package (needs `name`) |
| `files` | ✓ | ✓ | ✓ | Declarative files materialized into the wrapper (below) |
| `aliases` | ✓ | ✓ | ✓ | Extra `$out/bin` names symlinked to the wrapper |
| `exe` | ✓ | ✓ | ✓ | Pick a specific binary under `bin/` (when `meta.mainProgram` isn't it) |
| `postBuildHook` | ✓ | ✓ | ✗ | Shell appended to the in-place build (desktop-file surgery is automatic) |
| `passthru` | ✓ | ✓ | ✓ | Merged into the result's `passthru` |

\* package-mode; `wrap.withScript`'s text mode (`cmd`) ignores `package`/`args`/
`prefix` and requires `name`. Fields a backend doesn't declare are rejected by
the module system itself — no silent drops, no builder-time validation.

Every result also carries `passthru.wrapped` (the original package),
`passthru.override` (rebuild the wrapper around an overridden package), and
`passthru.files` (name → store path of each materialized file).

### Files

`files.<relpath>` materializes a file and links it into the wrapper output at
`$out/<relpath>`, verbatim — the "ship the config inside the derivation"
escape from `$HOME`:

```nix
wrap.withShell {
  package = pkgs.mpv;
  files."mpv.conf".text = "vo=gpu\n";
  env.MPV_CONFIG_HOME = f: f."mpv.conf";   # function values receive the files attrset
}
```

Values in `env`/`args`/`prefix` may be functions of the files attrset
(`name → resolved path`); plain values pass through untouched. A file may also
set `source = <path or drv>` instead of `text`, or override `path` with a
literal string (e.g. `"$HOME/.config/foo"`) for runtime resolution.

### Usage

```nix
{ pkgs, wrap, secrets, ... }:
let
  # in-place default: replace claude-code, keep its completions, add a flag
  claude = wrap {
    package = pkgs.claude-code;
    args = [ "--mcp-config" "$HOME/.claude/mcp-servers.json" ];
  };

  # compiled stub: macOS-safe, no shell hooks
  viewer = wrap.withBinary {
    package = pkgs.imagemagick;
    env.MAGICK_TMPDIR = "/tmp";
  };

  # standalone: prefix a launcher (uwsm), or run under secrets
  mcp = wrap.withScript {
    package = pkgs.github-mcp-server;
    prefix = [ (secrets.prefix { scope = "github-mcp"; }) ];
  };

  # text mode: no base package at all
  ff = wrap.withScript {
    name = "ff";
    cmd = ''
${pkgs.ripgrep}/bin/rg "$@" | ${pkgs.fzf}/bin/fzf
    '';
    runtimeInputs = [ pkgs.ripgrep pkgs.fzf pkgs.bat ];
  };
in
{
  home.packages = [ claude viewer mcp ff ];
}
```

### Typed definitions (`wrap.typed`)

`wrap.typed` turns a wrapper into a reusable, *typed* function from settings
to derivation. A definition without a pinned `backend` follows
`settings.wrappers.defaultBackend`. `options` declares the knobs; `spec` maps them to the backend
spec, which flows through the same validated pipeline as a plain call:

```nix
mpv = wrap.typed {
  backend = "shell";
  options = {
    package = lib.mkOption { type = lib.types.package; default = pkgs.mpv; };
    hq = lib.mkOption { type = lib.types.bool; default = false; };
    settings = lib.mkOption { type = with lib.types; attrsOf str; default = { }; };
  };
  spec = config: {
    inherit (config) package;
    files."mpv.conf".text = lib.generators.toKeyValue { } config.settings;
    env.VO = lib.optionalString config.hq "gpu";
  };
};

# the definition is a function; bad or unknown settings are eval errors
home.packages = [ (mpv { hq = true; settings.vo = "gpu"; }) ];
```

`mpv.options` is normalized for reuse in a real nixpkgs module when you want
option-tree integration (namespacing, enable flags, multi-layer merging):

```nix
{ pkgs, wrap, config, lib, ... }:
let mpv = wrap.typed mpvDef; in
{
  options.mypv = lib.mkOption { type = lib.types.submodule mpv.options; default = { }; };
  config.home.packages = lib.mkIf config.mypv.enable [ (mpv config.mypv) ];
}
```

### Composing Layers

Any wrapper is itself a package, so layers nest — the innermost runs closest to
the program and its `env`/`PATH` win:

```nix
wrap {
  package = wrap.withScript { package = pkgs.foo; args = [ "--fast" ]; };
  env.LOUD = "1";
}
```

`wrap.withScript` is often the natural inner layer because it is the only built-in
that supports `prefix`. `wrap.toShell { cmd = ...; }` (a no-build string
builder) is exposed for tests and inspection.

### Contributed backends

Other extensions can add callables to the same `wrap` object by registering an
entry in `substrate.settings.wrappers.backends`. The `jail` extension does exactly
this to provide `wrap.withBubblewrap { package; name?; permissions; }`:

```nix
config.substrate.settings.wrappers.backends.mybackend = {
  options = {
    flavor = lib.mkOption { type = lib.types.str; default = "plain"; };
  };
  build = { pkgs, ... }: cfg: /* cfg -> derivation */;
};
```

`options` is an attrset of mkOption declarations (or a full module body, or a
module function) merged over the common prelude — `package` (backends that wrap
a package must honor `config.package`), `passthru`, and an internal
`assertions` list for cross-field rules. The pipeline evaluates specs against
the interface, enforces assertions, calls `build { pkgs, lib, wrapLib } cfg`,
and attaches the standard passthru (`wrapped`/`override`/`files`).

A registered backend at key `foo` appears as the callable `wrap.withFoo` (mechanically
the key with its first letter capitalized), disappears when the contributing
extension is not loaded, is usable as a `wrap.typed` backend, and can become
the site's default via `settings.wrappers.defaultBackend`. Reserved names
(`shell`, `binary`, `script`, `typed`, `toShell`, `toStubFlags`, `types`) are
rejected. See the Jail Extension section for `wrap.withBubblewrap` usage.

## Creating Custom Extensions



Extensions are standard NixOS modules:

```nix
# extensions/my-extension/default.nix
{ lib, config, ... }:
{
  # Add new options
  options.substrate.settings.myOption = lib.mkOption {
    type = lib.types.str;
    default = "value";
    description = "My custom option";
  };

  # Add to supported classes (if adding a new class)
  config.substrate.settings.supportedClasses = [ "myClass" ];

  # Register output builders (global = once; perSystem = once per system)
  config.substrate.outputs.perSystem.myOutput = [
    {
build = { pkgs, system, substrate, ... }: {
  # Return attrset to merge into the flake output
};
    }
  ];

  # Register a finder
  config.substrate.finders.my-finder.find = cfgs:
    # Return list of modules
    [];

  # Push modules into builds (consumed by the builder for the declared class,
  # blind to the producing extension)
  config.substrate.settings.contributors = [
    {
class = "nixos";
contribute = { inputs, hostname, hostcfg, userConfigs, ... }: [
  # Return modules to append to each nixos configuration
  { }
];
    }
  ];
}
```

Export in `default.nix`:
```nix
{
  # ...existing exports...
  substrateModules = {
    # ...existing modules...
    my-extension = import ./extensions/my-extension;
  };
}
```
