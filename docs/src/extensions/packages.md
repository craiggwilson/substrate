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
| `substrate.packages.internal` | list of paths | Package definition files available to substrate itself |
| `substrate.packages.publish` | list of paths | Package definition files to expose in public outputs |
| `substrate.packages` | lazy attrs of attrs of package | The published packages keyed by system. Set by the extension, not by you |

Note the split: behavior goes under `settings.*`, internal and published inputs
go under `substrate.packages.*`, and the evaluated result comes back under
`substrate.packages`.

### Output

- `packages.<system>.<name>` - Package derivations
- `overlays.packages` - Overlay adding packages under namespace

### Usage

```nix
substrate.packages = {
  internal = [
    ./pkgs/local-only-tool.nix
  ];
  publish = [
    ./pkgs/my-tool.nix
    ./pkgs/another-tool.nix
  ];
};

substrate.settings.packages.namespace = "myproject";
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

---

See the [extension index](index.md) for the composition hooks and the full list.
