# Wrappers Extension

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
run before the chain, or a different program to wrap. See
[Contributors](#contributors) for the contract.

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
| `incompatible` | list of core field names | Fields this contributor's shape cannot honor. Setting one is an error, never a silent omission. |

Every hook's context is the build context a builder hands the configuration, plus
what the contributor adds:

```nix
{
  # the build context a builder hands the configuration: `config` is the
  # configuration this wrapper is built for, and the rest is what
  # extraArgsGenerators receive
  inherit (buildContext) config hostcfg usercfg inputs pkgs;

  # nixpkgs lib under the shared core vocabulary, plus the names to pass
  # past a scrubbed environment
  inherit (wrapContext) lib wrapLib forwarded;
}
```

The hooks receive that attrset merged with whatever this contributor's own
`context` hook returns.

`config` is why a contributor can read the configuration it is built for: the
secrets extension renders its manifest from `config.secretspec`, which is
the same options its class module rendered it from, so a wrapper names only its
scope and lands on the same store path. A hook that reads `config` ties its
wrapper to that configuration — fine for reading options, a cycle if it reads
something derived from the wrapper itself.

Every hook receives the whole resolved spec, so a contributor can honor the
vocabulary through its own mechanism — but it should reach for another
contributor's effect through `ctx.forwarded`, not by reading that contributor's
options. No contributor may ignore a field: it either renders it, or declares it
`incompatible`, or the wrapper is an error.

The core vocabulary has nothing in it that a contributor has to re-derive: the
secrets extension turns `scope` into an exec-chain prefix, renders the manifest
from the configuration it is built for, and puts the provider CLIs on `PATH`; the
bubblewrap extension replaces the program with a jail launcher and translates
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

---

See the [extension index](index.md) for the composition hooks and the full list.
