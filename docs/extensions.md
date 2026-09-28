# Extensions

Extensions add capabilities to substrate. Import only what you need.

## Available Extensions

| Extension | Import Path | Description |
|-----------|-------------|-------------|
| `home-manager` | `substrateModules.home-manager` | Home Manager configuration builder |
| `nixos` | `substrateModules.nixos` | NixOS configuration builder |
| `tags` | `substrateModules.tags` | Tag-based module filtering |
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
reads the options declared beside it (see "Composition Hooks" in the wrappers
section). nixpkgs passes argument values through verbatim rather than applying
them, so a generator cannot hand over a closure to be called later either.

`wrappers.contributors` is the same push pattern one level down: an *extension*
extends another extension's API. The `wrappers` extension owns the `wrap`
module argument but never references `jail-nix`; the `jail` extension registers
a contributor, and `wrap.package { bubblewrap.permissions = …; }` is only valid when
`jail` is loaded. A contributor declares its own `options` (validated by
`wrappers`, so error messages stay consistent) and what it contributes to a
wrapper — chain fragments, `PATH` entries, or a different program to wrap. Its
hooks receive the configuration the wrapper is built for, which is what lets a
contributor read the options declared next to it.

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
[jail.nix](https://git.sr.ht/~alexdavid/jail.nix), primarily as the
`bubblewrap` wrapper contributor (see the Wrappers Extension). It also exposes
the raw pkgs-bound jail.nix callable as `jailLib` for integrations the
contributor does not cover, such as `jailLib.mkOverlay`.

### Import

```nix
imports = [ inputs.substrate.substrateModules.jail ];
```

Requires a `jail-nix` input — resolved by the usual precedence: an explicit
`jail-nix` argument, `substrate.settings.inputs."jail-nix"`, or a flake input
named `jail-nix`. The `bubblewrap` contributor additionally requires the
`wrappers` extension; without it jail is available only through `jailLib`.

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.jail.basePermissions` | function or null | Base permissions all jails inherit |
| `substrate.settings.jail.additionalCombinators` | function or null | Custom combinators exposed to jail definitions |

### Wrapping in a jail

With the `wrappers` extension loaded, jail registers the `bubblewrap`
contributor. Its `permissions` go straight to jail.nix — either a list of
combinators or a function receiving them:

```nix
{ pkgs, wrap, ... }:
{
  home.packages = [
    (wrap.package {
      package = pkgs.firefox;
      bubblewrap.permissions = c: with c; [
        network
        gui
        (readwrite "$HOME/.mozilla")
      ];
    })
  ];
}
```

The contributor replaces the program with a jail launcher (named after the
wrapper, so `<pkg>-isolated` by default) and translates the wrapper's own
vocabulary into jail permissions, because a jailed program sees none of it
otherwise: `env` becomes `--setenv`, `runtimeInputs` become `PATH` entries with
their closures bound, and `files` are bound at the store paths the spec resolved
them to.

jail.nix's base permissions clear the environment, so anything the wrapper put
there has to be named back in:

| What | How it crosses |
|------|----------------|
| The spec's `env` | `--setenv NAME "value"` — known at build time |
| Another contributor's `envNames` | `try-fwd-env NAME` — forwarded by value, so nothing about a resolved secret reaches the bwrap command line |
| `bubblewrap.forwardEnv` | `try-fwd-env NAME`, for a variable that came from outside the wrapper |

| Option | Description |
|--------|-------------|
| `bubblewrap.permissions` | jail.nix permissions: a list of combinators, or a function receiving them. `null` means the base permissions alone. |
| `bubblewrap.forwardEnv` | Names to pass through the cleared environment that no contributor advertised — a variable your own `prefix` chain introduced, or one an interactive session provides that a systemd unit would not. Unset names are simply absent inside the jail. |

Prefer `secrets.scope` over naming a secret's variable here: only the chain knows
when a secret is resolved.

To jail an already-wrapped program, nest the calls — each is one wrapper:

```nix
wrap.package {
  package = wrap.package { package = pkgs.foo; env.X = "1"; };
  bubblewrap.permissions = [ ];
}
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
| `secretspec.entries.<name>` | Secret declaration (description, required, default, prompt, asPath, composed, providers, ref) and optional `file` materialization policy (path, fileOwner, fileGroup, mode) |
| `secretspec.project` | Project name recorded in the manifest, which SecretSpec uses to address provider credentials. Defaults to the class module's identity — the hostname on NixOS, the username under Home Manager — so the render stays a pure function of these options |
| `secretspec.manifestPath` | Where the manifest is read from at runtime; `null` reads it from the store |
| `secretspec.providers.<alias>` | Provider URI and optional provider credentials |
| `secretspec.scopes.<name>.secrets` | Allowlist of entries a service may receive |
| `secretspec.defaultProviders` | Fallback chain for entries without their own providers |

`description` is required on every entry: SecretSpec rejects the whole manifest
when a secret has none, so the renderer fails at eval instead.

The manifest holds declarations only, so by default it is read **straight from
the store** (`/nix/store/…-secretspec.toml`): nothing is placed on disk, nothing
is activated, and there is no activation ordering to reason about. Every consumer
points at that path — the materialization unit's `--file`, `$SECRETSPEC_FILE`
under Home Manager, and every secretspec invocation in a wrapper built in that
configuration.

Because the render is a pure function of these options, anything that needs the
manifest can reproduce it: a wrapper reads `config.secretspec` and lands on the
same store path, rather than being told where it is. That is why the class
modules publish nothing back into substrate settings.

`secretspec.manifestPath` asks for a path on disk instead, and moves every
consumer with it:

```nix
secretspec.manifestPath = "/var/lib/secrets/secretspec.toml";
```

The path is honored verbatim, wherever it points: the manifest is linked there
with a systemd tmpfiles symlink (system on NixOS, user under Home Manager), and
its parent directory is created if missing. No special cases for `/etc` or the
config home.

Reading from the store is GC-safe: the path is interpolated, so the manifest is an
input of whatever references it (each stub, the materializer unit, HM's
`$SECRETSPEC_FILE`). On NixOS `$SECRETSPEC_FILE` is set on the unit only — a host
with no stubs and no `file` entries has no consumer and so nothing to keep alive.

`secretspec` is installed automatically. A provider that shells out to an
external CLI names it beside its URI, which is the extension's only notion of a
provider:

```nix
secretspec.providers.team = {
  uri = "onepassword://Prod";
  package = pkgs._1password-cli;   # the CLI; omitted for keyring://
  credentials = { … };
};
```

Because `package` is a package of the configuration's own module, it comes from
that host's `nixpkgsConfig` instance. The extension stays provider-agnostic: it
only knows that a provider may bring a CLI.

Every declared secret must already exist in its provider — the extension never
generates or mints values.

### Usage

```nix
# a nixos-class module declares what it needs and wraps its service:
{ pkgs, lib, wrap, ... }:
{
  secretspec = {
    providers.team = {
      uri = "onepassword://Prod";
      # How the 1Password service account token reaches secretspec; see
      # "Service account tokens" below.
      credentials.service_account_token = "systemd-credential://";
    };
    entries.GITHUB_TOKEN = {
      description = "GitHub API token";
      providers = [ "team" ];
      ref = { item = "GitHub"; field = "token"; };
    };
    scopes.github-mcp.secrets = [ "GITHUB_TOKEN" ];
  };

  systemd.services.github-mcp = {
    # systemd hands the unit its own copy of the token, readable only by this
    # service, from a root-only file on disk.
    serviceConfig.LoadCredential = [ "service_account_token:/etc/secrets/service_account_token" ];
    serviceConfig.ExecStart = lib.getExe (
      wrap.package {
        package = pkgs.github-mcp;
        secrets.scope = "github-mcp";
      }
    );
  };

  # or, in a Home Manager module:
  home.packages = [
    (wrap.package {
      package = pkgs.github-mcp;
      secrets.scope = "github-mcp";
    })
  ];
}
```

Home Manager class modules use the same options; in shells the CLI works
directly (`secretspec get NAME`, `eval "$(secretspec export)"`) because
`$SECRETSPEC_FILE` points at the generated manifest.

### Service account tokens

A provider that authenticates with a token (1Password service accounts, Vault,
Bitwarden Secrets Manager, cloud secret managers, ...) declares a credential
per semantic name. SecretSpec reads the token at resolution time and passes it
to the provider's own CLI or API in memory — it is never exported into the
resolved process's environment, and never into the manifest.

Two forms, both in `secretspec.providers.<alias>.credentials`:

```nix
# a bare provider spec: read at that provider's convention address,
# {project}/_provider/{credential name}
credentials.service_account_token = "keyring";

# a table: pin an explicit address in the source provider
credentials.service_account_token = {
  provider = "file:/etc/secrets";
  ref.item = "service_account_token";
};
```

`ref` takes the same coordinates as an entry's `ref` (`vault`, `item`, `field`,
`section`, `version`), so the token can equally live in an item field of another
store — e.g. `{ provider = "onepassword"; ref.item = "op-sa"; field = "token"; }`
for a desktop session that unlocks through the 1Password app.

