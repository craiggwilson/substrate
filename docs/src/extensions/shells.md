# Shells Extension

Defines development shells.

### Import

```nix
imports = [ inputs.substrate.substrateModules.shells ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.publish.shells` | list of paths | Shell definition files to publish |

The list is of paths, and the `devShell` attribute name comes from the file's
basename — so shells are identified by where they live, not by a key you write.

### Output

- `devShells.<system>.<name>` - Development shells

### Usage

```nix
substrate.settings.publish.shells = [
  ./shells/default.nix
  ./shells/rust.nix
];
```

Shell file format:
```nix
# shells/rust.nix
{ pkgs, ... }:
pkgs.mkShell {
  packages = with pkgs; [
    rustc
    cargo
    rust-analyzer
  ];
}
```

---

See the [extension index](index.md) for the composition hooks and the full list.
