# Shells Extension

Defines development shells built with `mkShell`. Orthogonal to the
[devenv extension](devenv.md), which builds shells with devenv instead; both
write to `devShells`, so load either or both — just don't claim the same shell
name twice.

### Import

```nix
imports = [ inputs.substrate.substrateModules.shells ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.shells.internal` | attrs of entry | Shells substrate defines but does not publish |
| `substrate.shells.publish` | attrs of entry | Shells exposed under `devShells` |

A shell is named by its attribute key, not by a filename. An entry is either a
**path** to a shell definition or a **function** of this context:

| Argument | Description |
|----------|-------------|
| `pkgs` | The package set for the system being built |
| `system` | The system being built, e.g. `x86_64-linux` |
| `lib` | nixpkgs `lib` |
| `inputs` | The consumer's flake inputs |
| `substrate` | The substrate configuration, for reading user settings |
| `stdenv` | The system's stdenv |

Write function entries as `{ pkgs, ... }: ...` so they tolerate additions to
that set.

A path entry is imported with that context, so a shell file reads the same
whichever form you use. A directory works too — importing one resolves its
`default.nix` — which is what makes `shells/rust/` a shell named `rust`:

```nix
substrate.shells.publish.rust = ./shells/rust;
```

### Output

- `devShells.<system>.<name>` - Development shells

### Usage

```nix
substrate.shells.publish = {
  default = { pkgs, ... }:
    pkgs.mkShell {
      packages = with pkgs; [
        git
        just
      ];
    };

  rust = { pkgs, ... }:
    pkgs.mkShell {
      packages = with pkgs; [
        rustc
        cargo
        rust-analyzer
      ];
    };
};
```

`devShells.x86_64-linux.default` and `devShells.x86_64-linux.rust` come out of
that. A package from a substrate overlay is reachable through the `pkgs` each
entry is handed, so `pkgs` here is the same package set the rest of the
configuration builds against.

## Declaring shells as modules

This is the ergonomic route, and the one to reach for by default.

An entry is a value, so a module can assign one, and a shell can live in the
same module tree as everything else:

```nix
# shells/rust.nix
_: {
  substrate.shells.publish.rust = { pkgs, ... }: pkgs.mkShell { packages = with pkgs; [ rustc cargo ]; };
}
```

```nix
imports = [ (inputs.import-tree ./shells) ];
```

There is no suffix handling and no path building anywhere: the module states the
name it wants and the tree import does the rest. Dropping a file into `./shells`
registers a shell.

## Standalone shell files

The other route is a file that is not a module — a bare path, imported with the
entry context:

```nix
substrate.shells.publish.rust = ./shells/rust;
```

A directory works too, since importing one resolves its `default.nix`, so
`shells/rust/default.nix` is a shell named `rust`. Nothing in substrate has to
change when one is added, but as with packages a path list is not something the
module system can merge, so collecting them means writing the same `readDir`
walk described in the [packages extension](packages.md#standalone-package-files).

The trade is the same: purity for convenience. A standalone file is a shell and
nothing else; a module merges, tree-imports, and needs no collection logic. Both
routes reach the same attribute set.

---

See the [extension index](index.md) for the composition hooks and the full list.