Sources, and how each is provisioned:

| Context | `service_account_token` | Provisioning |
|---------|-------------------------|--------------|
| systemd unit | `"systemd-credential://"` | `serviceConfig.LoadCredential = [ "service_account_token:/etc/secrets/service_account_token" ]`, set on **every** unit that resolves (including `secretspec-materialize`). systemd copies the file into a service-private directory at start and exports `$CREDENTIALS_DIRECTORY`; the credential's `ID` is the filename, which is why it must be spelled `service_account_token`. `LoadCredentialEncrypted=` takes a `systemd-creds` blob instead (TPM2- or key-sealed), which is the one form safe to keep in a repo. |
| interactive shell / desktop | `"keyring"` | `secretspec config provider login <alias>` stores it in the OS keyring at `{project}/_provider/service_account_token`. |
| wrappers, cron, one-off commands, containers | `{ provider = "file:…"; ref.item = "…"; }` | A token file you place yourself. Works for any process, with no systemd and no unlocked keyring. |
| CI, containers, ad-hoc shells | *nothing declared* | `op` reads `OP_SERVICE_ACCOUNT_TOKEN` from the environment. |
| desktop app integration | *nothing declared* | `op` unlocks through the 1Password app (`programs._1password` on NixOS, `programs._1password-gui` under Home Manager) — no token at all. |

