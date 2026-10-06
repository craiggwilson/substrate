# Secrets Extension

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

### Runtime files (`entries.<name>.file`)

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

---

See the [extension index](index.md) for the composition hooks and the full list.
