# Jail Extension

Adds bubblewrap isolation via
[jail.nix](https://git.sr.ht/~alexdavid/jail.nix), primarily as the
`bubblewrap` wrapper contributor (see the [Wrappers](wrappers.md) extension). It also exposes
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
  generic =
    { jailLib, ... }:
    {
      config = {
        nixpkgs.overlays = [
          (
            final: prev:
            jailLib.mkOverlay {
              inherit final prev;
              packages = c: with c; { firefox = [ network gui gpu ]; };
            }
          )
        ];
      };
    };
};
```

`jailLib` is the result of `jail-nix.lib.extend` applied with the build's
`pkgs` plus `basePermissions`/`additionalCombinators` from the options above.

---

See the [extension index](index.md) for the composition hooks and the full list.