Notes that save an hour:

- **`onepassword+token://` is not needed.** The scheme is accepted but inert;
  since 0.19 a token in the URI is rejected outright (`onepassword+token://token@vault`),
  because URIs end up in committed manifests, shell history and CI logs. Keep
  `uri = "onepassword://Vault"` and declare the credential.
- **A bare-string `file:` source nests.** Its convention address is
  `<root>/<project>/_provider/<credential name>`, and substrate sets `project` to
  the hostname (NixOS) or the username (Home Manager). Use the table form when
  you want a fixed path.
- **Bytes are verbatim.** No trimming, so no trailing newline in a token file
  (`printf %s "$TOKEN" > …`, not `echo`).
- **Two files for two privilege levels.** Root and user scopes need different
  permissions, so declare the source per class: `/etc/secrets/…` (0400 root) for
  NixOS, `~/.config/secretspec/…` (0600 you) for Home Manager. It is the same
  1Password service account either way, so this is a local boundary only —
  issue a separate token per user if you want 1Password-side scoping.
- **Keeping host paths out of the flake.** A credential source may name an alias
  that exists only in `~/.config/secretspec/config.toml` (project aliases win,
  then user-global ones), so the committed manifest can say
  `credentials.service_account_token = "opToken"` and each machine resolves
  `opToken` locally.
- **Your own units need `op` too.** A provider's `package` reaches the units and
  stubs substrate builds; for a unit of your own use
  `systemd.services.<name>.path = [ pkgs._1password-cli ]`, and for a desktop
  session add it to `home.packages`.
- **A provider's `package` is a package, so it is the configuration's own.**
  Substrate's evaluation has a different package set from each NixOS/Home Manager
  configuration, which is why the CLI is declared in the target's module rather
  than once beside substrate's settings.

### As a wrapper contributor

When the wrappers extension is also loaded, secrets joins in as a contributor:
`wrap { package; secrets.scope; … }` puts secretspec's invocation in the
wrapper's exec chain, so the command's environment is populated at exec time
from the generated manifest.

The invocation goes **outside** anything else in the chain, because secretspec
needs the provider CLIs, the keychain and the network to resolve anything at
all, and because `--scope` both injects the scope's values and strips every
other secret from the child environment.

The manifest is not named anywhere: the contributor renders it from
`ctx.config.secretspec` — the same options the class module rendered it
from, producing the same store path — and reads the scope's declarations from
there too. Nothing is published back into substrate settings, and there is no
build-context fallback, so a wrapper only works in a configuration that actually
declares `secretspec`.

