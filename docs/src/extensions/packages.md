# Packages Extension

Defines custom packages.

### Import

```nix
imports = [ inputs.substrate.substrateModules.packages ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.packages.namespace` | string | Namespace in overlay (default: `custom`) |
| `substrate.packages.internal` | attrs of entry | Packages available to substrate itself |
| `substrate.packages.publish` | attrs of entry | Packages to expose in public outputs |
| `substrate.packages` | lazy attrs of attrs of package | The published packages keyed by system. Set by the extension, not by you |

A package is named by its attribute key, not by a filename. An entry is either
a **path** to a package definition or a **function** of this context:

| Argument | Description |
|----------|-------------|
| `pkgs` | The package set being built |
| `lib` | nixpkgs `lib` |
| `inputs` | The consumer's flake inputs |
| `substrate` | The substrate configuration, for reading user settings |

Write function entries as `{ pkgs, ... }: ...` so they tolerate additions to
that set.

A function entry cannot be a bare derivation, because the substrate
configuration is evaluated once and system-independently, while a derivation is
system-specific and needs the package set that `settings.overlays` produces.
Deferring that step to the builder is what the function is for; substrate hands
the entry the package set it is contributing to.

```nix
substrate.packages.publish.my-tool = { pkgs, ... }: pkgs.mkDerivation { ... };
```

A path entry is `callPackage`'d, so a file written against a callPackage
argument keeps working exactly as it always has:

```nix
substrate.packages.publish.my-tool = ./pkgs/my-tool.nix;
```

Both forms land in the same attribute set, so either works and they can be mixed
freely in one configuration.

Note the split: behavior goes under `settings.*`, internal and published inputs
go under `substrate.packages.*`, and the evaluated result comes back under
`substrate.packages`.

### Output

- `packages.<system>.<name>` - Package derivations
- `overlays.packages` - Overlay adding packages under namespace

### Usage

```nix
substrate.settings.packages.namespace = "myproject";

substrate.packages = {
  internal.local-only = ./pkgs/local-only-tool.nix;

  publish = {
    my-tool = { pkgs, ... }: pkgs.callPackage ./pkgs/my-tool.nix { };
    another-tool = ./pkgs/another-tool.nix;
  };
};
```

Packages are available as `pkgs.myproject.my-tool`. The `publish` set also
reaches consumers through the `packages` output and the `overlays.packages`
overlay; the `internal` set is deliberately absent from both.

## Declaring packages as modules

This is the ergonomic route, and the one to reach for by default.

An entry is a value, so a module can assign one. A package therefore lives in
the same module tree as everything else, merges by the same rules, and can be
picked up by a tree import:

```nix
# packages/my-tool.nix
_: {
  substrate.packages.publish.my-tool = { pkgs, ... }: pkgs.mkDerivation { ... };
}
```

```nix
imports = [ (inputs.import-tree ./packages) ];
```

There is no suffix handling and no path building anywhere: the module states the
name it wants and the tree import does the rest. Dropping a file into
`./packages` registers a package; removing it unregisters one. Two modules may
contribute to the same package, and `mkOverride`/`mkForce` work as usual,
because it is only an option.

Because everything is an option, such a module can do more than define a
package — read settings, declare its own, or contribute to a module tree:

```nix
{ config, ... }: {
  substrate.packages.publish.my-tool =
    { pkgs, ... }:
    pkgs.callPackage ./my-tool.nix { };
}
```

## Standalone package files

The other route is a file that is not a module — a bare path holding nothing but
the package:

```nix
substrate.packages.publish.my-tool = ./pkgs/my-tool.nix;
```

Nothing in substrate has to change when one is added, but a path list is not
something the module system can merge, so you have to collect them. Writing the
walk is a few lines:

```nix
substrate.packages.publish = lib.listToAttrs (
  lib.map (f: lib.nameValuePair (lib.removeSuffix ".nix" f) ./pkgs/${f}) (
    lib.filter (n: lib.hasSuffix ".nix" n) (lib.attrNames (builtins.readDir ./pkgs))
  )
);
```

Note that `builtins.readDir` reports an entry's kind as a bare string on Nix
2.35 and later and as `{ type = ...; }` before that, so a walk that inspects
kinds needs to handle both.

The trade is purity for convenience. A standalone file is a package and nothing
else — readable without knowing about substrate, importable on its own. A module
gives up that independence in exchange for merging, tree imports, and no
collection logic at all. Both routes reach the same attribute set.

---

See the [extension index](index.md) for the composition hooks and the full list.