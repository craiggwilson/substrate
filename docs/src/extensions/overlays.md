# Overlays Extension

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

---

See the [extension index](index.md) for the composition hooks and the full list.