| Option | Description |
|--------|-------------|
| `secrets.scope` | Scope resolved at exec time; must be declared in `secretspec.scopes`, checked at eval time. |
| `secrets.reason` | Audit-reason string; defaults to `"runtime resolution for scope <scope>"`. |
| `secrets.manifest` | Read the manifest from here instead. `null` (the default) renders it from this configuration — same name, same content, same store path. Set it for a manifest placed on disk (`secretspec.manifestPath`) or written by a different configuration. |

Secrets names no variables of its own: a scope's are only known once secretspec
has run, so a wrapper that also jails names them where they are forwarded (see
`bubblewrap.forwardEnv`).

Everything else about the wrapper — `env`, `args`, `files`, `prefix`, and any
other contributor — belongs to the spec itself, in one call:

```nix
wrap.package {
  package = pkgs.rclone;
  env = plaintextEnv;
  secrets.scope = "rclone";
}
```

### Runtime files (entries.<name>.file)

For consumers that must read a *file path* (module options taking
`EnvironmentFile`-style paths, scripts doing `$(cat …)`), an entry can carry
a materialization policy; `null` means env/CLI consumption only:

```nix
secretspec.entries.githubApiToken.file = { };  # defaults below
```

| Option | Default | Description |
|--------|---------|-------------|
| `path` | `/var/lib/secretspec/files/<name>` (NixOS) / `~/.local/state/secretspec/files/<name>` (HM) | Runtime file target; never a Nix store path |
| `fileOwner` | `root:root` (NixOS) / `<user>:users` (HM) | Ownership of the materialized file |
| `mode` | `0600` | Permissions, octal |

