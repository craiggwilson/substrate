# Packages Extension

Defines custom packages.

### Import

```nix
imports = [ inputs.substrate.substrateModules.packages ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.settings.publish.packages` | list of paths | Package definition files to publish |
| `substrate.settings.packageNamespace` | string | Namespace in overlay (default: `custom`) |
| `substrate.packages` | lazy attrs of attrs of package | The published packages keyed by system. Set by the extension, not by you |

Note the split: inputs go under `settings.publish.*`, and the evaluated result
comes back under `substrate.packages`. There is no `settings.packages` option.

### Output

- `packages.<system>.<name>` - Package derivations
- `overlays.packages` - Overlay adding packages under namespace

### Usage

```nix
substrate.settings = {
  publish.packages = [
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

---

See the [extension index](index.md) for the composition hooks and the full list.
