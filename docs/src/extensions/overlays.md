# Overlays Extension

Manages nixpkgs overlays.

### Import

```nix
imports = [ inputs.substrate.substrateModules.overlays ];
```

### Options

| Option | Type | Description |
|--------|------|-------------|
| `substrate.overlays` | list | Overlays applied to the package sets substrate builds, but not published |
| `substrate.publish.overlays` | attrs of overlay | Named overlays exposed under the `overlays` output |

`substrate.settings.overlays` is core: builders bake it into every package set
substrate creates, so it exists whether or not this extension is loaded. The
extension applies `substrate.overlays` to package sets and keeps the separately
named `substrate.publish.overlays` set for the `overlays` output. Published
overlays are also applied to package sets.

### Usage

```nix
substrate.overlays = [
  (final: prev: {
    myPackage = prev.callPackage ./pkgs/my-package { };
  })
];

substrate.publish.overlays.default = inputs.some-flake.overlays.default;

substrate.settings.overlays = [
  (final: prev: {
    # User overlays still fit here.
  })
];
```

Published overlays are also exposed as the flake output `overlays.<name>`.

---

See the [extension index](index.md) for the composition hooks and the full list.