The resolution is still runtime: a oneshot service fetches each materialized
entry (as `secretspec get <NAME>` against that class's manifest) and installs it
atomically with the entry's owner and mode —
`systemd.services.secretspec-materialize` on NixOS (ordered after network),
`systemd.user.services.secretspec-materialize` under Home Manager. Its PATH is
the CLIs of the providers its entries can reach, plus the CLI itself, so
providers resolve there too. Ordering with consumers is explicit
(`after = [ "secretspec-materialize.service" ]`). `asPath` and `file` are
mutually exclusive — `asPath` trades persistent files for exec-time temp paths.
Values never appear in the Nix store; the materialized file only exists at
runtime.

### Runtime Model

- A secrets wrapper runs its command under `secretspec run` scoped to one
  scope; resolved values are injected into the child's environment at exec
  time.
- SecretSpec resolves an XDG config directory before it reads anything, and
  fails every call without one. A systemd unit has no `HOME` to derive it from,
  so the runtime contexts this extension builds supply one when the caller has
  neither `HOME` nor `XDG_CONFIG_HOME`: the NixOS materializer unit gets
  `XDG_CONFIG_HOME`/`XDG_STATE_HOME` = `/var/lib`, and so does a secrets wrapper
  stub built for a host (the unit-run case, e.g. an `ExecStartPre`). Each program
  appends its own name under those plain roots — SecretSpec writes
  `/var/lib/secretspec/{config.toml,audit.log}`, a provider CLI writes
  `/var/lib/op/config` — and `/var/lib/secretspec` is created `0700 root`.
  Wrappers built for a user configuration get no fallback (they run with a
  `HOME`), and an interactive session keeps its own directories either way.
- Entries with `asPath = true` are materialized as temporary files at
  resolution, for consumers that insist on a path.
- Manifest references are store-visible (vault/item/field names, like
  sops-nix filenames); values are not.
- Provider credentials are the bootstrap secret: the extension renders *where*
  each one is read from (see "Service account tokens") but never holds the value
  itself. Provision it out of band — a file you place, a systemd credential, the
  OS keyring, or the environment.
- Scopes minimize secret delivery; they are not an authorization boundary.

## Wrappers Extension

### Overview

Provides `wrap` — a module argument bound to the configuration it is built for,
for declaratively wrapping executables: inject environment variables, prepend CLI
args, and chain exec prefixes. One call, one wrapper.

`wrap` is published by a **class module** (a module contributed into each
configuration the wrappers extension supports), not by an `extraArgsGenerator`,
because it closes over that configuration: a contributor hook reads the options
declared beside it. A generator runs in the builder, outside the configuration
being built, so there is no config there to name — and nixpkgs passes argument
values through verbatim rather than applying them, so a closure would arrive
unapplied. `jailLib` is still a generator argument; it needs only `pkgs`.

A spec is the **core vocabulary flat at the top level**, plus **at most one key
per contributor it names**:

```nix
wrap.package {
  package = pkgs.rclone;
  env = plaintextEnv;
  args = [ "--config" "rclone.conf" ];
  secrets.scope = "rclone";
  bubblewrap.permissions = c: with c; [ base gui ];
}
```

Contributors are how extensions extend wrapping: they join in by name
(`secrets.scope`, `bubblewrap.permissions`), are ordered by a `priority` they
declare, and may only *add* — exec-chain fragments, `PATH` entries, a snippet
run before the chain, or a different program to wrap. See "Contributed
contributors" for the contract.

Each call returns a derivation you install through your usual mechanism
(`home.packages`, `environment.systemPackages`, a systemd unit, ...).

### Import

```nix
imports = [ inputs.substrate.substrateModules.wrappers ];
```

### The vocabulary

| Option | Description |
|--------|-------------|
| `package` | **Required.** The derivation to wrap; resolved with `lib.getExe`, or `bin/<exe>` when `exe` is set |
| `stub` | `makeWrapper` (default, a shell stub) or `makeBinaryWrapper` (a compiled one) |
| `env` | Attrset of exported variables (shell-escaped) |
| `args` | CLI args prepended before `"$@"` |
| `runtimeInputs` | Packages added to the wrapper's `PATH` |
| `prefix` | Raw exec-line fragments between the program and any contributor's chain (launchers, session managers) |
| `name` | Rename the wrapper command; the executable it replaces is removed rather than left beside it (`aliases` is the additive way to keep both) |
| `exe` | Pick a specific binary under `bin/` (when `meta.mainProgram` isn't it) |
| `files` | Declarative files materialized into the wrapper (below) |
| `aliases` | Extra `$out/bin` names symlinked to the wrapper |
| `preHook` | Shell run before the program starts (via makeWrapper `--run`) |
| `postHook` | Shell run after the program, with its exit code in `$?` and that code handed back |
| `passthru` | Merged into the result's `passthru` |

Fields nobody declared are rejected by the module system — no silent drops, no
builder-time validation. There is one mode: **a wrapper wraps a package**. Writing
a script is nixpkgs' job, and wrapping the result works like anything else:

```nix
wrap.package {
  package = pkgs.writeShellApplication { name = "ff"; runtimeInputs = [ … ]; text = ''…''; };
}
```

### The shape

One shape: the output is the **package tree** (`symlinkJoin`) with one
executable replaced by the stub, plus `.<name>-core` when `args` or `preHook`
need a `makeWrapper`ed program. With nothing for the core to carry, there is no
second file and the stub execs the program directly.

Desktop `Exec=` entries are rewritten to route through the wrapper, and
completions, `man` pages and other binaries come along, whether or not a
contributor contributed a prefix, a setup snippet, or a different program. Adding
a property to a spec never costs you anything in the output.

The tree is the package's default output plus whatever it declares in
`meta.outputsToInstall`, so a package keeping its manual in a separate `man`
output (rclone, fzf) keeps it when wrapped, and a package holding outputs it
declines to install (ghostty's `terminfo`, `vim`) does not gain them. The
wrapper itself is one `out` whatever it links.

`env`/`runtimeInputs` are exported by the stub, above the chain, so a chain member
can read them. `args`/`preHook` go to the **innermost** point — the core, right
before the program — so `"$VAR"` in an `arg` expands *after* everything the chain
resolved. That is what lets `secrets` inject a token into a variable the wrapper
then references in its arguments.

`stub = "makeBinaryWrapper"` writes a compiled stub, which cannot run an exec
chain. Pairing it with a `prefix`, a setup snippet, or a contributor that supplies
a different program is an error naming both sides, never a silently dropped
prefix; everything else it carries is the same vocabulary as flags.

### Files

`files.<relpath>` materializes a file and links it into the wrapper output at
`$out/<relpath>`, verbatim — the "ship the config inside the derivation"
escape from `$HOME`:

```nix
wrap.package {
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
{ pkgs, wrap, ... }:
let
  # replace claude-code, keep its completions, add a flag
  claude = wrap.package {
    package = pkgs.claude-code;
    args = [ "--mcp-config" "$HOME/.claude/mcp-servers.json" ];
  };

  # secrets resolution at exec time (with the secrets extension loaded)
  mcp = wrap.package {
    package = pkgs.github-mcp-server;
    secrets.scope = "github-mcp";
  };

  # arbitrary exec-chain prefix
  launch = wrap.package {
    package = pkgs.thing;
    prefix = [ "uwsm app --" ];
  };

  # a script is a package; wrapping one is like wrapping anything else
  ff = wrap.package {
    package = pkgs.writeShellApplication {
      name = "ff";
      runtimeInputs = [ pkgs.ripgrep pkgs.fzf pkgs.bat ];
      text = ''
        rg --ignore-case "$@" | fzf --ansi
      '';
    };
    name = "ff";
  };
in
{
  home.packages = [ claude mcp launch ff ];
}
```

Every result carries `passthru.wrapped` (the package the caller asked to wrap),
`passthru.override` (rebuild the wrapper around an overridden package), and
`passthru.files` (name → store path of each materialized file).

### Contributors

Anything that adds to a wrapper is a *contributor*, registered in
`substrate.settings.wrappers.contributors` and selected by naming its key in the
spec. Each entry is an attrset:

| Attribute | Values | Meaning |
|-----------|--------|---------|
| `priority` | integer, **required** | Order in the exec chain; lower sits further from the program, so its chain runs first. Two selected contributors may not share one — the order would be arbitrary, so it is an error. |
| `options` | mkOption attrset, module body, or module function | The contributor's own options, which become the submodule under its key (`secrets.scope`, `bubblewrap.permissions`). Wrong fields are module errors. |
| `prefix` | `ctx: spec -> [ string ]` | Exec-chain fragments, ahead of the spec's own `prefix`. |
| `runtimeInputs` | `ctx: spec -> [ package ]` | Packages added to the wrapper's `PATH`. |
| `setup` | `ctx: spec -> string` | Shell run in the stub before the chain — for anything conditional a prefix cannot express. |
| `program` | `ctx: spec -> package -> derivation` | The package to wrap instead of `spec.package`. Innermost contributor first, so several compose outward in priority order. |
| `envNames` | `ctx: spec -> [ string ]` | Environment variables this contributor's chain introduces. Handed to every contributor as `ctx.forwarded`, so one that scrubs the environment can pass them on. A contributor that cannot know its names ahead of time (secrets, whose values are resolved at exec time) leaves this empty and lets the spec name what to forward. |
| `context` | `ctx: attrs` | Anything else the contributor needs (its own libraries, say), merged into the context its hooks receive. |

Every hook's context is the build context a builder hands the configuration, plus
what the contributor adds:

```nix
ctx = {
  config;  # the configuration this wrapper is built for
  hostcfg; usercfg; inputs; pkgs;   # what extraArgsGenerators receive
  lib; wrapLib;                    # nixpkgs lib; the shared core vocabulary
  forwarded;                       # names to pass past a scrubbed environment
} // <this contributor's context hook>
```

`config` is why a contributor can read the configuration it is built for: the
secrets extension renders its manifest from `config.secretspec`, which is
the same options its class module rendered it from, so a wrapper names only its
scope and lands on the same store path. A hook that reads `config` ties its
wrapper to that configuration — fine for reading options, a cycle if it reads
something derived from the wrapper itself.
| `incompatible` | list of core field names | Fields this contributor's shape cannot honor. Setting one is an error, never a silent omission. |

Every hook receives the whole resolved spec, so a contributor can honor the
vocabulary through its own mechanism — but it should reach for another
contributor's effect through `ctx.forwarded`, not by reading that contributor's
options. No contributor may ignore a field: it either renders it, or declares it
`incompatible`, or the wrapper is an error.

The core vocabulary has nothing in it that a contributor has to re-derive: the
secrets extension turns `scope` into an exec-chain prefix, renders the manifest
from the configuration it is built for, and puts the provider CLIs on `PATH`; the
jail extension replaces the program with a jail launcher and translates
`env`/`runtimeInputs`/`files` into jail permissions, because a jail cannot see
the wrapper's own tree.

Two contributors that both contribute a prefix compose into one wrapper — which
is the whole point:

```nix
# one derivation, one chain:
#   exec secretspec run … -- bwrap … -- prog "$@"
wrap.package {
  package = pkgs.foo;
  secrets.scope = "github";
  bubblewrap.permissions = c: with c; [ base ];
}
```

Stacking different shapes is still just nesting calls, one wrapper each:

```nix
wrap.package {
  package = wrap.package {
    package = pkgs.foo;
    secrets.scope = "github";
  };
  bubblewrap.permissions = c: with c; [ base ];
}
```

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
